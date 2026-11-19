#Requires -Version 7
<#
  run_v152_VSTOAST.ps1 -- 1.52 lane VSTOAST: VS Code extension restart/toast defects (U9 report).
  Runs test\restartguard.test.js (traffic dropped during a planned stop/start, grace covers the stop
  timeout, double restart coalesced, exit code 0 at info, old client disposed, no output-channel popups).
#>
[CmdletBinding()]
param([string]$Dir = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Dir) { $Dir = "$PSScriptRoot\..\..\editors\vscode\drag-lint" }
$ErrorActionPreference = 'Stop'
$fail = 0
function Check($n, $ok) { if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green } else { Write-Host "  [FAIL] $n" -ForegroundColor Red; $script:fail++ } }
Check 'node available' ($null -ne (Get-Command node -ErrorAction SilentlyContinue))
foreach ($t in 'restartguard', 'plannedstop') {
  $out = & { $ErrorActionPreference = 'Continue'; & node (Join-Path $Dir "test\$t.test.js") 2>&1 | ForEach-Object { "$_" } } | Out-String
  Check "$t.test.js passes" ($LASTEXITCODE -eq 0 -and $out -match 'all assertions passed')
}
if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS'; exit 0
