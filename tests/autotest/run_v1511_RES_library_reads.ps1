<#
  run_v1511_RES_library_reads.ps1 -- 1.51.1 B02: a bare `read` of a library
  unit-level var / const (`Application` in a .dpr main block) binds
  refs.external_target to the library declaration, external_kind 'value'.

  Fixture: tests\autotest\fixtures\v1511-RES (lib\ResLib.pas, prog\ResProg.dpr,
  proj\uResUse.pas, proj\uResShadow.pas).

    c1  ResProg.dpr main block: both `GResApp` reads -> ResLib.GResApp, kind value --
        although a project class (uResShadow.TResOther) has a PROPERTY of that name
    c2  uResUse.ReadApp (a routine of a unit): `GResApp` -> ResLib.GResApp
    c3  the member calls on it keep their binding (ResLib.TResStore.OpenKey)
    c4  negative: uResShadow declares its own GResOwn -- its read is bound to
        the PROJECT symbol and carries no external_target
    c5  positive control: with no library store no read carries one
    c6  the stage reports the reads it bound

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_v1511_res_b02_$PID",
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
$want    = 'ResLib.GResApp'

Push-Location $env:TEMP
try {
  $fx   = Build-ResFixture $exePath $WorkDir
  $refs = Get-ResRefs $exePath $fx.Proj
  $bare = Get-ResRefs $exePath $fx.NoLib

  $main = @($refs | Where-Object { $_.File -eq 'ResProg.dpr' -and $_.Kind -eq 'read' -and $_.Name -eq 'GResApp' })
  $ok   = @($main | Where-Object { $_.Target -eq $want -and $_.XKind -eq 'value' })
  Check (($main.Count -eq 2) -and ($ok.Count -eq 2)) "c1 .dpr main block: $($ok.Count) of $($main.Count) GResApp read(s) -> $want [value] (expected 2 of 2)"

  $u = Find-ResRef $refs 'uResUse.pas' 'ReadApp' 'read' 'GResApp'
  Check (($null -ne $u) -and ($u.Target -eq $want) -and ($u.XKind -eq 'value')) "c2 unit routine: GResApp -> $want [value] (got '$($u.Target)' [$($u.XKind)])"

  $m = @($refs | Where-Object { $_.File -eq 'ResProg.dpr' -and $_.Kind -eq 'call' -and $_.Name -eq 'OpenKey' })
  Check (($m.Count -eq 2) -and (@($m | Where-Object { $_.Target -eq 'ResLib.TResStore.OpenKey' }).Count -eq 2)) "c3 the member calls keep ResLib.TResStore.OpenKey (got $(($m | ForEach-Object Target) -join ','))"

  $own = Find-ResRef $refs 'uResShadow.pas' 'ReadOwn' 'read' 'GResOwn'
  Check (($null -ne $own) -and ($own.Target -eq '') -and ($own.SymbolId -gt 0)) "c4 a project GResOwn wins: symbol bound ($($own.SymbolId)), external_target '$($own.Target)'"

  $leak = @($bare | Where-Object { $_.Kind -eq 'read' -and $_.Target -ne '' })
  Check ($leak.Count -eq 0) "c5 no library store: no read carries an external_target (got $($leak.Count))"

  Check ($fx.Log -match 'library-reads: [1-9]\d* of \d+ bare read\(s\) bound') "c6 the stage reports the library reads it bound"
} finally {
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:fail) { Write-Host 'run_v1511_RES_library_reads: FAIL'; exit 1 }
Write-Host 'run_v1511_RES_library_reads: PASS'
exit 0
