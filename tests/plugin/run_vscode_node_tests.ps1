<#
  run_vscode_node_tests.ps1 -- runs the VS Code extension's node unit tests
  (editors\vscode\drag-lint\test\*.test.js) from the battery (150 HG item 2).

  WHY: the three tests (context, enginestale, exceptionfacts) are plain `assert`
  scripts with no runner script in package.json, so run_battery.ps1 -- which
  discovers only run_*.ps1 -- never reached them. Each file is run as `node <file>`;
  a non-zero node exit is a FAIL.

  SKIP (exit 77): node is not on PATH. The reason is printed; a skipped run is
  reported apart from PASS by run_battery.ps1.
  FAIL (exit 1): no test files found (an empty directory is not a pass), or any
  test exits non-zero.
  -TestDir overrides the directory (used by the RED check).
#>
[CmdletBinding()]
param(
  [string]$TestDir = "$PSScriptRoot\..\..\editors\vscode\drag-lint\test"
)
$ErrorActionPreference = 'Continue'
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Host 'SKIP: node is not on PATH; the VS Code extension tests were not run.' -ForegroundColor Yellow
  exit 77
}
$files = @(Get-ChildItem -LiteralPath $TestDir -Filter '*.test.js' -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($files.Count -eq 0) {
  Write-Host "FAIL: no *.test.js under $TestDir" -ForegroundColor Red
  exit 1
}
$failed = 0
foreach ($f in $files) {
  $out = & $node.Source $f.FullName 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) {
    Write-Host ("  [PASS] {0}" -f $f.Name) -ForegroundColor Green
  } else {
    $failed++
    Write-Host ("  [FAIL] {0} (node exit {1})" -f $f.Name, $LASTEXITCODE) -ForegroundColor Red
    Write-Host ($out.Trim())
  }
}
if ($failed -gt 0) { Write-Host "VSCODE NODE TESTS: FAIL ($failed of $($files.Count))" -ForegroundColor Red; exit 1 }
Write-Host "VSCODE NODE TESTS: PASS ($($files.Count) files)" -ForegroundColor Green
exit 0