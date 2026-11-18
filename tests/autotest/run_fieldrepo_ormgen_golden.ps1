#Requires -Version 7.3
<#
  run_fieldrepo_ormgen_golden.ps1 -- lane TTGEN (1.52): ORM / DataService generators ported from
  TableTools onto the field repository (DRagLint.FieldRepo.OrmGen + DataServiceGen).

  PART 1 (always): builds and runs tests\fieldrepo\OrmGenTests.exe (unit checks on a repository
  built in %TEMP%). FAIL unless its SUMMARY reports fail=0.

  PART 2 (golden, needs a repository imported from the dev database): copies ORM3
  COMMON\OBJECTS\*.PAS, SERVER\*_SERVER.PAS and CLIENT\*_CLIENT.PAS into a work folder (ORM3 is
  only READ), runs update-orm over the COPY and lists per unit:
    BYTE-IDENTICAL | SAME-IGNORING-BLANKS | SAME-IGNORING-BLANKS-AND-CASE | DIFFERENT regions=<ids>
  plus OUTSIDE-CHANGED when a byte outside the DB-RAD regions moved (always a FAIL).
  The repository comes from -RepoFile, or is imported with -Connection / $env:DL_TEST_FB_CONNECTION
  (Firebird is only READ). Without either, part 2 prints SKIP.
  Byte parity below 100 percent is reported (the 1.52 cut line); -RequireParity makes it a FAIL.

  Run: pwsh -File tests\autotest\run_fieldrepo_ormgen_golden.ps1 [-RepoFile <x.dlrepo>]
         [-Connection "Database=..;User_Name=..;Password=.."] [-Orm3 C:\Projects\DB\ORM3]
         [-SkipBuild] [-RequireParity] [-Work <dir>]
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$RepoFile = '',
      [string]$Connection = $env:DL_TEST_FB_CONNECTION,
      [string]$Orm3 = 'C:\Projects\DB\ORM3',
      [string]$Work = '',
      [switch]$SkipBuild,
      [switch]$RequireParity)
$ErrorActionPreference = 'Stop'
Write-Host '== field repository ORM / DataService generator tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_fieldrepo_ormgen_tests_local.bat'
$bin = Join-Path $Repo 'tests\fieldrepo\OrmGenTests.exe'
if ($Work -eq '') { $Work = Join-Path $env:TEMP "drag-lint-ormgen-golden-$PID" }
[IO.Directory]::CreateDirectory($Work) | Out-Null
$failed = $false

# ---- part 1: unit checks ----
if (-not $SkipBuild) {
  if (-not (Test-Path -LiteralPath $bat)) { Write-Host "ORMGEN: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
  $blog = Join-Path $Work 'build.log'
  Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
  $bl = Get-Content -LiteralPath $blog -Raw
  if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error | Error: ')) {
    Write-Host "ORMGEN: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red
    exit 1
  }
}
if (-not (Test-Path -LiteralPath $bin)) { Write-Host "ORMGEN: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
$log = Join-Path $Work 'unit.log'
& $bin *> $log
$code = $LASTEXITCODE
$sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
if ($null -eq $sum -or $sum.Line -notmatch 'fail=0$' -or $code -ne 0) {
  Write-Host "ORMGEN UNIT: FAIL -- $($sum.Line) exit=$code (log: $log)" -ForegroundColor Red
  $failed = $true
} else {
  Write-Host "ORMGEN UNIT: PASS -- $($sum.Line)" -ForegroundColor Green
}

# ---- part 2: golden over a COPY of ORM3 ----
if ($RepoFile -eq '' -and [string]::IsNullOrWhiteSpace($Connection)) {
  Write-Host 'SKIP golden (no -RepoFile and no -Connection / DL_TEST_FB_CONNECTION)'
} elseif (-not (Test-Path -LiteralPath (Join-Path $Orm3 'COMMON\OBJECTS'))) {
  Write-Host "SKIP golden (ORM3 not found: $Orm3)"
} else {
  if ($RepoFile -eq '') {
    $RepoFile = Join-Path $Work 'dev-import.dlrepo'
    $imp = & $bin --import $Connection $RepoFile 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "ORMGEN GOLDEN: FAIL -- import failed: $imp" -ForegroundColor Red; exit 1 }
    Write-Host "  $($imp | Select-Object -Last 1)"
  }
  $copy = @{ OBJECTS = @('COMMON\OBJECTS', '*.PAS'); SERVER = @('SERVER', '*_SERVER.PAS'); CLIENT = @('CLIENT', '*_CLIENT.PAS') }
  foreach ($k in $copy.Keys) {
    $dst = Join-Path $Work $k
    [IO.Directory]::CreateDirectory($dst) | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $Orm3 $copy[$k][0]) -Filter $copy[$k][1] -File | ForEach-Object {
      [IO.File]::Copy($_.FullName, (Join-Path $dst $_.Name), $true)
    }
  }
  $report = Join-Path $Work 'golden-report.txt'
  & $bin --golden $RepoFile (Join-Path $Work 'OBJECTS') (Join-Path $Work 'SERVER') (Join-Path $Work 'CLIENT') $report | Out-Null
  $gcode = $LASTEXITCODE
  if (-not (Test-Path -LiteralPath $report)) { Write-Host 'ORMGEN GOLDEN: FAIL -- no report' -ForegroundColor Red; exit 1 }
  $lines = Get-Content -LiteralPath $report
  $lines | Where-Object { $_ -match 'DIFFERENT|OUTSIDE-CHANGED|^SKIPPED' -and $_ -notmatch '^GOLDEN ' } | ForEach-Object { Write-Host "  $_" }
  $g = $lines | Where-Object { $_ -match '^GOLDEN ' } | Select-Object -Last 1
  Write-Host "  $g"
  Write-Host "  per-unit list: $report ; regenerated copy: $Work"
  $m = [regex]::Match($g, 'units=(\d+) byte_identical=(\d+) .* outside_changed=(\d+)')
  if (-not $m.Success -or $gcode -ne 0 -or [int]$m.Groups[3].Value -ne 0) {
    Write-Host 'ORMGEN GOLDEN: FAIL -- text outside the DB-RAD regions changed (or no summary)' -ForegroundColor Red
    $failed = $true
  } else {
    $units = [int]$m.Groups[1].Value; $same = [int]$m.Groups[2].Value
    $pct = if ($units -gt 0) { [math]::Floor(100 * $same / $units) } else { 0 }
    Write-Host "ORMGEN GOLDEN PARITY: $same / $units byte-identical ($pct percent); outside the regions: unchanged"
    if ($RequireParity -and $same -ne $units) { Write-Host 'ORMGEN GOLDEN: FAIL -- -RequireParity' -ForegroundColor Red; $failed = $true }
  }
}
if ($failed) { exit 1 }
Write-Host 'ORMGEN: PASS' -ForegroundColor Green
exit 0
