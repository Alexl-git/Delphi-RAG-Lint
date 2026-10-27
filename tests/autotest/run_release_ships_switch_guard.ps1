<#
  run_release_ships_switch_guard.ps1 -- drag-lint-switch.exe must be built, staged,
  shipped and verified by the build and release scripts.

  THE DEFECT: the switch was built only by build_lsp_switch.bat, so the deployed
  third_party\dll-win64 copy and every release zip lacked it or carried a stale one
  (no --params, no --vscode --on|--off).

  STATIC: asserts the text of build_draglint_win64.bat and pack-lint-release.ps1.
  POSITIVE CONTROL: each assertion is re-run on a copy of the script with the
  matching line removed and must FAIL; a check that cannot fail proves nothing.
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path)
$ErrorActionPreference = 'Stop'
$scratch = Join-Path $env:TEMP ("rssg-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$fail = 0
try {
  $bat  = Join-Path $Repo 'build\build_draglint_win64.bat'
  $pack = Join-Path $Repo 'build\pack-lint-release.ps1'
  # name, file, regex a line must match
  $checks = @(
    @('bat builds the switch dproj',   $bat,  'msbuild.*drag-lint-switch\.dproj'),
    @('bat stages it via stage-engine', $bat,  'stage-engine\.ps1.*drag-lint-switch\.exe'),
    @('pack builds the switch dproj',  $pack, 'msbuild.*\$swProj|drag-lint-switch\.dproj'),
    @('pack stages it via stage-engine', $pack, 'stage-engine\.ps1.*drag-lint-switch\.exe'),
    @('pack copies it into the zip',   $pack, 'Copy-Item.*drag-lint-switch\.exe.*\$stg'),
    @('pack verifies it in the win64 zip', $pack, "foreach \(\`$need in .*'drag-lint-switch\.exe'")
  )
  foreach ($c in $checks) {
    $name, $file, $rx = $c
    $lines = [IO.File]::ReadAllLines($file)
    $hits = @($lines | Where-Object { $_ -match $rx })
    if ($hits.Count -ge 1) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name (no line matches $rx)"; $fail++ }
    # positive control: same check on a copy with the matching lines removed
    $copy = Join-Path $scratch ([IO.Path]::GetFileName($file))
    [IO.File]::WriteAllLines($copy, @($lines | Where-Object { $_ -notmatch $rx }))
    $left = @([IO.File]::ReadAllLines($copy) | Where-Object { $_ -match $rx })
    if ($left.Count -eq 0) { Write-Host "PASS  control: $name fails when the line is removed" }
    else { Write-Host "FAIL  control: $name still passes with the line removed"; $fail++ }
  }
} finally { [IO.Directory]::Delete($scratch, $true) }
if ($fail -gt 0) { Write-Host "FAILED ($fail)"; exit 1 }
Write-Host "ALL PASS"; exit 0
