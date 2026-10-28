<#
  run_cli_followups_guard.ps1 -- the 1.20.4 / 1.20.5 CLI follow-ups (lane B-CLI2), each RED on the
  pre-B-CLI engine (7dc3b0f2) and GREEN on gaps/bcli2:

    Q  #5      IndexSectionCommand quotes a section name that holds a literal `"`
               (resolve-dbs never-built NOTE: --only "P\"Q", not --only P"Q).
    L  #5      ResolveLibraryDb finds the library by section KIND, not by the file-name prefix
               `library-`: a PROJECT whose DB is library-app.sqlite is not the library. Observed by
               the stale-library warning of lint-project, which names the REAL library DB.
    M  #4b-2   a project registered only in a LOCAL .drag-lint.json beside it resolves for a read
               (lint-all --project) run from ANOTHER cwd -- the write (index --project) already walked
               from the project folder.
    C  #4b-3   compile-check caches into an unregistered project's OWN _D-RAG\<base>.sqlite when it
               exists (the plugin passes no --db); a project with no such file still warns.
    R  item 10 lint-all --rule a,b,c exits 2 with a message (it used to match no rule and report 0).
    N  #4b-4   `NOTE: no index owns` appears ONCE for `lint <folder> --project X` (it repeated per file).
    H  item 5d the shared guard helper names exit 0xC000007B instead of "index produced no DB".

  Positive controls sit beside each negative assertion. Needs a working dcc for case C.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-clifollow-$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')   # Get-ExeStartFailureHint (case H); also defines Check
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$exeDir = Split-Path $Exe -Parent
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

# An ENGINE COPY with its own drag-lint.json, so no shared manifest is ever consulted or written.
function New-Engine([string]$Dir, $Manifest) {
  New-Item -ItemType Directory -Path $Dir | Out-Null
  Copy-Item $Exe (Join-Path $Dir 'drag-lint.exe') -Force
  Get-ChildItem -Path $exeDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $Dir $_.Name) -Force }
  if (Test-Path (Join-Path $exeDir 'rules')) { Copy-Item (Join-Path $exeDir 'rules') (Join-Path $Dir 'rules') -Recurse -Force }
  if ($Manifest) { Write-Ascii (Join-Path $Dir 'drag-lint.json') ($Manifest | ConvertTo-Json -Depth 8) }
  return (Join-Path $Dir 'drag-lint.exe')
}
function Run($Cwd, $Cmd, [string[]]$A) {
  Push-Location $Cwd
  try { $o = (& $Cmd @A 2>&1 | ForEach-Object { "$_" }) -join "`n"; return @{ Out = $o; Code = $LASTEXITCODE } }
  finally { Pop-Location }
}

# ---- Q: the section name holds a literal quote ---------------------------------------------
$q = Join-Path $WorkDir 'q'
New-Item -ItemType Directory -Path "$q\proj" | Out-Null
$qExe = New-Engine "$q\eng" @{
  settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
  indexes  = @{ sections = @( @{ name = 'P"Q'; include = @('..\proj\Foo.dpr') } ) } }
Write-Ascii "$q\proj\Foo.dpr" "program Foo;`nbegin`nend.`n"
$r = Run $q $qExe @('resolve-dbs', '--platform', 'win64')
$note = @($r.Out -split "`n" | Where-Object { $_ -match 'has never been built -- run: ' })
Check 'Q0 precondition: the never-built NOTE is printed for the quoted section' ($note.Count -eq 1) $r.Out
Check 'Q1 the advice quotes and escapes the literal quote: --only "P\"Q"' `
      (($note.Count -eq 1) -and $note[0].Contains('--only "P\"Q"')) ($note -join ' | ')

# ---- L: the library is found by section KIND -----------------------------------------------
$l = Join-Path $WorkDir 'l'
New-Item -ItemType Directory -Path "$l\proj", "$l\lib" | Out-Null
$lExe = New-Engine "$l\eng" @{
  settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
  indexes  = @{ sections = @(
    @{ name = 'P-App';   include = @('..\proj\library-app.dpr') },
    @{ name = 'Library'; db = 'library-{platform}.sqlite'; source = 'registry-libraries'; platforms = @('Win64') } ) } }
Write-Ascii "$l\proj\library-app.dpr" "program App;`nuses uMain in 'uMain.pas';`nbegin`nend.`n"
Write-Ascii "$l\proj\uMain.pas" "unit uMain;`n`ninterface`n`nimplementation`n`nend.`n"
Write-Ascii "$l\lib\uLibOnly.pas" "unit uLibOnly;`n`ninterface`n`nimplementation`n`nend.`n"
$libDb = "$l\eng\library-Win64.sqlite"
Push-Location $l
try {
  & $lExe index "$l\lib" --db $libDb 2>&1 | Out-Null
  & $lExe index --project "$l\proj\library-app.dpr" 2>&1 | Out-Null
} finally { Pop-Location }
$ownDb = "$l\proj\_D-RAG\library-app.sqlite"
Check 'L0 precondition: the project DB is named library-* and the real library DB exists' `
      ((Test-Path $ownDb) -and (Test-Path $libDb)) "$ownDb | $libDb"
# Make the REAL library unreadable: the only run that can then name it is one that picked it.
Write-Ascii $libDb "this is not a database`n"
$r = Run $l $lExe @('lint-project', '--project', "$l\proj\library-app.dpr", '--quiet')
Check 'L1 the library is the Library SECTION (its DB is named in the degrade warning), not the library-* project DB' `
      (($r.Out -match 'warning: library DB \S*library-Win64\.sqlite unreadable') -and ($r.Out -match 'continuing without it')) $r.Out
Check 'L2 control: the project DB is intact and was not reported as the failing library' `
      ($r.Out -notmatch 'library-app\.sqlite: ') $r.Out

