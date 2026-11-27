#Requires -Version 7.3
<#
  run_v156_UIM.ps1 -- lane UI-M (1.56 USEDICON): field-usage query (DRagLint.FieldRepo.FieldUsage).
  Builds and runs tests\fieldrepo\FieldUsageTests.dpr (unit tests over a hand-built project index DB). No engine needed.
  A missing toolchain or exe is a FAIL, never a skip. Exit 0 only when SUMMARY reports fail=0.
  Parameters: -Repo <root> (default: two levels above this script); -OutDir <dir> build output (default: a temp dir);
              -SkipBuild  run the exe already in -OutDir
#>
[CmdletBinding()]
param([string]$Repo = '', [string]$OutDir = '', [switch]$SkipBuild)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP "dl-uim-$PID" }
$ErrorActionPreference = 'Stop'
Write-Host '== UI-M field usage tests ==' -ForegroundColor Cyan
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$bat = Join-Path $Repo 'build\_build_fieldrepo_fieldusage_tests_local.bat'
$bin = Join-Path $OutDir 'FieldUsageTests.exe'
if (-not $SkipBuild) {
  $blog = Join-Path $OutDir 'build.log'
  $p = Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $OutDir + '" > "' + $blog + '" 2>&1"') -PassThru -NoNewWindow
  try { $p.PriorityClass = 'BelowNormal' } catch { Write-Verbose 'priority not set' }
  $p.WaitForExit()
  $bl = Get-Content -LiteralPath $blog -Raw
  if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|Error: E\d+')) {
    Write-Host "UIM: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path -LiteralPath $bin)) { Write-Host "UIM: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
$log = Join-Path $OutDir 'run.log'
& { $ErrorActionPreference = 'Continue'; & $bin *> $log }
$code = $LASTEXITCODE
$sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
if (-not $sum) { Write-Host 'UIM: FAIL -- no SUMMARY line' -ForegroundColor Red; exit 1 }
Write-Host "  $($sum.Line)"
if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'UIM: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'UIM: PASS' -ForegroundColor Green
exit 0
