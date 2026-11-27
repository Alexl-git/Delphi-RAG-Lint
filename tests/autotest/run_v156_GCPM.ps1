#Requires -Version 7.3
<#
  run_v156_GCPM.ps1 -- builds and runs the grid copy model tests (1.56 lane GCP-M: copy events and columns between grid view types, or one event)
  (tests\fieldrepo\GridCopyTests.dpr; unit DRagLint.FieldRepo.GridCopy on testsixturesieldrepogridcopy). No engine needed.

  A MISSING Delphi toolchain or test exe is a FAIL here, never a skip. Exit 0 only when the
  SUMMARY line reports fail=0 and the process exit code is 0.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -SkipBuild  run the exe already on disk
    -SkipForm   leave out part 2 (a machine without DevExpress)

  PART 1  the unit tests: plans, refusals, renderings and the applied BYTES of every case.
  PART 2  the fixture form, copied by `GridCopyTests.exe --apply`, COMPILES (dcc64) and LOADS before and after:
    F1 control   F2 written with backups   F3 band + view events   F4 new columns, the copied handler runs
    F5 the updated handler   F6 the source view untouched   F7 a second copy writes nothing   F8 card view
#>
[CmdletBinding()]
param([string]$Repo = '',
      [switch]$SkipBuild,
      [switch]$SkipForm)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
