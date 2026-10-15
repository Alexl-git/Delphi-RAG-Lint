<#
  run_index_scope_listing_cap.ps1 -- a real `index --project` run prints its
  scope CAPPED; `--dry-run` still prints all of it.

  THE PROBLEM. DoIndex printed the whole compile closure, one path per line,
  before every run. On a 2,249-file project that is 2,249 lines -- over 100k
  tokens -- ahead of the summary lines an agent actually reads, on every
  incremental reindex that re-parses one file (field report, 2026-09-29).

  THE FIX. PrintScopeListing: a real run prints the count, SWEEP_SAMPLE_MAX (20)
  paths, "... and N more" and a pointer to --dry-run; --dry-run keeps the full
  list, because there the list IS the answer (run_index_project_scope.ps1
  parses it).

  The fixture is a program with 25 units, so the closure is 26 entries (the .dpr
  plus 25 .pas) -- over the cap by a margin the assertions can see.

  Usage: pwsh -File tests/autotest/run_index_scope_listing_cap.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-scope-cap-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$UnitCount = 25
$names = @(1..$UnitCount | ForEach-Object { 'CapUnit{0:D2}' -f $_ })
foreach ($n in $names) {
  Write-Ascii (Join-Path $WorkDir "$n.pas") @"
unit $n;

interface

procedure Run$n;

implementation

procedure Run$n;
begin
end;

end.
"@
}
$usesList = ($names | ForEach-Object { "  $_ in '$_.pas'" }) -join ",`n"
$dpr = Join-Path $WorkDir 'CapApp.dpr'
Write-Ascii $dpr @"
program CapApp;

uses
$usesList;

begin
end.
"@

$db = Join-Path $WorkDir 'cap.sqlite'
# A scope line is a two-space-indented absolute path (drive letter or UNC) and
# nothing else. The per-file progress line ('  X.pas -> N symbols, ...') has the
# same indent and a path too, so it is excluded explicitly.
$pathLine = '^\s\s([A-Za-z]:\\|\\\\)(?!.* -> )'

Write-Host 'dry run -- the list IS the answer, so it stays complete' -ForegroundColor Cyan
$dry = @((& $Exe index --project $dpr --db $db --platform win32 --dry-run 2>&1) | ForEach-Object { "$_" })
Check 'dry run exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$dryPaths = @($dry | Where-Object { $_ -match $pathLine })
Check 'precondition: the closure is larger than the cap' ($dryPaths.Count -gt 20) `
  "dry-run listed $($dryPaths.Count) -- at 20 or fewer the cap cannot be observed and every assertion below is vacuous"
Check 'ASSERT: --dry-run lists EVERY scope entry' ($dryPaths.Count -eq ($UnitCount + 1)) `
  "listed $($dryPaths.Count), expected $($UnitCount + 1) (the .dpr plus $UnitCount units)"

Write-Host ''
Write-Host 'real run -- the list is capped' -ForegroundColor Cyan
$run = @((& $Exe index --project $dpr --db $db --platform win32 2>&1) | ForEach-Object { "$_" })
Check 'real run exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$text = $run -join "`n"
Check 'the headline still carries the full count' ($text -match ('Compile closure: {0} file\(s\):' -f ($UnitCount + 1))) ''
$runPaths = @($run | Where-Object { $_ -match $pathLine })
Check 'ASSERT: a real run prints at most 20 scope paths' ($runPaths.Count -eq 20) "printed $($runPaths.Count)"
Check 'ASSERT: the tail says how many were left out' ($text -match ('\.\.\. and {0} more' -f ($UnitCount + 1 - 20))) ''
Check 'ASSERT: the tail names --dry-run as the way to see all of them' `
  ($text -match ('\(--dry-run lists all {0}\)' -f ($UnitCount + 1))) ''
Check 'CONTROL: the run really indexed the whole closure' ($text -match 'Done\. Files: 26\b') `
  "the cap is about PRINTING; a run that indexed fewer files would pass the assertions above for the wrong reason"

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-scope-cap-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
