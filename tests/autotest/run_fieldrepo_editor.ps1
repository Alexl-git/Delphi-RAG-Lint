#Requires -Version 7.3
<#
  run_fieldrepo_editor.ps1 -- builds BOTH field-repository editor builds and runs --selftest on each:
    dl-field-repo.exe      DevExpress cxGrid build (the DEFAULT shipped build, ruling A3)
    dl-field-repo-std.exe  TDBGrid build (fallback for source builds without DevExpress)
  --selftest checks 4 tabs and, per tab, the row and column counts (and an edit round trip).

  A MISSING DevExpress library, build script, build or exe is a FAIL here, never a skip.
  The DevExpress DCU folder comes from env DL_DEVEX_LIB (default: the RS37 Win64 folder under
  env DXVCL); the runner prints the path it used. Exit 0 only when both builds report fail=0.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -SkipBuild  run the exes already on disk
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Write-Host '== field repository editor (--selftest, both builds) ==' -ForegroundColor Cyan
$fail = 0
if (-not $env:DL_DEVEX_LIB) {
  $dx = if ($env:DXVCL) { $env:DXVCL } else { 'C:\Program Files (x86)\DevExpress\VCL' }
  $env:DL_DEVEX_LIB = Join-Path $dx 'Library\RS37\Win64'
}
Write-Host "  DL_DEVEX_LIB = $($env:DL_DEVEX_LIB)"
$work = Join-Path $env:TEMP "drag-lint-fieldrepo-editor-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$builds = @(
  @{ Name = 'DevEx'; Bat = 'build\_build_field_repo_local.bat';     Exe = 'src\tools\field-repo\dl-field-repo.exe';     Grid = 'DevExpress cxGrid' },
  @{ Name = 'Std';   Bat = 'build\_build_field_repo_std_local.bat'; Exe = 'src\tools\field-repo\dl-field-repo-std.exe'; Grid = 'TDBGrid' })
try {
  foreach ($b in $builds) {
    $tag = "FIELDREPO EDITOR [$($b.Name)]"
    $bat = Join-Path $Repo $b.Bat
    $bin = Join-Path $Repo $b.Exe
    if ($b.Name -eq 'DevEx' -and -not (Test-Path -LiteralPath (Join-Path $env:DL_DEVEX_LIB 'cxGrid.dcu'))) {
      Write-Host "$tag`: FAIL -- DevExpress library not found (no cxGrid.dcu in DL_DEVEX_LIB=$($env:DL_DEVEX_LIB)); the DevEx build is the default shipped build, so this is a FAIL, not a SKIP" -ForegroundColor Red
      $fail++; continue
    }
    if (-not $SkipBuild) {
      if (-not (Test-Path -LiteralPath $bat)) { Write-Host "$tag`: FAIL -- build script missing: $bat" -ForegroundColor Red; $fail++; continue }
      $blog = Join-Path $work "build-$($b.Name).log"
      Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
      $bl = Get-Content -LiteralPath $blog -Raw
      if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error |Fatal: ')) {
        Write-Host "$tag`: FAIL -- the build did not succeed (log: $blog)" -ForegroundColor Red
        $fail++; continue
      }
    }
    if (-not (Test-Path -LiteralPath $bin)) { Write-Host "$tag`: FAIL -- exe not found: $bin" -ForegroundColor Red; $fail++; continue }
    $log = Join-Path $work "run-$($b.Name).log"
    & $bin --selftest *> $log
    $code = $LASTEXITCODE
    $text = Get-Content -LiteralPath $log -Raw
    $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
    Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
    if (Select-String -LiteralPath $log -Pattern '^SKIP' -Quiet) { Write-Host "$tag`: FAIL -- a SKIP line is a vanished regression pin" -ForegroundColor Red; $fail++; continue }
    if (-not $sum) { Write-Host "$tag`: FAIL -- no SUMMARY line (the exe crashed or wrote nothing); log: $log" -ForegroundColor Red; $fail++; continue }
    if ($text -notmatch [regex]::Escape("GRID $($b.Grid)")) { Write-Host "$tag`: FAIL -- the exe did not report 'GRID $($b.Grid)' (wrong build?)" -ForegroundColor Red; $fail++; continue }
    if ($text -notmatch 'PASS tabs=4\b') { Write-Host "$tag`: FAIL -- no 'PASS tabs=4' line" -ForegroundColor Red; $fail++; continue }
    Write-Host "  $($b.Grid): $($sum.Line)"
    if (($code -ne 0) -or ($sum.Line -notmatch 'fail=0\b')) { Write-Host "$tag`: FAIL" -ForegroundColor Red; $fail++; continue }
    Write-Host "$tag`: PASS" -ForegroundColor Green
  }
} finally {
  if (Test-Path -LiteralPath $work) { try { [IO.Directory]::Delete($work, $true) } catch { $null = $_ } }
}
if ($fail -gt 0) { Write-Host "FIELDREPO EDITOR: FAIL ($fail build(s))" -ForegroundColor Red; exit 1 }
Write-Host 'FIELDREPO EDITOR: PASS' -ForegroundColor Green
exit 0
