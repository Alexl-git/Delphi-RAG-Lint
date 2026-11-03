<#
  run_index_halfread_guard.ps1 -- 1.41 IDX-HALFREAD.

  WHAT IT PINS. A reader during a reindex sees the PREVIOUS COMPLETE state, or is
  told an index run is writing. The case that showed "0 of 60k refs resolved":
  a stale resolver / `--resolve-only` used to clear every call edge and every
  refs.symbol_id in AUTOCOMMIT before the (long) calls pass, so for the whole
  pass every reader saw zero resolved refs. The clear now runs inside the calls
  pass's transaction.

    HR1 two processes: while `index --resolve-only` holds its calls pass open
        (test seam DRAGLINT_TEST_RESOLVE_DELAY_MS), a python reader never sees
        fewer resolved refs than before the run (RED before 1.41: it sees 0)
    HR2 the run ends 0 with the same resolved-ref count as before (same rows)
    HR3 a reader while <db>.indexing.lock is held prints the index-in-progress NOTE
    HR4 positive control: without the lock no such NOTE

  Scratch only (-WorkDir); never a real project DB. Needs python on PATH. pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-halfread-guard-$PID",
  [int]$DelayMs    = 6000
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name  $Detail" } else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
function Run-Exe([string[]]$ArgList, [hashtable]$EnvVars) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $WorkDir
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit(120000)) { try { $p.Kill($true) } catch { } }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
$CountSql = 'SELECT count(*) FROM refs WHERE symbol_id IS NOT NULL'
function Resolved([string]$Db) {
  return [int](& python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute(sys.argv[2]).fetchone()[0])" $Db $CountSql)
}

try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  for ($i = 1; $i -le 4; $i++) {
    $j = if ($i -lt 4) { $i + 1 } else { 1 }
    $t = "unit HalfUnit$i;`r`n`r`ninterface`r`n`r`nprocedure Work$i(A: Integer);`r`n`r`nimplementation`r`n`r`nuses HalfUnit$j;`r`n`r`nprocedure Work$i(A: Integer);`r`nbegin`r`n  if A > 0 then begin Work$i(A - 1); Work$j(A - 1); end;`r`nend;`r`n`r`nend.`r`n"
    [IO.File]::WriteAllText((Join-Path $src "HalfUnit$i.pas"), $t, [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir 'half.sqlite'
  $first = Run-Exe @('index', $src, '--db', $db) @{}
  if ($first.Code -ne 0) { Write-Host "FATAL: setup index failed: $($first.Out)$($first.Err)" -ForegroundColor Red; exit 2 }
  $r0 = Resolved $db
  if ($r0 -le 0) { Write-Host "FATAL: setup resolved no refs ($r0)" -ForegroundColor Red; exit 2 }

  # ---- HR1/HR2: a reader sampled while the calls pass holds its transaction ----
  $readerOut = Join-Path $WorkDir 'reader.out'
  $reader = Join-Path $WorkDir 'reader.py'
  [IO.File]::WriteAllText($reader, (@(
    'import sqlite3, sys, time',
    'db, secs, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]',
    'counts = []',
    'end = time.time() + secs',
    'while time.time() < end:',
    '    c = sqlite3.connect(db, timeout=5.0)',
    "    counts.append(c.execute('SELECT count(*) FROM refs WHERE symbol_id IS NOT NULL').fetchone()[0])",
    '    c.close()',
    '    time.sleep(0.2)',
    "open(out, 'w').write(' '.join(str(n) for n in counts))"
  ) -join "`r`n"), [Text.Encoding]::ASCII)
  $rp = Start-Process python -ArgumentList @('-I', $reader, $db, ([string](($DelayMs + 2000) / 1000)), $readerOut) -PassThru -NoNewWindow
  $v = Run-Exe @('index', $src, '--db', $db, '--resolve-only') @{ DRAGLINT_TEST_RESOLVE_DELAY_MS = $DelayMs }
  if (-not $rp.WaitForExit(30000)) { try { $rp.Kill() } catch { } }
  $samples = @((Get-Content $readerOut -Raw).Trim() -split ' ' | ForEach-Object { [int]$_ })
  $min = ($samples | Measure-Object -Minimum).Minimum
  Check 'HR1 a reader during the calls pass never sees fewer resolved refs than before' (($samples.Count -ge 5) -and ($min -ge $r0)) "before=$r0 min=$min samples=$($samples.Count)"
  $r1 = Resolved $db
  Check 'HR2 --resolve-only ends 0 with the same resolved-ref count' (($v.Code -eq 0) -and ($r1 -eq $r0)) "exit=$($v.Code) before=$r0 after=$r1"

  # ---- HR3/HR4: the in-progress NOTE ----
  $lock = [IO.FileStream]::new("$db.indexing.lock", [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
  try { $q = Run-Exe @('query', '--name', 'Work1', '--db', $db) @{} } finally { $lock.Dispose() }
  Check 'HR3 a reader while the index lock is held says an index run is writing' (($q.Code -eq 0) -and ($q.Err -match 'an index run is writing')) "exit=$($q.Code) err=$($q.Err.Trim())"
  $q2 = Run-Exe @('query', '--name', 'Work1', '--db', $db) @{}
  Check 'HR4 positive control: no lock, no in-progress NOTE' (($q2.Code -eq 0) -and ($q2.Err -notmatch 'an index run is writing')) "exit=$($q2.Code)"
}
catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
finally {
  try { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { exit 1 }
Write-Host 'ALL PASS'
exit 0
