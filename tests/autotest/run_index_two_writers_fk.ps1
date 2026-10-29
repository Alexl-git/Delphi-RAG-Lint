<#
  run_index_two_writers_fk.ps1 -- TWO WRITERS ON ONE INDEX DB (backlog item 12).

  THE DEFECT
  ---------------------------------------------------------------------------
  Every post-walk resolve pass (call targets, ancestry, helpers, unit-use
  targets, dispatch) read its candidate universe -- symbol ids -- BEFORE its
  write transaction and wrote those ids INSIDE it. FireDAC's default is
  BEGIN DEFERRED, so the write lock was only taken at the pass's first write.
  A second writer (plugin job, `index --watch`, another agent session) that
  committed a per-file reindex in between deleted the file's symbols and
  re-inserted them with NEW ids; the pass then wrote a call_edges row naming a
  dead id and SQLite raised `FOREIGN KEY constraint failed` (the DB rolled back
  clean, which is why the sighting looked like a ghost). Ancestry has no FK on
  type_ancestors.ancestor_symbol_id, so there the same race wrote a WRONG id
  silently.

  THE FIX: the writer connection starts every transaction with BEGIN IMMEDIATE
  (TxOptions.Isolation = xiSnapshot) and each pass starts its transaction
  ABOVE its candidate reads, so reads and writes share one snapshot under one
  lock; a second writer waits on the busy timeout instead of slipping between.

  CHECKS (a python perpetrator, tests\autotest\_fk_perp.py, plays writer B)
    C0  positive control: one perpetrator commit really changes UnitX's ids.
    C1  lock hold: B holds an IMMEDIATE tx (re-issued ids) while the victim
        `index --resolve-only` starts; victim exits 0, no FOREIGN KEY. NOT a
        RED check on its own: the victim's first stage (uses-targets) blocks on
        the lock BEFORE the calls pass reads its maps, so it sees fresh ids even
        on the unfixed engine. It guards the other face (a hold shorter than
        the 5 s busy timeout must not fail the victim). C2 is the RED check.
    C2  stress (RED on 1.36.0: 7 of 8 victims die FOREIGN KEY): B commits every 10 ms beside 8 victim runs; 8 x exit 0,
        0 FOREIGN KEY, 0 `database is locked`.
    C3  integrity afterwards: foreign_key_check 0 rows, integrity_check ok,
        0 orphan call_edges.
    C6  long hold: B holds an IMMEDIATE tx for 20 s; the victim waits it out (writer busy\n        timeout 120 s, env DRAGLINT_BUSY_TIMEOUT_MS) -- RED on a 5 s timeout.
    C4  a final undisturbed run leaves the same call_edges count as the
        first index, every target present.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs `python` on PATH.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$scratch = $null
