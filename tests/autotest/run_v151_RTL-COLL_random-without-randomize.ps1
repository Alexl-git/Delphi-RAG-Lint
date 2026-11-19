# Guard: random-without-randomize (v151 lane RTL-COLL, project-wide, lint-all only).
# Fixture tests\autotest\fixtures\v151-RTL-COLL\random-without-randomize:
#   unseeded\uDice.pas:11  Random(6) in a project with no Randomize / RandSeed   -> FIRES (one finding)
#   seeded\uDice.pas       same unit, but uBoot.pas calls Randomize               -> silent
# Positive control: --disable random-without-randomize must remove the finding.
# Usage: pwsh -File tests/autotest/run_v151_RTL-COLL_random-without-randomize.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = '',
      [string]$WorkDir = "$env:TEMP\drag-lint-rtlcoll-rnd-$PID")
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok) {
  if ($Ok) { Write-Host "  [PASS] $Name" -ForegroundColor Green } else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$src = Join-Path $PSScriptRoot 'fixtures\v151-RTL-COLL\random-without-randomize'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
function Findings([string]$Case, [string[]]$Extra) {
  $d = Join-Path $WorkDir $Case
  New-Item -ItemType Directory -Force $d | Out-Null
  Get-ChildItem (Join-Path $src $Case) -File | ForEach-Object { Copy-Item $_.FullName $d -Force }
  $db = Join-Path $WorkDir "$Case.sqlite"
  & $Exe index $d --db $db 2>&1 | Out-Null
  $raw = & $Exe lint-all --db $db --rule random-without-randomize --json @Extra 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $f = @(); if ($b -ge 0) { try { $f = @($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
  return @($f | Where-Object { $_.rule -eq 'random-without-randomize' })
}
try {
  $u = Findings 'unseeded' @('--enable', 'random-without-randomize')
  Check 'unseeded: exactly one finding' ($u.Count -eq 1)
  # positive-control: random-without-randomize
  Check 'unseeded: at uDice.pas:11' (($u.Count -eq 1) -and ($u[0].file_path -match 'uDice\.pas$') -and ([int]$u[0].start_line -eq 11))
  $s = Findings 'seeded' @('--enable', 'random-without-randomize')
  Check 'seeded (Randomize in another unit): silent' ($s.Count -eq 0)
  $x = Findings 'unseeded' @('--disable', 'random-without-randomize')
  Check 'positive control: disabled rule reports nothing' ($x.Count -eq 0)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
