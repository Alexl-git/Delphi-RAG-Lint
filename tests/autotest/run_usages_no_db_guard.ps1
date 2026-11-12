<#
  run_usages_no_db_guard.ps1 -- lane 140-cli USAGES-NAME. `usages --name X` with NO resolvable
  database must fail loudly (exit 2, "database not found") exactly as `query find-callers` does.

  THE DEFECT: DoUsages looped over PathsToScan = [''] and `Continue`d on the missing file, so it
  printed "declarations: 0 ... calls: 0" and exited 0 -- a plausible-looking empty answer where
  find-callers (same cwd, same args) said "database not found". A reader concluded the symbol had
  no usages.

  Cases (2 is the positive control, 3 the old-behaviour witness):
    1. no --db, scratch cwd: exit 2, message names the missing database, no "calls:" summary
    2. CONTROL: --db <indexed fixture>: exit 0, calls >= 1
    3. CONTROL: an exe with NO manifest beside it: find-callers also reports "database not found"
    4. CONTROL: an exe with a manifest beside it: find-callers with no --db answers from the
       manifest's databases

  WHY 3 RUNS A PRIVATE COPY OF THE EXE (corrected deliberately, 1.42 sweeper-B). Check 3 used to
  run $Exe in place and assumed no database resolves. That holds for a build-output exe and is
  false for an installed one: omitting --db is DOCUMENTED to let the manifest resolver supply the
  full set (README "An explicit --db must exist", AI-USAGE "Omitting --db is always safe" and its
  cross-project find-callers note). Beside a real drag-lint.json the check read every configured
  DB for >120 s, then failed. So find-callers keeps that behaviour, the assumption is now made
  true by construction, and 4 pins the documented half so neither case can drift unseen.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-usages-nodb-$PID"
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # 152 HG3: no machine drag-lint.json
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null
$body = @(
  'unit uUsg;', '', 'interface', '', 'procedure Callee;', 'procedure Caller;', '',
  'implementation', '', 'procedure Callee;', 'begin', 'end;', '', 'procedure Caller;', 'begin',
  '  Callee;', 'end;', '', 'end.') -join "`r`n"
[IO.File]::WriteAllText((Join-Path $src 'uUsg.pas'), $body + "`r`n", (New-Object System.Text.ASCIIEncoding))
$db = Join-Path $WorkDir 'u.sqlite'
$code = Invoke-G8Index $Exe $src $db
Check 'fixture index built' (($code -eq 0) -and (Test-Path $db)) "exit=$code"

$empty = Join-Path $WorkDir 'cwd'
New-Item -ItemType Directory -Force $empty | Out-Null
Push-Location $empty
try {
  $o1 = (& $Exe usages --name Callee 2>&1 | ForEach-Object { "$_" }) -join "`n"; $c1 = $LASTEXITCODE
  Check '1 usages without a database exits 2' ($c1 -eq 2) "exit=$c1"
  Check '1 usages names the missing database' ($o1 -match 'database not found') ($o1 -replace "`n", ' | ')
  Check '1 usages prints no zero summary' ($o1 -notmatch 'calls:\s*0')
  $o2 = (& $Exe usages --name Callee --db $db 2>&1 | ForEach-Object { "$_" }) -join "`n"; $c2 = $LASTEXITCODE
  Check '2 CONTROL usages with --db exits 0' ($c2 -eq 0) "exit=$c2"
  Check '2 CONTROL usages with --db finds the call' ($o2 -match 'calls:\s*[1-9]') ($o2 -replace "`n", ' | ')
  $bare = Join-Path $WorkDir 'bare'
  New-Item -ItemType Directory -Force $bare | Out-Null
  Copy-Item -LiteralPath $Exe -Destination $bare
  Get-ChildItem -LiteralPath (Split-Path $Exe) -Filter '*.dll' | Copy-Item -Destination $bare
  $bareExe = Join-Path $bare (Split-Path $Exe -Leaf)
  $o3 = (& $bareExe query find-callers --name Callee 2>&1 | ForEach-Object { "$_" }) -join "`n"
  Check '3 CONTROL find-callers with no manifest also says database not found' ($o3 -match 'database not found') ($o3 -replace "`n", ' | ')
  $manifest = @{ indexes = @{ sections = @( @{ name = 'Fix'; include = @($src); db = $db } ) } } | ConvertTo-Json -Depth 6
  [IO.File]::WriteAllText((Join-Path $bare 'drag-lint.json'), $manifest, (New-Object System.Text.ASCIIEncoding))
  $o4 = (& $bareExe query find-callers --name Callee 2>&1 | ForEach-Object { "$_" }) -join "`n"; $c4 = $LASTEXITCODE
  Check '4 CONTROL find-callers with a manifest answers without --db' (($c4 -eq 0) -and ($o4 -match 'Caller')) "exit=$c4 $($o4 -replace "`n", ' | ')"
} finally { Pop-Location }
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'run_usages_no_db_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_usages_no_db_guard: PASS' -ForegroundColor Green
exit 0