try {

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$perp = Join-Path $PSScriptRoot '_fk_perp.py'
$scratch = Join-Path $env:TEMP "drag-lint-two-writers-$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$db = Join-Path $scratch 'fix.sqlite'

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- fixture: UnitX 60 routines, UnitY 600 call sites into them -------------
$decl = (1..60 | ForEach-Object { "procedure DoThing$_(A: Integer);" }) -join "`n"
$impl = (1..60 | ForEach-Object { "procedure DoThing$_(A: Integer);`nbegin`nend;`n" }) -join "`n"
Write-Ascii (Join-Path $scratch 'UnitX.pas') "unit UnitX;`n`ninterface`n`n$decl`n`nimplementation`n`n$impl`nend.`n"
$calls = (1..60 | ForEach-Object { $n = $_; (0..9 | ForEach-Object { "  DoThing$n(I + $_);" }) }) -join "`n"
Write-Ascii (Join-Path $scratch 'UnitY.pas') "unit UnitY;`n`ninterface`n`nuses UnitX;`n`nprocedure RunAll;`n`nimplementation`n`nprocedure RunAll;`nvar I: Integer;`nbegin`n  I := 0;`n$calls`nend;`n`nend.`n"
Write-Ascii (Join-Path $scratch 'Fix.dpr') "program Fix;`n`nuses`n  UnitX in 'UnitX.pas',`n  UnitY in 'UnitY.pas';`n`nbegin`n  RunAll;`nend.`n"
Write-Ascii (Join-Path $scratch 'Fix.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <ProjectGuid>{F1F1F1F1-0000-0000-0000-000000000001}</ProjectGuid>
    <MainSource>Fix.dpr</MainSource>
    <Platform>Win32</Platform>
    <Config>Debug</Config>
  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="Fix.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="UnitX.pas"/>
    <DCCReference Include="UnitY.pas"/>
  </ItemGroup>
</Project>
'@
$proj = Join-Path $scratch 'Fix.dproj'

function Invoke-Victim { # returns @{Code; Out}
  $o = & $exePath index --project $proj --db $db --resolve-only 2>&1 | Out-String
  @{ Code = $LASTEXITCODE; Out = $o }
}
function Db-Facts { # call_edges count, orphan edges, fk_check rows, integrity
  $py = @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
print(c.execute('select count(*) from call_edges').fetchone()[0],
      c.execute('select count(*) from call_edges e where not exists (select 1 from symbols s where s.id=e.target_symbol_id)').fetchone()[0],
      len(c.execute('PRAGMA foreign_key_check').fetchall()),
      c.execute('PRAGMA integrity_check').fetchone()[0])
'@
  $f = Join-Path $scratch '_facts.py'; Write-Ascii $f $py
  $r = (& python -I $f $db 2>&1 | Out-String).Trim() -split '\s+'
  @{ Edges = [int]$r[0]; Orphans = [int]$r[1]; FkRows = [int]$r[2]; Integrity = $r[3] }
}

# --- first index ------------------------------------------------------------
$first = & $exePath index --project $proj --db $db 2>&1 | Out-String
$firstCode = $LASTEXITCODE
$edges0 = (Db-Facts).Edges
Check 'setup: first index exit 0 and call_edges present' (($firstCode -eq 0) -and ($edges0 -gt 600)) "edges=$edges0"

# --- C0 positive control ----------------------------------------------------
$id0 = [int](& python -I $perp $db 'UnitX.pas' --min-id 2>&1 | Out-String).Trim()
$null = & python -I $perp $db 'UnitX.pas' --hold-ms 1 2>&1
$id1 = [int](& python -I $perp $db 'UnitX.pas' --min-id 2>&1 | Out-String).Trim()
Check 'C0 positive control: a perpetrator commit re-issues UnitX symbol ids' ($id1 -ne $id0) "min id $id0 -> $id1"

# --- C1 deterministic race --------------------------------------------------
$pOut = Join-Path $scratch 'perp-c1.out'
$p = Start-Process python -ArgumentList @('-I', $perp, $db, 'UnitX.pas', '--hold-ms', '3000') -PassThru -NoNewWindow -RedirectStandardOutput $pOut
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline -and -not ((Test-Path $pOut) -and ((Get-Content $pOut -Raw) -match 'READY'))) { Start-Sleep -Milliseconds 50 }
Start-Sleep -Milliseconds 500
$v = Invoke-Victim
$p.WaitForExit()
Check 'C1 perpetrator committed' ((Get-Content $pOut -Raw) -match 'COMMITTED')
Check 'C1 victim exit 0 beside a writer re-issuing ids' ($v.Code -eq 0) "exit=$($v.Code)"
Check 'C1 no FOREIGN KEY failure' ($v.Out -notmatch 'FOREIGN KEY')
if ($v.Out -match 'FOREIGN KEY|database is locked') { ($v.Out -split "`r?`n" | Where-Object { $_ -match 'FOREIGN|locked|failing edge' } | Select-Object -First 4) | ForEach-Object { Write-Host "   $_" } }

# --- C6 long hold (RED on stage2: the busy timeout was 5 s) -------------------
# B holds an IMMEDIATE tx for 20 s while the victim starts. A 5 s writer timeout dies
# "database is locked" at 5 s; the 120 s writer timeout waits the hold out and completes.
$hOut = Join-Path $scratch 'perp-c6.out'
$hp = Start-Process python -ArgumentList @('-I', $perp, $db, 'UnitX.pas', '--hold-ms', '20000') -PassThru -NoNewWindow -RedirectStandardOutput $hOut
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline -and -not ((Test-Path $hOut) -and ((Get-Content $hOut -Raw) -match 'READY'))) { Start-Sleep -Milliseconds 50 }
Start-Sleep -Milliseconds 300
$sw = [Diagnostics.Stopwatch]::StartNew()
$hv = Invoke-Victim
$sw.Stop()
$hp.WaitForExit()
Check 'C6 perpetrator committed after its 20 s hold' ((Get-Content $hOut -Raw) -match 'COMMITTED')
Check 'C6 victim waited out a 20 s writer hold (exit 0)' ($hv.Code -eq 0) ("exit={0} after {1:N1} s" -f $hv.Code, $sw.Elapsed.TotalSeconds)
Check 'C6 no database-is-locked failure' ($hv.Out -notmatch 'database is locked')
Check 'C6 victim really waited (>= 15 s)' ($sw.Elapsed.TotalSeconds -ge 15) ("{0:N1} s" -f $sw.Elapsed.TotalSeconds)
# --- C2 stress --------------------------------------------------------------
$sOut = Join-Path $scratch 'perp-c2.out'
$sp = Start-Process python -ArgumentList @('-I', $perp, $db, 'UnitX.pas', '--loop', '--period-ms', '10', '--seconds', '45') -PassThru -NoNewWindow -RedirectStandardOutput $sOut
Start-Sleep -Milliseconds 300
$ok = 0; $fk = 0; $lk = 0
1..8 | ForEach-Object {
  $r = Invoke-Victim
  if ($r.Code -eq 0) { $ok++ }
  if ($r.Out -match 'FOREIGN KEY') { $fk++ }
  if ($r.Out -match 'database is locked') { $lk++ }
}
$sp.WaitForExit()
$sTxt = (Get-Content $sOut -Raw)
Check 'C2 8 of 8 victims exit 0 beside a 10 ms writer' ($ok -eq 8) "ok=$ok"
Check 'C2 zero FOREIGN KEY failures' ($fk -eq 0) "fk=$fk"
Check 'C2 zero database-is-locked failures' ($lk -eq 0) "locked=$lk"
Check 'C2 perpetrator really committed during the run' (($sTxt -match 'DONE commits=(\d+)') -and ([int]$Matches[1] -gt 50)) $sTxt.Trim()

# --- C3 / C4 ----------------------------------------------------------------
$fin = Invoke-Victim
$f = Db-Facts
Check 'C3 foreign_key_check returns 0 rows' ($f.FkRows -eq 0) "rows=$($f.FkRows)"
Check 'C3 integrity_check ok' ($f.Integrity -eq 'ok') $f.Integrity
Check 'C3 zero orphan call_edges' ($f.Orphans -eq 0) "orphans=$($f.Orphans)"
Check 'C4 undisturbed final run exit 0' ($fin.Code -eq 0) "exit=$($fin.Code)"
Check 'C4 call_edges rebuilt onto the new ids (same count as first index)' ($f.Edges -eq $edges0) "edges=$($f.Edges) first=$edges0"

} finally {
  if ($scratch -and (Test-Path $scratch)) { try { [IO.Directory]::Delete($scratch, $true) } catch { Write-Host "note: scratch not removed: $scratch" } }
}
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green; exit 0
