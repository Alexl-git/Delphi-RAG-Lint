<#
  run_release_ships_wiki_guide_guard.ps1 -- docs\wiki\Wiki-Blocks-Authoring.md must be
  copied into the release zip by pack-lint-release.ps1 and shipped by the installer.

  STATIC: asserts the text of pack-lint-release.ps1 and installer\drag-lint.iss, and that
  the source file exists. POSITIVE CONTROL: each assertion is re-run on a copy with the
  matching line removed and must FAIL; a check that cannot fail proves nothing.
#>
[CmdletBinding()]
param([string]$Repo = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$scratch = Join-Path $env:TEMP ("rswg-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$fail = 0
try {
  $pack = Join-Path $Repo 'build\pack-lint-release.ps1'
  $iss  = Join-Path $Repo 'installer\drag-lint.iss'
  $src  = Join-Path $Repo 'docs\wiki\Wiki-Blocks-Authoring.md'
  if (Test-Path -LiteralPath $src) { Write-Host "PASS  source docs\wiki\Wiki-Blocks-Authoring.md exists" }
  else { Write-Host "FAIL  source docs\wiki\Wiki-Blocks-Authoring.md missing"; $fail++ }
  $checks = @(
    @('pack copies the guide into the zip', $pack, 'Copy-Item.*Wiki-Blocks-Authoring\.md.*\$stg'),
    @('installer ships the guide',          $iss,  '^\s*Source:.*Wiki-Blocks-Authoring\.md.*DestDir:\s*"\{app\}[\\]docs"')
  )
  foreach ($c in $checks) {
    $name, $file, $rx = $c
    $lines = [IO.File]::ReadAllLines($file)
    $hits = @($lines | Where-Object { $_ -match $rx })
    if ($hits.Count -ge 1) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name (no line matches $rx)"; $fail++ }
    $copy = Join-Path $scratch ([IO.Path]::GetFileName($file))
    [IO.File]::WriteAllLines($copy, @($lines | Where-Object { $_ -notmatch $rx }))
    $left = @([IO.File]::ReadAllLines($copy) | Where-Object { $_ -match $rx })
    if ($left.Count -eq 0) { Write-Host "PASS  control: $name fails when the line is removed" }
    else { Write-Host "FAIL  control: $name still passes with the line removed"; $fail++ }
  }
} finally { [IO.Directory]::Delete($scratch, $true) }
if ($fail -gt 0) { Write-Host "FAILED ($fail)"; exit 1 }
Write-Host "ALL PASS"; exit 0
