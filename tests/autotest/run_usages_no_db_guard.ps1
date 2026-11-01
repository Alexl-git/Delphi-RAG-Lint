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
    3. CONTROL: find-callers in the same cwd also reports "database not found" (the verbs agree)
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-usages-nodb-$PID"
)
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
  $o3 = (& $Exe query find-callers --name Callee 2>&1 | ForEach-Object { "$_" }) -join "`n"
  Check '3 CONTROL find-callers also says database not found' ($o3 -match 'database not found')
} finally { Pop-Location }
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'run_usages_no_db_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_usages_no_db_guard: PASS' -ForegroundColor Green
exit 0
