#Requires -Version 7.3
<#
  run_fieldrepo_ormgen_golden.ps1 -- lane TTGEN (1.52): ORM / DataService generators ported from
  TableTools onto the field repository (DRagLint.FieldRepo.OrmGen + DataServiceGen).

  PART 1 (always): builds and runs tests\fieldrepo\OrmGenTests.exe (unit checks on a repository
  built in %TEMP%). FAIL unless its SUMMARY reports fail=0.

  PART 2 (golden, needs a repository imported from the dev database): copies ORM3
  COMMON\OBJECTS\*.PAS, SERVER\*_SERVER.PAS and CLIENT\*_CLIENT.PAS into a work folder (ORM3 is
  only READ), runs update-orm over the COPY and lists per unit:
    BYTE-IDENTICAL | SAME-IGNORING-BLANKS | SAME-IGNORING-BLANKS-AND-CASE |
    DELIBERATE-DRIFT deliberate=<ids> | DIFFERENT regions=<ids>
  DELIBERATE-DRIFT = the region is what TableTools wrote plus the named 1.54 change of that region id
  and nothing else (LegacyForm in OrmGenTests.dpr turns it back and compares).
  plus OUTSIDE-CHANGED when a byte outside the DB-RAD regions moved (always a FAIL).
  The repository comes from -RepoFile, or is imported with -Connection / $env:DL_TEST_FB_CONNECTION
  (Firebird is only READ). Without either, part 2 prints SKIP.
  Byte parity below 100 percent is reported; -RequireParity makes it a FAIL. Byte parity is not
  reachable on ORM3: its units were re-formatted (aligned, re-cased) after TableTools wrote them.
  -RequireForm (B33, 1.52) is the release gate instead: every unit must be the same ignoring
  blanks and case (or DELIBERATE-DRIFT in a region id that file lists with @region, each of which
  must occur), except the units listed in tests\fieldrepo\ormgen-golden-known-drift.txt
  (repository rows that differ from the unit, or a hand-edited region); a listed unit that is no
  longer DIFFERENT is reported as STALE and also fails, so the list cannot rot.

  Run: pwsh -File tests\autotest\run_fieldrepo_ormgen_golden.ps1 [-RepoFile <x.dlrepo>]
         [-Connection "Database=..;User_Name=..;Password=.."] [-Orm3 C:\Projects\DB\ORM3]
         [-SkipBuild] [-RequireParity] [-RequireForm] [-Work <dir>]
#>
[CmdletBinding()]
param([string]$Repo = '',
      [string]$RepoFile = '',
      [string]$Connection = $env:DL_TEST_FB_CONNECTION,
      [string]$Orm3 = 'C:\Projects\DB\ORM3',
      [string]$Work = '',
      [switch]$SkipBuild,
      [switch]$RequireParity,
      [switch]$RequireForm)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
. (Join-Path $PSScriptRoot 'lib\GoldenDrift.ps1')
try {
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
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
& { $ErrorActionPreference = 'Continue'; & $bin *> $log }
$code = $LASTEXITCODE
$sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
Select-String -LiteralPath $log -Pattern '^FAIL' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
if ($null -eq $sum -or $sum.Line -notmatch 'fail=0$' -or $code -ne 0) {
  Write-Host "ORMGEN UNIT: FAIL -- $($sum.Line) exit=$code (log: $log)" -ForegroundColor Red
  $failed = $true
} else {
  Write-Host "ORMGEN UNIT: PASS -- $($sum.Line)" -ForegroundColor Green
}

# ---- part 1b: positive control of the known-drift comparison (both failure directions must fire) ----
if (Test-GoldenDriftControl) { Write-Host 'ORMGEN DRIFT CONTROL: PASS -- unlisted and stale drift both fail' -ForegroundColor Green }
else { Write-Host 'ORMGEN DRIFT CONTROL: FAIL -- the known-drift comparison cannot fail' -ForegroundColor Red; $failed = $true }

# ---- part 2: golden over a COPY of ORM3 ----
if ($RepoFile -eq '' -and [string]::IsNullOrWhiteSpace($Connection)) {
  Write-Host 'SKIP golden (no -RepoFile and no -Connection / DL_TEST_FB_CONNECTION)'
} elseif (-not (Test-Path -LiteralPath (Join-Path $Orm3 'COMMON\OBJECTS'))) {
  Write-Host "SKIP golden (ORM3 not found: $Orm3)"
} else {
  if ($RepoFile -eq '') {
    $RepoFile = Join-Path $Work 'dev-import.dlrepo'
    $imp = & { $ErrorActionPreference = 'Continue'; & $bin --import $Connection $RepoFile 2>&1 | ForEach-Object { "$_" } }
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
    if ($RequireForm) {
      $driftFile = Join-Path $Repo 'tests\fieldrepo\ormgen-golden-known-drift.txt'
      $drift = Read-GoldenDrift -Path $driftFile
      $drift.Errors | ForEach-Object { Write-Host "  DRIFT FILE $_" -ForegroundColor Red }
      if ($drift.Errors.Count -gt 0) { Write-Host 'ORMGEN GOLDEN FORM: FAIL -- the known-drift file is malformed' -ForegroundColor Red; exit 1 }
      $known = Get-GoldenDriftKeys $drift
      # 1.54 TT-GENFIX: region ids that may differ ONLY by the named change (OrmGenTests LegacyForm)
      $okIds = Get-GoldenDriftKeys $drift 'region'
      $seenIds = @($lines | Where-Object { $_ -match '^UNIT ' } | ForEach-Object { [regex]::Match($_, 'deliberate=(.*)$').Groups[1].Value -split ' ' } | Where-Object { $_ } | Sort-Object -Unique)
      $cmpId = Compare-GoldenDrift -Listed $okIds -Actual $seenIds
      $badIds = @($cmpId.New); $staleIds = @($cmpId.Stale)
      $badIds | ForEach-Object { Write-Host "  UNLISTED deliberate region $_" -ForegroundColor Red }
      $staleIds | ForEach-Object { Write-Host "  STALE @region entry $_" -ForegroundColor Red }
      $diff = @($lines | Where-Object { $_ -match '^UNIT (\S+) DIFFERENT' } | ForEach-Object { ([regex]::Match($_, '^UNIT (\S+)')).Groups[1].Value.ToUpper() })
      $cmp = Compare-GoldenDrift -Listed $known -Actual $diff
      $new = @($cmp.New); $stale = @($cmp.Stale)
      $new | ForEach-Object { Write-Host "  NEW-DIFFERENT $_" -ForegroundColor Red }
      $stale | ForEach-Object { Write-Host "  STALE known-drift entry $_" -ForegroundColor Red }
      if ($new.Count -gt 0 -or $stale.Count -gt 0 -or $badIds.Count -gt 0 -or $staleIds.Count -gt 0) {
        Write-Host "ORMGEN GOLDEN FORM: FAIL -- $($new.Count) unlisted DIFFERENT, $($stale.Count) stale, $($badIds.Count) unlisted / $($staleIds.Count) stale region ids" -ForegroundColor Red; $failed = $true
      } else {
        Write-Host "ORMGEN GOLDEN FORM: PASS -- $($units - $diff.Count) / $units same ignoring blanks and case (deliberate regions: $($seenIds -join ' ')); $($diff.Count) known drift"
      }
    }
  }
}
if ($failed) { exit 1 }
Write-Host 'ORMGEN: PASS' -ForegroundColor Green
exit 0
} finally { Remove-WorkDir $Work -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
