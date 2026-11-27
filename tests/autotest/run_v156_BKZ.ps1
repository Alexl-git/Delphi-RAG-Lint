#Requires -Version 7.3
<#
  run_v156_BKZ.ps1 -- builds and runs the v156 BK-Z backup formats (text, sql, zip): restore round trip per format
  (tests\fieldrepo\BackupFormatTests.dpr, units SqlBackup + ZipBackup). No engine needed.

  A MISSING Delphi toolchain or test exe is a FAIL here, never a skip. Exit 0 only when the
  SUMMARY line reports fail=0 and the process exit code is 0.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -SkipBuild  run the exe already on disk
#>
[CmdletBinding()]
param([string]$Repo = '',
      [switch]$SkipBuild)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
Write-Host '== field repository backup format tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_fieldrepo_backupformat_tests_local.bat'
$bin = Join-Path $Repo 'tests\fieldrepo\BackupFormatTests.exe'
$work = Join-Path $env:TEMP "drag-lint-v156-bkz-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "V156 BKZ: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) {
      Write-Host "V156 BKZ: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red
      exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "V156 BKZ: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $skips = @(Select-String -LiteralPath $log -Pattern '^SKIP')
  if ($skips.Count -gt 0) { Write-Host ("V156 BKZ: FAIL -- $($skips.Count) SKIP line(s): a skipped check is a vanished regression pin") -ForegroundColor Red; exit 1 }
  if (-not $sum) { Write-Host 'V156 BKZ: FAIL -- no SUMMARY line (the runner crashed)' -ForegroundColor Red; exit 1 }
  Write-Host "  $($sum.Line)"
  if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'V156 BKZ: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'V156 BKZ: PASS' -ForegroundColor Green
  exit 0
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
