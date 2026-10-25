<#
  run_charts_interface_loop.ps1 -- Test-InterfaceLoop (charts\src\Emit-Common.ps1) on synthetic graphs.

  This is the A-CY-ILOOP check that lived inside charts\src\Test-Emitters.ps1 (the cy2p step, ~line 876).
  Test-Emitters needs the scratch clone indexes (charts\scratch\db\*.sqlite), which are not in the repo, so the
  suite never ran under the battery and this self-contained check never executed. It needs no index: three
  hand-built edge maps.

    ring   a>b>c>a, all INTERFACE            -> True   (an all-interface loop: the compiler refuses it, F2047)
    mixIn  SCC whose b<->c sub-loop is all-interface -> True
    mixNo  every loop crosses an implementation use  -> False

  POSITIVE CONTROL: an edge map with NO interface edge must read False, and a deliberately wrong expectation
  must be seen to FAIL, so a Test-InterfaceLoop that always returned True (or a Check that always passed) is caught.
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$common = Join-Path $Repo 'charts\src\Emit-Common.ps1'
if (-not (Test-Path $common)) { Write-Host "FATAL: $common not found" -ForegroundColor Red; exit 2 }
. $common

$i = [pscustomobject]@{ section = 'interface' }
$m = [pscustomobject]@{ section = 'implementation' }
$ring  = @{ 'a|b' = $i; 'b|c' = $i; 'c|a' = $i }
$mixIn = @{ 'a|b' = $i; 'b|a' = $m; 'b|c' = $i; 'c|b' = $i }
$mixNo = @{ 'a|b' = $i; 'b|c' = $i; 'c|a' = $m }
$none  = @{ 'a|b' = $m; 'b|c' = $m; 'c|a' = $m }
$mem   = @('a', 'b', 'c')

$r = '{0}/{1}/{2}' -f (Test-InterfaceLoop $ring $mem), (Test-InterfaceLoop $mixIn $mem), (Test-InterfaceLoop $mixNo $mem)
Check 'A-CY-ILOOP ring/mixIn/mixNo = True/True/False' ($r -ceq 'True/True/False') "got $r"

Write-Host 'POSITIVE CONTROL' -ForegroundColor Cyan
Check 'an all-implementation cycle is NOT an interface loop' ((Test-InterfaceLoop $none $mem) -eq $false)
Check 'a wrong expectation is seen to fail (the comparison can fail)' (-not ($r -ceq 'True/True/True')) "got $r"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
