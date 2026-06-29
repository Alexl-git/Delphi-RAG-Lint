# Runs all M1 type/hierarchy-resolver test scripts and aggregates results.
# Each sub-script indexes its fixtures into a throwaway DB and asserts behavior
# via `query ancestors` / `query typecat` / `check-ast --db`.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$scripts = @(
  'run_heritage_test.ps1',   # P1: heritage capture
  'run_ancestry_test.ps1',   # P2: cross-unit ancestry + IsDescendantOf/Implements
  'run_typecat_test.ps1',    # P3: ResolveTypeCategory + alias chase
  'run_typeaware_test.ps1',  # P4: float/freeandnil/win64 + string-equality (store-aware)
  'run_virtctor_test.ps1'    # P4b: cross-unit virtual-method-in-constructor
)
$failed = 0
foreach ($s in $scripts) {
  Write-Host "--- $s ---"
  & (Join-Path $dir $s)
  if ($LASTEXITCODE -ne 0) { $failed++ }
}
Write-Host ''
if ($failed -gt 0) { Write-Host "M1 tests: $failed script(s) FAILED"; exit 1 }
Write-Host 'M1 tests: ALL PASS'; exit 0
