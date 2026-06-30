# unused-private-member + unused-unit-in-uses fixture test.
# Indexes a tiny multi-unit project, runs lint-all --db, and asserts:
#   - unused-private-member fires for UnusedPrivateMethod and FUnusedField in producer.pas
#   - unused-private-member does NOT fire for UsedPublicMethod
#   - unused-unit-in-uses fires for helper (implementation-section, zero symbols used)
#   - unused-unit-in-uses fires for helper2 (interface-section, zero symbols used)
#   - unused-unit-in-uses does NOT fire for producer (UsedPublicMethod referenced)
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$dir = $PSScriptRoot
$db  = Join-Path $env:TEMP "unused_private_test.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }

Write-Host "Indexing fixture..."
& $exePath index $dir --db $db | Out-Null

Write-Host "Running lint-all..."
$raw = & $exePath lint-all --db $db --format json 2>$null
$txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
$f = @(); if ($b -ge 0) { try { $f = ($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
if ($null -eq $f) { $f = @() }

$privFindings = @($f | Where-Object { $_.rule -eq 'unused-private-member' })
$usesFindings = @($f | Where-Object { $_.rule -eq 'unused-unit-in-uses' })

Write-Host "unused-private-member findings:"
$privFindings | ForEach-Object { Write-Host ("  {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) }
Write-Host "unused-unit-in-uses findings:"
$usesFindings | ForEach-Object { Write-Host ("  {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) }

# ASSERT 1: unused-private-member fires for UnusedPrivateMethod (producer.pas)
$hasUnusedMethod = ($privFindings | Where-Object { $_.message -like '*UnusedPrivateMethod*' }).Count -gt 0
# ASSERT 2: unused-private-member fires for FUnusedField (producer.pas)
$hasUnusedField  = ($privFindings | Where-Object { $_.message -like '*FUnusedField*' }).Count -gt 0
# ASSERT 3: unused-private-member does NOT fire for UsedPublicMethod (it is public, not private)
$noPublicFP      = ($privFindings | Where-Object { $_.message -like '*UsedPublicMethod*' }).Count -eq 0
# ASSERT 4: unused-unit-in-uses fires for helper (implementation-section import; match 'helper' exactly, not helper2)
$hasUnusedHelper = ($usesFindings | Where-Object { $_.message -like "*'helper'*" }).Count -gt 0
# ASSERT 5: unused-unit-in-uses fires for helper2 (interface-section import)
$hasUnusedHelper2 = ($usesFindings | Where-Object { $_.message -like "*'helper2'*" }).Count -gt 0
# ASSERT 6: unused-unit-in-uses does NOT fire for producer (symbols ARE referenced)
$noProducerFP    = ($usesFindings | Where-Object { $_.message -like "*'producer'*" }).Count -eq 0

$pass = $hasUnusedMethod -and $hasUnusedField -and $noPublicFP -and $hasUnusedHelper -and $hasUnusedHelper2 -and $noProducerFP

if ($pass) {
  Write-Host "PASS  unused-private + unused-unit-in-uses (impl + interface section)"
  exit 0
} else {
  Write-Host ("FAIL  hasUnusedMethod={0} hasUnusedField={1} noPublicFP={2} hasUnusedHelper={3} hasUnusedHelper2={4} noProducerFP={5}" -f $hasUnusedMethod, $hasUnusedField, $noPublicFP, $hasUnusedHelper, $hasUnusedHelper2, $noProducerFP)
  exit 1
}
