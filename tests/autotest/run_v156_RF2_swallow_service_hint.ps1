<#
  run_v156_RF2_swallow_service_hint.ps1 -- 1.56 RF-2 (Q27): `try-except-swallowed` adds a hint for a
  service / console unit (log file + EurekaLog report with call stack). Text only: detection of the
  swallow is unchanged, so both fixtures fire; only the SERVICE message carries the hint.
  Positive control: the hint substring must be in the service finding; negative: absent from the VCL one.
#>
[CmdletBinding()]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$Exe = (Resolve-Path $Exe).Path
$script:Failed = $false
function Check($n, $ok) {
  Write-Host ("  [{0}] {1}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $n)
  if (-not $ok) { $script:Failed = $true }
}
function Get-SwallowMsg([string]$Name) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint "$PSScriptRoot\fixtures\v156-rf2\$Name" --rule try-except-swallowed --json --quiet 2>$null | ForEach-Object { "$_" } } | Out-String
  $j = $raw.Substring($raw.IndexOf('[')) | ConvertFrom-Json | ForEach-Object { $_ }
  return @($j | Where-Object { $_.rule_id -eq 'try-except-swallowed' -or $_.rule -eq 'try-except-swallowed' } | ForEach-Object { $_.message })
}
$svc = @(Get-SwallowMsg 'RF2Service.pas')
$vcl = @(Get-SwallowMsg 'RF2Vcl.pas')
Check 'service fixture still fires (1 finding)' ($svc.Count -eq 1)
Check 'VCL fixture still fires (1 finding)' ($vcl.Count -eq 1)
Check 'service message carries the log-file + EurekaLog hint' ($svc.Count -eq 1 -and $svc[0] -match 'log file' -and $svc[0] -match 'EurekaLog' -and $svc[0] -match 'call stack')
Check 'VCL message has NO hint' ($vcl.Count -eq 1 -and $vcl[0] -notmatch 'EurekaLog' -and $vcl[0] -notmatch 'log file')
if ($script:Failed) { exit 1 } else { exit 0 }
