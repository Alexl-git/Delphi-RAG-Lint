[CmdletBinding()]
param([string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check([string]$Name,[bool]$Ok,[string]$Detail=''){
  $s = if($Ok){'PASS'}else{'FAIL'}; $c = if($Ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$Name,$Detail) -ForegroundColor $c
  if(-not $Ok){$script:Failed=$true}
}
if(-not(Test-Path $Exe)){Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2}

$out = (& $Exe contrast-selftest 2>&1) -join "`n"
Check 'black-on-white = 21.00' ($out -match 'BLACK_ON_WHITE=21\.00') $out
Check 'same color = 1.00'      ($out -match 'SAME=1\.00') $out
$dark = if($out -match 'DARKFAIL=([\d.]+)'){[double]$Matches[1]}else{99}
Check 'keyword-blue on dark FAILS 4.5' ($dark -lt 4.5) "ratio=$dark"
$fixed = if($out -match 'FIXED=([\d.]+)'){[double]$Matches[1]}else{0}
Check 'EnsureReadable clears 4.5' ($fixed -ge 4.5) "ratio=$fixed"

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red; exit 1}else{Write-Host 'PASS' -ForegroundColor Green; exit 0}
