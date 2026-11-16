# Guard (v1511 lane PROJ, R5): uses-movable-to-implementation must not credit a unit for a NAME it
# merely shares with a parameter / local of the audited file (INBOX-orm3-fp-hunt-151 #5: 170 of 289
# CLIENT findings were units referenced nowhere).
# Fixture tests\lint-project\uses-movable-name-collision: uMain uses uPlib (PProc called in the
# implementation only -> FIRES, positive control), uQcoll (declares a PARAMETER V that uMain also
# names) and uRcoll (parameter X likewise) -> both SILENT: nothing of them is used.
# Usage: pwsh -File tests/autotest/run_v1511_PROJ_uses_movable_name_collision.ps1 [-Exe <path>]
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-proj-umnc-$PID")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\g8-common.ps1"
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$rule = 'uses-movable-to-implementation'
try {
  $fx = New-G8Scratch 'uses-movable-name-collision' $WorkDir
  $db = Join-Path $WorkDir 'fx.sqlite'
  Check 'index exits 0' ((Invoke-G8Index $Exe $fx $db) -eq 0)
  $f = Get-G8Findings $Exe $db $rule
  Show-G8Findings $f
  Check 'positive: uPlib (PProc called in the implementation) flagged' (@($f | Where-Object { $_.message -match '^uPlib\b' }).Count -eq 1)
  Check 'negative: uQcoll (shares only the parameter name V) silent' (@($f | Where-Object { $_.message -match '^uQcoll\b' }).Count -eq 0)
  Check 'negative: uRcoll (shares only the parameter name X) silent' (@($f | Where-Object { $_.message -match '^uRcoll\b' }).Count -eq 0)
} finally { [IO.Directory]::Delete($WorkDir, $true) }
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
