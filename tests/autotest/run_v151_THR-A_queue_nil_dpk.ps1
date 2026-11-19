# run_v151_THR-A_queue_nil_dpk.ps1 -- queue-nil-in-package: package membership comes from a .dpk contains list.
# Copies the fixture to a temp folder, adds Pkg.dpk (stored as Pkg.dpk.txt so no tool sees a live package here),
# and checks: PkgUnit.pas fires, AppUnit.pas does not, and with the .dpk removed PkgUnit.pas goes silent again
# (positive control).
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$exePath = (Resolve-Path (Join-Path $repo $Exe) -ErrorAction SilentlyContinue)
if (-not $exePath) { $exePath = (Resolve-Path $Exe) }
$exePath = $exePath.Path
$src = Join-Path $PSScriptRoot "fixtures\v151-THR-A\queue-nil-in-package"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("thra-queue-" + [Guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$fail = 0
function Count-Hits([string]$file) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint $file --rule queue-nil-in-package --json 2>$null }
  $f = @(); try { $f = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { }
  return @($f | Where-Object { $_.rule -eq 'queue-nil-in-package' }).Count
}
try {
  Copy-Item (Join-Path $src "*.pas") $tmp
  Copy-Item (Join-Path $src "Pkg.dpk.txt") (Join-Path $tmp "Pkg.dpk")
  $a = Count-Hits (Join-Path $tmp "PkgUnit.pas")
  $b = Count-Hits (Join-Path $tmp "AppUnit.pas")
  [IO.File]::Delete((Join-Path $tmp "Pkg.dpk"))
  $c = Count-Hits (Join-Path $tmp "PkgUnit.pas")
  if ($a -ne 1) { Write-Host "FAIL listed unit: expected 1 hit, got $a"; $fail++ }
  if ($b -ne 0) { Write-Host "FAIL unlisted unit: expected 0 hits, got $b"; $fail++ }
  if ($c -ne 0) { Write-Host "FAIL positive control (no .dpk): expected 0 hits, got $c"; $fail++ }
} finally {
  [IO.Directory]::Delete($tmp, $true)
}
if ($fail -eq 0) { Write-Host "PASS queue-nil-in-package dpk membership (1 / 0 / 0)"; exit 0 } else { exit 1 }
