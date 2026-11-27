#Requires -Version 7.3
<#
  run_v156_LIN1.ps1 -- 1.56 lane LIN-1: the read-only lineage model of pre-calculated data fields
  (src\sql\DRagLint.FieldRepo.Lineage.pas; spec 2026-11-27-derived-field-lineage-design.md sections 2, 3.1, 5.2).

  Copies tests\fixtures\v156\LIN1 to a scratch folder, indexes the COPY with the engine (the B14 facts), builds
  tests\fieldrepo\LineageTests.dpr and runs it on that index:
    T1      M.X := Q.A * Q.B -> derived, direct, inputs A + B, the statement text       (milestone LIN-1.1)
    T2      a local on the path, a by-name input, the DFM event binding                  (DL-1 A, DL-3, DL-5)
    T3      NOT derived: `:= Now` (no field input), a field nobody writes                (control: T1 / T2, same form)
    T4      project call / parameter = unknown + reason; Round(field) = direct            (control: R3)
    T5-T6   in / after a loop over ANOTHER dataset = aggregate; own dataset = direct      (control: SEQ)
    T7      name built at run time marks no field; Lookup; `with` over two datasets       (control: U1B)
    T8      a write from another unit does not mark the field                             (control: Y)
    T9-T10  unknown unit, missing index, unit changed after indexing (stale: no guess)

  Positive control of the whole runner: an engine WITHOUT the B14 facts (older than lane EXT-B3) makes the
  model raise "no field lineage facts" -> FAIL; a model that answers "not derived" fails T1.
  A MISSING toolchain, engine or test exe is a FAIL, never a skip. Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.

  Parameters:
    -Exe          engine to index with (default: src\cli\Win64\Debug\drag-lint.exe, else third_party\dll-win64)
    -SkipBuild    run the test exe already on disk
    -KeepScratch  leave the scratch folder
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipBuild, [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path -LiteralPath $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
Write-Host '== v156 LIN-1: field lineage model ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "V156 LIN1: FAIL -- no engine at $Exe" -ForegroundColor Red; exit 1 }
$bat  = Join-Path $repo 'build\_build_fieldrepo_lineage_tests_local.bat'
$bin  = Join-Path $repo 'tests\fieldrepo\LineageTests.exe'
$fx   = Join-Path $repo 'tests\fixtures\v156\LIN1'
$work = Join-Path $env:TEMP ('dl-v156-lin1-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$code = 1
try {
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "V156 LIN1: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error | Fatal: ')) {
      Write-Host "V156 LIN1: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red
      $KeepScratch = $true
      exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "V156 LIN1: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }

  # the fixtures are indexed as a COPY: the last test edits one of them
  $dir = Join-Path $work 'fx'
  Copy-Item -LiteralPath $fx -Destination $dir -Recurse
  $db   = Join-Path $work 'lin1.sqlite'
  $ilog = Join-Path $work 'index.log'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $dir --db $db *> $ilog }
  if (($LASTEXITCODE -ne 0) -or -not (Test-Path -LiteralPath $db)) {
    Write-Host "V156 LIN1: FAIL -- the fixture index failed (exit $LASTEXITCODE, log: $ilog)" -ForegroundColor Red
    $KeepScratch = $true
    exit 1
  }

  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin $db $dir *> $log }
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  $skips = @(Select-String -LiteralPath $log -Pattern '^SKIP')
  if ($skips.Count -gt 0) { Write-Host "V156 LIN1: FAIL -- $($skips.Count) SKIP line(s)" -ForegroundColor Red; exit 1 }
  if (-not $sum) { Write-Host 'V156 LIN1: FAIL -- no SUMMARY line (the test exe crashed)' -ForegroundColor Red; exit 1 }
  Write-Host "  $($sum.Line)"
  if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b') -or ($sum.Line -match 'pass=0\b')) {
    Write-Host 'V156 LIN1: FAIL' -ForegroundColor Red
    exit 1
  }
  Write-Host 'V156 LIN1: PASS' -ForegroundColor Green
  exit 0
} finally {
  if ($KeepScratch) { Write-Host "  scratch kept: $work" }
  elseif (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
}
