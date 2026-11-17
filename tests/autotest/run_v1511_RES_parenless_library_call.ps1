<#
  run_v1511_RES_parenless_library_call.ps1 -- 1.51.1 B04: a bare `read` that names
  a LIBRARY function callable without arguments is a call. The read ref carries
  refs.external_target (a library target has no call_edges row: the name on the
  ref IS the edge) with external_kind 'parenless-call', and the purity stage
  takes the library routine's effect summary for it.

  Fixture: tests\autotest\fixtures\v1511-RES (lib\ResLib.pas, proj\uResUse.pas,
  proj\uResShadow.pas, prog\ResProg.dpr).

    c1  `if AFlag and ResBump then`  -> ResLib.ResBump [parenless-call]
    c2  `Result := ResBump`          -> ResLib.ResBump [parenless-call]
    c3  the .dpr main block `if ResBump then` -> the same
    c4  purity: WrapBare carries g (ResBump writes a global) -- before B04 the
        caller read effect-free
    c5  `@ResBump` is the routine's ADDRESS: [proc-value], and AddrOnly takes no g
    c6  `@ResNeedsArg` (not callable bare): [proc-value]
    c7  negative: uResShadow declares its own ResOwn -- the read is the
        project's (a call edge to it), no external_target
    c8  positive control: with no library store no read carries a target and
        WrapBare has no g

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_v1511_res_b04_$PID",
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
$want    = 'ResLib.ResBump'
$unit    = 'uResUse.pas'

$savedSwitch = $env:DRAGLINT_LIBRARY_EFFECTS
$env:DRAGLINT_LIBRARY_EFFECTS = $null
Push-Location $env:TEMP
try {
  $fx   = Build-ResFixture $exePath $WorkDir
  $refs = Get-ResRefs $exePath $fx.Proj
  $bare = Get-ResRefs $exePath $fx.NoLib
  $sum  = Get-ResSummaries $exePath $fx.Proj
  $sum0 = Get-ResSummaries $exePath $fx.NoLib

  $a = Find-ResRef $refs $unit 'CheckBump' 'read' 'ResBump'
  Check (($null -ne $a) -and ($a.Target -eq $want) -and ($a.XKind -eq 'parenless-call')) "c1 AFlag and ResBump -> $want [parenless-call] (got '$($a.Target)' [$($a.XKind)])"

  $b = Find-ResRef $refs $unit 'WrapBare' 'read' 'ResBump'
  Check (($null -ne $b) -and ($b.Target -eq $want) -and ($b.XKind -eq 'parenless-call')) "c2 Result := ResBump -> $want [parenless-call] (got '$($b.Target)' [$($b.XKind)])"

  $c = Find-ResRef $refs 'ResProg.dpr' '' 'read' 'ResBump'
  Check (($null -ne $c) -and ($c.Target -eq $want) -and ($c.XKind -eq 'parenless-call')) "c3 .dpr main block: ResBump -> $want [parenless-call] (got '$($c.Target)' [$($c.XKind)])"

  Check (Test-ResFlag $sum['uResUse.WrapBare'] 'g') "c4 purity: WrapBare carries g from the library ResBump (got '$($sum['uResUse.WrapBare'])')"

  $d = Find-ResRef $refs $unit 'AddrOnly' 'read' 'ResBump'
  Check (($null -ne $d) -and ($d.Target -eq $want) -and ($d.XKind -eq 'proc-value') -and -not (Test-ResFlag $sum['uResUse.AddrOnly'] 'g')) "c5 @ResBump -> $want [proc-value], AddrOnly takes no g (got '$($d.Target)' [$($d.XKind)], summary '$($sum['uResUse.AddrOnly'])')"

  $e = Find-ResRef $refs $unit 'ArgOnly' 'read' 'ResNeedsArg'
  Check (($null -ne $e) -and ($e.Target -eq 'ResLib.ResNeedsArg') -and ($e.XKind -eq 'proc-value')) "c6 @ResNeedsArg -> ResLib.ResNeedsArg [proc-value] (got '$($e.Target)' [$($e.XKind)])"

  $own = Find-ResRef $refs 'uResShadow.pas' 'CallOwn' 'read' 'ResOwn'
  Check (($null -ne $own) -and ($own.Target -eq '')) "c7 a project ResOwn wins: external_target '$($own.Target)'"

  $leak = @($bare | Where-Object { $_.Kind -eq 'read' -and $_.Target -ne '' })
  Check (($leak.Count -eq 0) -and -not (Test-ResFlag $sum0['uResUse.WrapBare'] 'g')) "c8 no library store: no read target (got $($leak.Count)), WrapBare without g (got '$($sum0['uResUse.WrapBare'])')"
} finally {
  $env:DRAGLINT_LIBRARY_EFFECTS = $savedSwitch
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:fail) { Write-Host 'run_v1511_RES_parenless_library_call: FAIL'; exit 1 }
Write-Host 'run_v1511_RES_parenless_library_call: PASS'
exit 0
