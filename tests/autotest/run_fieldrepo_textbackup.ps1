#Requires -Version 7.3
<#
  run_fieldrepo_textbackup.ps1 -- builds and runs the field-repository text backup tests
  (tests\fieldrepo\TextBackupTests.dpr, unit DRagLint.FieldRepo.TextBackup). No engine needed.

  A MISSING Delphi toolchain or test exe is a FAIL here, never a skip. Exit 0 only when the
  SUMMARY line reports fail=0 and the process exit code is 0.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -SkipBuild  run the exe already on disk
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Write-Host '== field repository text backup tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_fieldrepo_textbackup_tests_local.bat'
$bin = Join-Path $Repo 'tests\fieldrepo\TextBackupTests.exe'
$work = Join-Path $env:TEMP "drag-lint-fieldrepo-textbackup-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "FIELDREPO TEXTBACKUP: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) {
      Write-Host "FIELDREPO TEXTBACKUP: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red
      exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "FIELDREPO TEXTBACKUP: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
  $log = Join-Path $work 'run.log'
  & $bin *> $log
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $skips = @(Select-String -LiteralPath $log -Pattern '^SKIP')
  if ($skips.Count -gt 0) { Write-Host ("FIELDREPO TEXTBACKUP: FAIL -- $($skips.Count) SKIP line(s): a skipped check is a vanished regression pin") -ForegroundColor Red; exit 1 }
  if (-not $sum) { Write-Host 'FIELDREPO TEXTBACKUP: FAIL -- no SUMMARY line (the runner crashed)' -ForegroundColor Red; exit 1 }
  Write-Host "  $($sum.Line)"
  if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'FIELDREPO TEXTBACKUP: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'FIELDREPO TEXTBACKUP: PASS' -ForegroundColor Green
  exit 0
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
