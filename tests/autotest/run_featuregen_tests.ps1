#Requires -Version 7.3
<#
  run_featuregen_tests.ps1 -- builds and runs the featuregen test runner
  (src\tools\featuregen\tests\FeatureGenTests.dpr). It covers what the retired
  PowerShell registry runners (canonical, cli, families, generate, harvest) covered, plus
  the golden parity of the PowerShell products, the check A-E controls and the website set.

  A MISSING engine, Delphi toolchain or test exe is a FAIL here, never a skip. The tests
  need the engine at third_party\dll-win64\drag-lint.exe (they also name it by its
  main-tree path). Exit 0 only when the summary line reports fail=0 and the process exit
  code is 0.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -SkipBuild  run the exe already on disk
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Write-Host '== featuregen tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_featuregen_tests_local.bat'
$bin = Join-Path $Repo 'src\tools\featuregen\tests\FeatureGenTests.exe'
$work = Join-Path $env:TEMP "drag-lint-featuregen-tests-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "FEATUREGEN TESTS: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) {
      Write-Host "FEATUREGEN TESTS: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red
      exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "FEATUREGEN TESTS: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
  $log = Join-Path $work 'run.log'
  & $bin *> $log
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $skips = @(Select-String -LiteralPath $log -Pattern '^SKIP')
  if ($skips.Count -gt 0) { Write-Host ("FEATUREGEN TESTS: FAIL -- $($skips.Count) SKIP line(s): a skipped parity test is a vanished regression pin") -ForegroundColor Red; exit 1 }
  if (-not $sum) { Write-Host 'FEATUREGEN TESTS: FAIL -- no SUMMARY line (the runner crashed)' -ForegroundColor Red; exit 1 }
  Write-Host "  $($sum.Line)"
  if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'FEATUREGEN TESTS: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'FEATUREGEN TESTS: PASS' -ForegroundColor Green
  exit 0
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
