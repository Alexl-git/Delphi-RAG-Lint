#Requires -Version 7.3
<#
  run_fieldrepo_backup.ps1 -- builds and runs the database backup tests (tests\fieldrepo\BackupTests.dpr): the list of backups and the
  purge on plain files, which hosts count as this machine, and backup + restore test + every refusal on a SCRATCH
  Firebird database that the test creates with a private embedded engine (lib\FirebirdEmbed.ps1; no server involved).
  No drag-lint engine needed. A MISSING Delphi toolchain or test exe is a FAIL. The only allowed SKIP is the live
  section L, and only on a machine without Firebird 4.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -SkipBuild  run the exe already on disk
#>
[CmdletBinding()]
param([string]$Repo = '',
      [switch]$SkipBuild)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\FirebirdEmbed.ps1')
Write-Host '== field repository database backup tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_fieldrepo_backup_tests_local.bat'
$bin = Join-Path $Repo 'tests\fieldrepo\BackupTests.exe'
$work = Join-Path ([IO.Path]::GetTempPath()) ('drag-lint-fieldrepo-backup-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$saved = @($env:FIREBIRD, $env:DL_TEST_FB_EMBED)
try {
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "FIELDREPO BACKUP: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) {
      Write-Host $bl
      Write-Host 'FIELDREPO BACKUP: FAIL -- the test runner did not build' -ForegroundColor Red
      exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "FIELDREPO BACKUP: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
  $embed = New-FirebirdEmbed (Join-Path $work 'fb')
  $env:DL_TEST_FB_EMBED = $embed
  if ($embed) { $env:FIREBIRD = $embed }
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $skips = @(Select-String -LiteralPath $log -Pattern '^SKIP')
  if (($skips.Count -gt 0) -and $embed) { Write-Host 'FIELDREPO BACKUP: FAIL -- the live section was skipped although Firebird 4 is here' -ForegroundColor Red; exit 1 }
  if ($skips.Count -gt 1) { Write-Host 'FIELDREPO BACKUP: FAIL -- unexpected SKIP lines' -ForegroundColor Red; exit 1 }
  if (-not $sum) { Write-Host 'FIELDREPO BACKUP: FAIL -- no SUMMARY line (the runner crashed)' -ForegroundColor Red; exit 1 }
  Write-Host "  $($sum.Line)"
  if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'FIELDREPO BACKUP: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'FIELDREPO BACKUP: PASS' -ForegroundColor Green
  exit 0
} finally {
  $env:FIREBIRD = $saved[0]
  $env:DL_TEST_FB_EMBED = $saved[1]
  try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "note: scratch folder kept: $work" }
}