# ---- M: a project registered only in a local .drag-lint.json, read from ANOTHER cwd --------
$m = Join-Path $WorkDir 'm'
New-Item -ItemType Directory -Path "$m\proj", "$m\other" | Out-Null
$mExe = New-Engine "$m\eng" $null
Write-Ascii "$m\proj\App.dpr" "program App;`nuses uMain in 'uMain.pas';`nbegin`nend.`n"
Write-Ascii "$m\proj\uMain.pas" "unit uMain;`n`ninterface`n`nimplementation`n`nend.`n"
Write-Ascii "$m\proj\.drag-lint.json" ((@{ indexes = @{ sections = @( @{ name = 'Loc'; include = @('App.dpr'); db = 'loc.sqlite' } ) } }) | ConvertTo-Json -Depth 8)
$w = Run "$m\other" $mExe @('index', '--project', "$m\proj\App.dpr")
Check 'M1 the write (index --project) from another cwd built the local section DB' (Test-Path "$m\proj\loc.sqlite") $w.Out
$r = Run "$m\other" $mExe @('lint-all', '--project', "$m\proj\App.dpr", '--quiet')
Check 'M2 the read (lint-all --project) from another cwd picks the SAME DB: scans the project (exit 0 or 1 = findings, never 2), no "no index owns"' `
      (($r.Code -ne 2) -and ($r.Out -match 'scanning') -and ($r.Out -notmatch 'no index owns')) "exit=$($r.Code) $($r.Out)"

# ---- C: compile-check caches into an unregistered project's own default DB -----------------
$c = Join-Path $WorkDir 'c'
New-Item -ItemType Directory -Path "$c\withdb", "$c\nodb", "$c\neutral" | Out-Null
$cExe = New-Engine "$c\eng" $null
foreach ($d in 'withdb', 'nodb') { Write-Ascii "$c\$d\Tiny.dpr" "program Tiny;`n`n{`$APPTYPE CONSOLE}`n`nbegin`n  Writeln('hi');`nend.`n" }
Push-Location "$c\withdb"
try { & $cExe index "$c\withdb" --db "$c\withdb\_D-RAG\Tiny.sqlite" 2>&1 | Out-Null } finally { Pop-Location }
Check 'C0 precondition: the unregistered project has its own _D-RAG\Tiny.sqlite' (Test-Path "$c\withdb\_D-RAG\Tiny.sqlite")
$r = Run "$c\neutral" $cExe @('compile-check', "$c\withdb\Tiny.dpr", '--format', 'json')
Check 'C1 an unregistered project with its own default DB caches (no "no database resolved" warning)' `
      ($r.Out -notmatch 'no database resolved for this target') $r.Out
$r = Run "$c\neutral" $cExe @('compile-check', "$c\nodb\Tiny.dpr", '--format', 'json')
Check 'C2 control: with NO default DB the warning is still printed' `
      ($r.Out -match 'no database resolved for this target') $r.Out

# ---- R: --rule takes one id -----------------------------------------------------------------
$r = Run $WorkDir $Exe @('lint-all', '--rule', 'magic-literal,missing-doc')
Check 'R1 a comma list exits 2' ($r.Code -eq 2) "exit=$($r.Code)"
Check 'R2 ... and says why (one rule id, not a list)' ($r.Out -match '--rule takes one rule id') $r.Out
$r = Run $WorkDir $Exe @('lint-all', '--rule', 'magic-literal', '--db', "$WorkDir\absent.sqlite")
Check 'R3 control: a single id is not refused by the list check' ($r.Out -notmatch '--rule takes one rule id') $r.Out

# ---- N: the no-owner NOTE once per run, also across a folder lint --------------------------
$n = Join-Path $WorkDir 'n'
New-Item -ItemType Directory -Path "$n\proj" | Out-Null
Write-Ascii "$n\proj\App.dproj" "<Project><PropertyGroup><MainSource>App.dpr</MainSource></PropertyGroup></Project>`n"
Write-Ascii "$n\proj\App.dpr" "program App;`nbegin`nend.`n"
foreach ($u in 'uA', 'uB', 'uC') { Write-Ascii "$n\proj\$u.pas" "unit $u;`n`ninterface`n`nimplementation`n`nend.`n" }
$r = Run $n $Exe @('lint', "$n\proj", '--project', "$n\proj\App.dproj")
$cnt = @($r.Out -split "`n" | Where-Object { $_ -match 'no index owns' }).Count
Check 'N1 lint <folder> --project over 3 units prints the note exactly once' ($cnt -eq 1) "count=$cnt (the pre-fix engine printed one per file)"

# ---- H: the shared guard helper names a loader failure ---------------------------------------
Check 'H1 0xC000007B is reported as an exe that failed to start' ((Get-ExeStartFailureHint -1073741701) -match 'failed to start') (Get-ExeStartFailureHint -1073741701)
Check 'H2 control: an ordinary exit code gives no hint' ((Get-ExeStartFailureHint 1) -eq '')

try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed) { Write-Host 'run_cli_followups_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_cli_followups_guard: PASS' -ForegroundColor Green
exit 0
