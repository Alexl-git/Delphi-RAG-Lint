#Requires -Version 7.3
<#
  run_fieldrepo_fbconn.ps1 -- builds and runs tests\fieldrepo\FbConnStringTests.dpr: the refused --connection keys
  (unit DRagLint.Sql.FbConnString, pure) and the live Firebird 4 schema reader, against a SCRATCH database that this
  runner creates with a private embedded engine (lib\FirebirdScratch.ps1; no server, no user database is opened).
  No drag-lint engine needed. A MISSING Delphi toolchain or test exe is a FAIL. The live part SKIPs only on a machine
  without any Firebird 4; where the embedded engine exists a SKIP is a FAIL.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -SkipBuild  run the exe already on disk
#>
[CmdletBinding()]
param([string]$Repo = '',
      [switch]$SkipBuild)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\FirebirdScratch.ps1')
Write-Host '== field repository Firebird connection-string + live reader tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_fieldrepo_fbconn_tests_local.bat'
$bin = Join-Path $Repo 'tests\fieldrepo\FbConnStringTests.exe'
$work = Join-Path ([IO.Path]::GetTempPath()) ('drag-lint-fieldrepo-fbconn-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$saved = @($env:FIREBIRD, $env:DL_TEST_FB_EMBED, $env:DL_TEST_FB_CONNECTION)
try {
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "FIELDREPO FBCONN: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) {
      Write-Host $bl
      Write-Host 'FIELDREPO FBCONN: FAIL -- the test runner did not build' -ForegroundColor Red
      exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "FIELDREPO FBCONN: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
  $conn = New-ScratchFbConnection $work $Repo
  $env:DL_TEST_FB_CONNECTION = $conn
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $skips = @(Select-String -LiteralPath $log -Pattern '^SKIP')
  if (($skips.Count -gt 0) -and $conn) { Write-Host 'FIELDREPO FBCONN: FAIL -- the live part was skipped although Firebird 4 is here' -ForegroundColor Red; exit 1 }
  if (-not $sum) { Write-Host 'FIELDREPO FBCONN: FAIL -- no SUMMARY line (the runner crashed)' -ForegroundColor Red; exit 1 }
  Write-Host "  $($sum.Line)"
  if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'FIELDREPO FBCONN: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'FIELDREPO FBCONN: PASS' -ForegroundColor Green
  exit 0
} finally {
  $env:FIREBIRD = $saved[0]
  $env:DL_TEST_FB_EMBED = $saved[1]
  $env:DL_TEST_FB_CONNECTION = $saved[2]
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch folder kept: $work" }
}