Write-Host '== v156 GCP-M: grid copy model tests ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'build\_build_fieldrepo_gridcopy_tests_local.bat'
$bin = Join-Path $Repo 'tests\fieldrepo\GridCopyTests.exe'
$work = Join-Path $env:TEMP "drag-lint-v156-gcpm-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "V156 GCPM: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) {
      Write-Host "V156 GCPM: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red
      exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "V156 GCPM: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $skips = @(Select-String -LiteralPath $log -Pattern '^SKIP')
  if ($skips.Count -gt 0) { Write-Host ("V156 GCPM: FAIL -- $($skips.Count) SKIP line(s): a skipped check is a vanished regression pin") -ForegroundColor Red; exit 1 }
  if (-not $sum) { Write-Host 'V156 GCPM: FAIL -- no SUMMARY line (the runner crashed)' -ForegroundColor Red; exit 1 }
  Write-Host "  $($sum.Line)"
  if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host 'V156 GCPM: FAIL' -ForegroundColor Red; exit 1 }
  if ($SkipForm) { Write-Host 'V156 GCPM: PASS (unit tests only: -SkipForm)' -ForegroundColor Green; exit 0 }
  # ---- part 2: the written form compiles and LOADS (dcc64 + DevExpress), before and after a copy ----
  $script:bad = 0
  function Check($n, $ok, $d = '') {
    Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
    if (-not $ok) { $script:bad++ }
  }
  $fix = Join-Path $Repo 'tests\fixtures\fieldrepo\gridcopy'
  $formBat = Join-Path $Repo 'build\_build_fieldrepo_gridcopy_form_local.bat'
  function NewForm($name) {
    $d = Join-Path $work $name
    [IO.Directory]::CreateDirectory($d) | Out-Null
    foreach ($f in 'uCopy.dfm', 'uCopy.pas', 'GridCopyLoad.dpr') { [IO.File]::Copy((Join-Path $fix $f), (Join-Path $d $f), $true) }
    $d
  }
  function BuildForm($dir) {
    $l = Join-Path $dir 'b.log'
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $formBat + '" "' + $dir + '" > "' + $l + '" 2>&1"') -Wait -NoNewWindow
    $t = Get-Content -LiteralPath $l -Raw
    if ($t -notmatch 'BUILD_EXITCODE=0') { return 'BUILD FAILED ' + (($t -split "`n" | Select-String 'Error|Fatal' | Select-Object -First 3) -join ' / ') }
    (& { $ErrorActionPreference = 'Continue'; & (Join-Path $dir 'GridCopyLoad.exe') 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  }
  function Copy-Grid($dir, $source, $target) {
    (& { $ErrorActionPreference = 'Continue'; & $bin --apply $dir $source $target 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  }
  $before = BuildForm (NewForm 'load0')
  Check 'F1 control: the fixture form loads; the banded view has 1 column, no band, no draw handler; the card view is empty' (($before -match 'LOADED$') -and ($before -match '(?m)^bvMain\|TcxGridDBBandedTableView\|items=1\|bands=0\|draw=\|dblclick=tvMainCellDblClick\r?$') -and ($before -match '(?m)^cvMain\|TcxGridDBCardView\|items=0\|bands=none\|draw=\|dblclick=\r?$') -and ($before -match 'bvMainNAME\|TcxGridDBBandedColumn\|Name\|caption=NAME\|band=-1\|editor=\|text=bvMainNAMEGetDisplayText>x\|')) $before
  $band = NewForm 'band'
  $w = Copy-Grid $band 'tvMain' 'bvMain'
  Check 'F2 table view -> banded table view is written: DFM and unit, a backup of each' (($w -match 'WRITTEN 2$') -and (@(Get-ChildItem -LiteralPath $band -Filter '*.before-write-dfm-*').Count -eq 2)) $w
  $after = BuildForm $band
  Check 'F3 the written form compiles and loads; the view has its band and the view events' (($after -match 'LOADED$') -and ($after -match '(?m)^bvMain\|TcxGridDBBandedTableView\|items=3\|bands=1\|draw=tvMainCustomDrawCell\|dblclick=tvMainCellDblClick\r?$')) $after
  Check 'F4 the new columns: class, field, band 0, editor, published, and the copied handler RUNS on them' (($after -match '(?m)^  bvMainCODE\|TcxGridDBBandedColumn\|CODE\|caption=Code\|band=0\|editor=TcxComboBoxProperties\|text=tvMainCODEGetDisplayText>\[x\]\|draw=\|published=TRUE\r?$') -and ($after -match '(?m)^  bvMainQTY\|TcxGridDBBandedColumn\|QTY\|caption=Quantity\|band=0\|editor=\|text=tvMainCODEGetDisplayText>\[x\]\|draw=tvMainQTYCustomDrawCell\|published=TRUE\r?$')) $after
  Check 'F5 the column that was there has the source handler now (the unchecked update was chosen by `all`)' ($after -match '(?m)^  bvMainNAME\|TcxGridDBBandedColumn\|Name\|caption=NAME\|band=-1\|editor=\|text=tvMainNAMEGetDisplayText>X\|draw=\|published=TRUE\r?$') $after
  Check 'F6 the source view is as before' ((($after -split "`n" | Select-Object -First 4) -join '|') -ceq (($before -split "`n" | Select-Object -First 4) -join '|')) $after
  $w = Copy-Grid $band 'tvMain' 'bvMain'
  Check 'F7 a second copy has nothing to do and writes nothing' (($w -match '0 changes, 0 blocked, 0 unchecked') -and ($w -match 'WRITTEN 0$') -and (@(Get-ChildItem -LiteralPath $band -Filter '*.before-write-dfm-*').Count -eq 2)) $w
  $card = NewForm 'card'
  $w = Copy-Grid $card 'tvMain' 'cvMain'
  $after = BuildForm $card
  Check 'F8 table view -> card view: written, compiles, loads; rows with class, field, editor and handlers' (($w -match 'WRITTEN 2$') -and ($after -match 'LOADED$') -and ($after -match '(?m)^cvMain\|TcxGridDBCardView\|items=3\|bands=none\|draw=tvMainCustomDrawCell\|dblclick=tvMainCellDblClick\r?$') -and ($after -match '(?m)^  cvMainCODE\|TcxGridDBCardViewRow\|CODE\|caption=Code\|band=none\|editor=TcxComboBoxProperties\|text=tvMainCODEGetDisplayText>\[x\]\|draw=\|published=TRUE\r?$') -and ($after -match '(?m)^  cvMainNAME\|TcxGridDBCardViewRow\|NAME\|caption=NAME\|band=none\|editor=\|text=tvMainNAMEGetDisplayText>X\|') -and ($after -match '(?m)^  cvMainQTY\|TcxGridDBCardViewRow\|QTY\|caption=Quantity\|.*draw=tvMainQTYCustomDrawCell\|published=TRUE\r?$')) ($w + "`n" + $after)
  if ($script:bad -gt 0) { Write-Host "V156 GCPM: FAIL -- $($script:bad) form check(s)" -ForegroundColor Red; exit 1 }
  Write-Host 'V156 GCPM: PASS' -ForegroundColor Green
  exit 0
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
