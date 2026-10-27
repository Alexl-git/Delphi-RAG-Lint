# Guard: unused-public-symbol own-unit-only tier (clippy-parity L11; folds in the
# clippy visibility-could-be-reduced idea). An exported routine whose every
# reference sits inside its OWN unit gets a hint: it could move out of the
# interface section.
#
# Fixture tests\lint-project\own-unit-tier:
#   OnlyInternal   - exported, called only by InternalDriver in the same unit -> tier hint (positive)
#   UsedElsewhere  - exported, called from uConsumer                         -> silent (negative)
#   NeverUsed      - exported, no refs at all -> the ORIGINAL "possible dead public API" info, NOT the tier
#
# Usage: pwsh -File tests/autotest/run_unused_public_symbol_own_unit_tier.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-own-unit-tier-$PID"
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
  $fx = Join-Path $PSScriptRoot '..\lint-project\own-unit-tier'
  $db = Join-Path $WorkDir 'fx.sqlite'
  & $Exe index $fx --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)
  $raw = & $Exe lint-all --db $db --rule unused-public-symbol --format json 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $f = @(); if ($b -ge 0) { try { $f = @($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
  $f | ForEach-Object { Write-Host ("  [{0}] {1}:{2} {3}" -f $_.severity, $_.file_path, $_.start_line, $_.message) -ForegroundColor DarkGray }
  $only  = @($f | Where-Object { $_.message -match '\bOnlyInternal\b' })
  $used  = @($f | Where-Object { $_.message -match '\bUsedElsewhere\b' })
  $never = @($f | Where-Object { $_.message -match '\bNeverUsed\b' })
  Check 'positive: OnlyInternal reported' ($only.Count -eq 1)
  Check 'positive: tier wording (own unit)' (($only.Count -eq 1) -and ($only[0].message -match 'only referenced within its own unit'))
  Check 'positive: severity hint' (($only.Count -eq 1) -and ($only[0].severity -eq 'hint'))
  # NEGATIVE CONTROLS
  Check 'negative: UsedElsewhere (cross-unit caller) silent' ($used.Count -eq 0)
  Check 'negative: NeverUsed keeps the dead-API wording' (($never.Count -eq 1) -and ($never[0].message -match 'possible dead public API') -and ($never[0].message -notmatch 'own unit'))
} finally {
  [IO.Directory]::Delete($WorkDir, $true)
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
