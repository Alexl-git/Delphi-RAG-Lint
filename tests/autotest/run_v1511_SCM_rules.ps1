# Guard for the v1511 lane SCM rule fixes (1.51.1-alpha): B13 division-by-zero-literal (no div/mod 0 = dcc E2098;
# float message), Y1/R6 large-magic-number (case labels, enum ordinals, dispid), R3 inherited-bare (Destroy / Assign /
# AssignTo, then/else fallback). Reuses tests\lint\run_lint_tests.ps1 with a
# filter per fixture; the (+)/(-) expectations are the .expected files next to the fixtures.
param(
  [string]$Exe   = "third_party\dll-win64\drag-lint.exe",
  [string]$Rules = "rules"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$fail = 0
foreach ($f in 'division-by-zero-literal', 'large-magic-number-v1511', 'large-magic-number-v1511b', 'inherited-bare-v1511', 'inherited_bare', 'large-magic-number-v151', 'large-magic-number-exempt') {
  $out = & { $ErrorActionPreference = 'Continue'; & (Join-Path $repo 'tests\lint\run_lint_tests.ps1') -Exe $Exe -Rules $Rules -Filter $f *>&1 | ForEach-Object { "$_" } }
  $out | Where-Object { $_ -match 'PASS|FAIL|missing|should' } | ForEach-Object { Write-Host $_ }
  if (($out | Out-String) -cmatch 'FAIL  ') { $fail++ }
}
# division-by-zero-literal message must not claim an integer div/mod is covered.
$exe = (Resolve-Path $Exe).Path
$raw = & { $ErrorActionPreference = 'Continue'; & $exe lint (Join-Path $repo 'tests\lint\division-by-zero-literal.pas') --rule division-by-zero-literal --json 2>$null }
$msg = (($raw | ConvertFrom-Json | ForEach-Object { $_ }) | Select-Object -First 1).message
if ($msg -match "float") { Write-Host "PASS  message names the float / division form" } else { Write-Host "FAIL  message: $msg" -ForegroundColor Red; $fail++ }
if ($fail -gt 0) { Write-Host "FAILED: $fail" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS"
exit 0
