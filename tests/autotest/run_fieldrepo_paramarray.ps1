#Requires -Version 7.3
<#
  run_fieldrepo_paramarray.ps1 -- builds and runs the FieldRepo.ParamArray test runner
  (tests\fieldrepo\ParamArrayTests.dpr): the golden Array-DML block derived from the
  TableTools FireDAC Param Array assistant on the fixture, the plan diff, the compile-gate
  apply (refusal leaves the source) and the project run.

  A MISSING Delphi toolchain, build or test exe is a FAIL here, never a skip. Exit 0 only
  when the summary line reports fail=0 and the process exit code is 0.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -OutDir     where the exe and dcu go (default: %TEMP%\drag-lint-paramarray-tests-<pid>)
    -SkipBuild  run the exe already in -OutDir
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$OutDir = (Join-Path $env:TEMP "drag-lint-paramarray-tests-$PID"),
      [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Write-Host '== fieldrepo param-array tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_fieldrepo_paramarray_tests_local.bat'
$bin = Join-Path $OutDir 'ParamArrayTests.exe'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
if (-not $SkipBuild) {
  if (-not (Test-Path -LiteralPath $bat)) { Write-Host "PARAM-ARRAY TESTS: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
  $blog = Join-Path $OutDir 'build.log'
  Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' ' + [char]34 + $OutDir + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
  $bl = Get-Content -LiteralPath $blog -Raw
  if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error |Error: E\d+')) {
    Write-Host "PARAM-ARRAY TESTS: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red
    exit 1
  }
}
if (-not (Test-Path -LiteralPath $bin)) { Write-Host "PARAM-ARRAY TESTS: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
$log = Join-Path $OutDir 'run.log'
& $bin *> $log
$code = $LASTEXITCODE
$sum = Select-String -LiteralPath $log -Pattern '^Summary: ' | Select-Object -Last 1
Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
if (-not $sum) { Write-Host 'PARAM-ARRAY TESTS: FAIL -- no Summary line (the runner crashed)' -ForegroundColor Red; exit 1 }
Write-Host "  $($sum.Line)"
if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'PARAM-ARRAY TESTS: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PARAM-ARRAY TESTS: PASS' -ForegroundColor Green
exit 0