# Guard: duplicate-unit-on-search-path (clippy-parity L11, project-wide, structure).
#
# Q6 (measured 2026-10-27): index membership does NOT evict a second file with the
# same unit stem. The closure dedupes by full path only, and a directory index
# admits both; FindUnitFile first-file-wins only governs `uses` resolution. So
# the symbol DB holds two files named uDup.pas and the rule groups files by stem.
#
# Fixture tests\lint-project\dup-unit: a\uDup.pas + b\uDup.pas (positive, one
# finding per file) and uUnique.pas (negative control: unique stem).
#
# Usage: pwsh -File tests/autotest/run_duplicate_unit_on_search_path.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-dup-unit-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $fx = Join-Path $PSScriptRoot '..\lint-project\dup-unit'
  $db = Join-Path $WorkDir 'fx.sqlite'
  & $Exe index $fx --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)
  $raw = & $Exe lint-all --db $db --rule duplicate-unit-on-search-path --format json 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $f = @(); if ($b -ge 0) { try { $f = @($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
  $f | ForEach-Object { Write-Host ("  {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) -ForegroundColor DarkGray }
  $a  = @($f | Where-Object { $_.rule -eq 'duplicate-unit-on-search-path' -and $_.file_path -match '\\a\\uDup\.pas$' })
  $bb = @($f | Where-Object { $_.rule -eq 'duplicate-unit-on-search-path' -and $_.file_path -match '\\b\\uDup\.pas$' })
  Check 'positive: a\uDup.pas flagged' ($a.Count -eq 1)
  Check 'positive: b\uDup.pas flagged' ($bb.Count -eq 1)
  Check 'message names the other file' (($a.Count -eq 1) -and ($a[0].message -match 'b\\uDup\.pas'))
  Check 'severity is warning' (($a.Count -eq 1) -and ($a[0].severity -eq 'warning'))
  # NEGATIVE CONTROL -- a unique stem must stay silent; a rule that flagged everything would pass the arms above.
  $u = @($f | Where-Object { $_.file_path -match 'uUnique\.pas$' })
  Check 'negative: unique stem uUnique.pas not flagged' ($u.Count -eq 0)
  Check 'only the two duplicate files are reported' ($f.Count -eq 2)
} finally {
  [IO.Directory]::Delete($WorkDir, $true)
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
