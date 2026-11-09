<#
  run_battery_pwsh7_guard.ps1 -- GD (wave 148): the battery driver must refuse Windows PowerShell 5 with one line
  and exit 2 (the engine's stderr banner kills ~1000 runners under PS5), and the docs must say "pwsh 7".
  Positive control: the same driver under pwsh 7 enumerates (-List) and exits 0.
  Run under pwsh 7:  pwsh -File tests\autotest\run_battery_pwsh7_guard.ps1
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== battery pwsh7 guard ==' -ForegroundColor Cyan
$bat = Join-Path $Repo 'tests\run_battery.ps1'
$ps5 = (Get-Command powershell.exe -ErrorAction SilentlyContinue)
if ($ps5) {
  $o = (& $ps5.Source -NoProfile -File $bat -List 2>&1 | Out-String); $c = $LASTEXITCODE
  Check 'PS5: battery refuses, exit 2, names pwsh 7' (($c -eq 2) -and ($o -match 'pwsh 7')) "(exit $c)"
  Check 'PS5: refusal is one line' (@($o -split "\r?\n" | Where-Object { $_.Trim() }).Count -eq 1)
} else { Write-Host '  [SKIP] powershell.exe (PS5) not present' -ForegroundColor Yellow }
$o7 = (& pwsh -NoProfile -File $bat -List 2>&1 | Out-String); $c7 = $LASTEXITCODE
Check 'CONTROL pwsh 7: -List enumerates and exits 0' (($c7 -eq 0) -and ($o7 -match 'run_.*\.ps1')) "(exit $c7)"
foreach ($d in 'tests\README.md', 'docs\AI-USAGE.md') {
  Check "doc states pwsh 7: $d" ([IO.File]::ReadAllText((Join-Path $Repo $d)) -match 'run under \*\*pwsh 7\*\*|Guards run under pwsh 7')
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
