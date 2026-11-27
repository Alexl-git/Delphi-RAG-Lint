#Requires -Version 7.3
<#
  run_v156_UIP.ps1 -- lane UI-P (1.56 USEDICON): the Select Fields usage icons (model). Builds and runs
  tests\plugin\fieldselect\FieldSelectTests.dpr; prints the ICON lines (icon index per field and kind).
  A missing toolchain or exe is a FAIL, never a skip. Parameters: -Repo, -OutDir, -SkipBuild.
#>
[CmdletBinding()]
param([string]$Repo = '', [string]$OutDir = '', [switch]$SkipBuild)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP "dl-uip-$PID" }
$ErrorActionPreference = 'Stop'
Write-Host '== UI-P select-fields usage icons ==' -ForegroundColor Cyan
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$bat = Join-Path $Repo 'build\_build_plugin_fieldselect_tests_local.bat'
$bin = Join-Path $OutDir 'FieldSelectTests.exe'
if (-not $SkipBuild) {
  $blog = Join-Path $OutDir 'build.log'
  $p = Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" "' + $OutDir + '" > "' + $blog + '" 2>&1"') -PassThru -NoNewWindow; $null = $p.Handle
  try { $p.PriorityClass = 'BelowNormal' } catch { Write-Verbose 'priority not set' }
  $p.WaitForExit()
  $bl = Get-Content -LiteralPath $blog -Raw
  if (($bl -notmatch 'MODEL_EXITCODE=0') -or ($bl -notmatch 'FORMS_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|Error: E\d+')) {
    Write-Host "UIP: FAIL -- the runner did not build (log: $blog)" -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path -LiteralPath $bin)) { Write-Host "UIP: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
$log = Join-Path $OutDir 'run.log'
& { $ErrorActionPreference = 'Continue'; & $bin *> $log }
$code = $LASTEXITCODE
Select-String -LiteralPath $log -Pattern '^ICON ' | ForEach-Object { Write-Host "  $($_.Line)" }
Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
$sum = Select-String -LiteralPath $log -Pattern '^Summary: ' | Select-Object -Last 1
if (-not $sum) { Write-Host 'UIP: FAIL -- no Summary line' -ForegroundColor Red; exit 1 }
Write-Host "  $($sum.Line)"
if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'UIP: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'UIP: PASS' -ForegroundColor Green
exit 0
