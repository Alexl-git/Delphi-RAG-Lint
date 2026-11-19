# Guard for lane NAMING (1.51.1): field-name-prefix accepts a lowercase "f" prefix
# (R1); method-pascalcase exempts Get/Set accessors named after a DB column
# (underscore remainder) and every method of a *_TLB.pas unit (R4).
# Runs the three tests\lint fixtures through the lint harness; each fixture carries
# negative (!rule N) and positive (rule N) directives, so the rule firing on the
# real defect is the positive control.
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$fail = 0
foreach ($flt in 'field-name-prefix-lowercase-f*', 'method-pascalcase-accessor*', 'mpa_TLB*') {
  $out = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File (Join-Path $repo 'tests\lint\run_lint_tests.ps1') -Exe $Exe -Filter $flt 2>&1 | ForEach-Object { "$_" } } | Out-String
  if ($LASTEXITCODE -ne 0) { Write-Host "FAIL  $flt"; Write-Host $out; $fail++ } else { Write-Host "PASS  $flt" }
}
if ($fail) { exit 1 }
