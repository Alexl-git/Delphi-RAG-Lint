<#
  run_v1511_RES_function_result_receiver.ps1 -- 1.51.1 B06: a member called on the
  result of a LIBRARY function binds refs.external_target, whether the function
  is named with parens, without, or held in an inferred inline var.

  Fixture: tests\autotest\fixtures\v1511-RES (lib\ResLib.pas, proj\uResUse.pas).

    c1  control: a typed parameter `AReg.OpenKey` binds (it did before B06)
    c2  `var Reg := ResReg; Reg.OpenKey`     -> ResLib.TResStore.OpenKey
    c3  `var RegC := ResReg(); RegC.OpenKey` -> ResLib.TResStore.OpenKey
    c4  `ResReg().OpenKey`                   -> ResLib.TResStore.OpenKey
    c5  `ResReg.OpenKey`                     -> ResLib.TResStore.OpenKey
    c6  `ResReg.Sub.OpenKey`                 -> ResLib.TResStore.OpenKey (a pending step)
    c7  negative: a PARAMETER named ResReg shadows the library function -- its
        member never binds through the library function's result type
    c8  positive control: with no library store none of c2-c6 binds

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Exe,   # 152 TESTS: no default engine (a runner must never silently test third_party\dll-win64)
  [string]$WorkDir = "$env:TEMP\draglint_v1511_res_b06_$PID",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([bool]$ok, [string]$what) {
  if ($ok) { if (-not $Quiet) { Write-Host "PASS  $what" } }
  else     { Write-Host "FAIL  $what" -ForegroundColor Red; $script:fail = $true }
}
. (Join-Path $PSScriptRoot 'fixtures\v1511-RES\common.ps1')

$exePath = (Resolve-Path $Exe).Path
$want    = 'ResLib.TResStore.OpenKey'
$unit    = 'uResUse.pas'
$sites   = @('OpenInline', 'OpenInlineCall', 'OpenParens', 'OpenBare', 'OpenChain')

Push-Location $env:TEMP
try {
  $fx   = Build-ResFixture $exePath $WorkDir
  $refs = Get-ResRefs $exePath $fx.Proj
  $bare = Get-ResRefs $exePath $fx.NoLib

  $ctl = Find-ResRef $refs $unit 'OpenParam' 'call' 'OpenKey'
  Check (($null -ne $ctl) -and ($ctl.Target -eq $want)) "c1 control: AReg.OpenKey -> $want (got '$($ctl.Target)')"

  $n = 2
  foreach ($s in $sites) {
    $r = Find-ResRef $refs $unit $s 'call' 'OpenKey'
    Check (($null -ne $r) -and ($r.Target -eq $want)) "c$n ${s}: receiver '$($r.Receiver)' -> $want (got '$($r.Target)')"
    $n++
  }

  $sh = @($refs | Where-Object { $_.File -eq $unit -and $_.Encl -eq 'OpenShadow' -and $_.Receiver -eq 'ResReg' })
  Check (($sh.Count -ge 1) -and (@($sh | Where-Object { $_.Target -like 'ResLib.*' }).Count -eq 0)) "c7 a parameter named ResReg is not typed through the library function ($($sh.Count) ref(s), targets: $(($sh | ForEach-Object Target) -join ','))"

  $leak = @($bare | Where-Object { $_.File -eq $unit -and $_.Target -ne '' })
  Check ($leak.Count -eq 0) "c8 no library store: no external_target at all (got $($leak.Count))"
} finally {
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:fail) { Write-Host 'run_v1511_RES_function_result_receiver: FAIL'; exit 1 }
Write-Host 'run_v1511_RES_function_result_receiver: PASS'
exit 0
