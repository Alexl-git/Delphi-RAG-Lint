#Requires -Version 7.3
<#
  run_v156_UIM.ps1 -- lane UI-M (1.56 USEDICON): field-usage query (DRagLint.FieldRepo.FieldUsage).
  Builds and runs tests\fieldrepo\FieldUsageTests.dpr: unit tests over hand-built index tables (M*/K*) AND over a real\n  index of tests\fixtures\v156\UIM made by the engine (R*).
  A missing toolchain or exe is a FAIL, never a skip. Exit 0 only when SUMMARY reports fail=0.
  Parameters: -Repo <root> (default: two levels above this script); -OutDir <dir> build output (default: a temp dir);
              -SkipBuild  run the exe already in -OutDir
              -Engine <drag-lint.exe> engine that indexes tests\fixtures\v156\UIM for the real-index cases R1..R8
                          (default: <Repo>\third_party\dll-win64\drag-lint.exe, else the shared one); the index lands in -OutDir
              -Engine <drag-lint.exe> (default: <Repo>\third_party\dll-win64\drag-lint.exe) indexes tests\fixtures\v156\UIP for the indexed case I1..I5; needs an engine with schema 25 (dfm_properties); a missing engine is a FAIL
#>
[CmdletBinding()]
param([string]$Repo = '', [string]$OutDir = '', [switch]$SkipBuild, [string]$Engine = '')
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Engine) { $Engine = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe' }
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
if (-not $Engine) {
  $Engine = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe'
  if (-not (Test-Path -LiteralPath $Engine)) { $Engine = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path -LiteralPath $Engine)) { Write-Host "UIM: FAIL -- engine not found: $Engine" -ForegroundColor Red; exit 1 }
$fixture = Join-Path $Repo 'tests\fixtures\v156\UIM'
$fxDb = Join-Path $OutDir 'uim-fixture.sqlite'
Remove-Item -LiteralPath $fxDb -ErrorAction SilentlyContinue
& { $ErrorActionPreference = 'Continue'; & $Engine index $fixture --db $fxDb *> (Join-Path $OutDir 'index.log') }
if (($LASTEXITCODE -ne 0) -or -not (Test-Path -LiteralPath $fxDb)) { Write-Host "UIM: FAIL -- the fixture did not index (log: $OutDir\index.log)" -ForegroundColor Red; exit 1 }
$log = Join-Path $OutDir 'run.log'
& { $ErrorActionPreference = 'Continue'; & $bin $fxDb *> $log }
$code = $LASTEXITCODE
$sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
if (-not (Select-String -LiteralPath $log -Pattern '^PASS R1 ' -Quiet)) { Write-Host 'UIM: FAIL -- the real-index cases did not run (no PASS R1)' -ForegroundColor Red; exit 1 }
if (-not $sum) { Write-Host 'UIM: FAIL -- no SUMMARY line' -ForegroundColor Red; exit 1 }
Write-Host "  $($sum.Line)"
if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'UIM: FAIL' -ForegroundColor Red; exit 1 }
$fxDb = Join-Path $OutDir 'fx.sqlite'
if (Test-Path -LiteralPath $fxDb) { [IO.File]::Delete($fxDb) }
if (-not (Test-Path -LiteralPath $Engine)) { Write-Host "UIM: FAIL -- engine not found for the indexed case: $Engine" -ForegroundColor Red; exit 1 }
& { $ErrorActionPreference = 'Continue'; & $Engine index (Join-Path $Repo 'tests\fixtures\v156\UIP') --db $fxDb *> (Join-Path $OutDir 'index.log') }
if (-not (Test-Path -LiteralPath $fxDb)) { Write-Host 'UIM: FAIL -- the engine wrote no fixture DB' -ForegroundColor Red; exit 1 }
$ilog = Join-Path $OutDir 'run-indexed.log'
& { $ErrorActionPreference = 'Continue'; & $bin --db $fxDb *> $ilog }
$icode = $LASTEXITCODE
$isum = Select-String -LiteralPath $ilog -Pattern '^SUMMARY ' | Select-Object -Last 1
Select-String -LiteralPath $ilog -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
if (-not $isum) { Write-Host 'UIM: FAIL -- no SUMMARY line from the indexed case' -ForegroundColor Red; exit 1 }
Write-Host "  indexed: $($isum.Line)"
if (($icode -ne 0) -or ($isum.Line -notmatch 'fail=0\b')) { Write-Host 'UIM: FAIL (indexed case)' -ForegroundColor Red; exit 1 }
Write-Host 'UIM: PASS' -ForegroundColor Green
exit 0
