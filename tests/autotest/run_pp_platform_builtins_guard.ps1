<#
  run_pp_platform_builtins_guard.ps1 -- `pp-profile --platform <P>` prints the
  engine built-in define set of each Delphi 13 target platform (lane ext-plat).

  Per platform: every must-have symbol present, every must-not-have absent.
  POSITIVE CONTROLS: Win32 / Win64 keep their exact old sets (win32 has no
  win64, Win64 has no cpux64 change); an unknown platform name still gets the
  Win64 default set.

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
function Get-Set($plat) {
  $out = & $Exe pp-profile --platform $plat 2>&1 | ForEach-Object { "$_".Trim().ToLowerInvariant() }
  ,@($out | Where-Object { $_ -match '^[a-z_][a-z0-9_]*$' })
}
$common = 'unicode','conditionalexpressions','ver370','nativecode','dcc','weakref'
$cases = [ordered]@{
  'Win32'      = @{ has = @('mswindows','win32','cpux86','cpu386','cpu32bits','assembler','underscoreimportname') + $common; not = @('win64','posix','cpu64bits','cpux64','compiler_version_37') }
  'Win64'      = @{ has = @('mswindows','win64','cpu64bits','cpux64','assembler') + $common; not = @('win32','posix','linux','cpux86_64','compiler_version_37') }
  'Win64x'     = @{ has = @('mswindows','win64','cpu64bits','cpux64') + $common; not = @('win32','posix','linux') }
  'Linux64'    = @{ has = @('linux','linux64','posix','posix64','cpux64','cpu64bits','externallinker') + $common; not = @('mswindows','win64','macos','android') }
  'OSX64'      = @{ has = @('macos','macos64','osx','osx64','posix','posix64','cpux64','cpu64bits') + $common; not = @('mswindows','linux','ios','cpuarm64') }
  'OSXARM64'   = @{ has = @('macos','macos64','osx','osx64','posix','posix64','cpuarm','cpuarm64','cpu64bits') + $common; not = @('mswindows','linux','ios','cpux64') }
  'Android'    = @{ has = @('android','android32','posix','posix32','cpuarm','cpuarm32','cpu32bits') + $common; not = @('mswindows','android64','linux','cpu64bits') }
  'Android64'  = @{ has = @('android','android64','posix','posix64','cpuarm','cpuarm64','cpu64bits') + $common; not = @('mswindows','android32','linux','cpu32bits') }
  'iOSDevice64'= @{ has = @('ios','ios64','iosdevice','iosdevice64','macos','posix','posix64','cpuarm','cpuarm64','cpu64bits') + $common; not = @('mswindows','iossimulator','android') }
  'iOSSimARM64'= @{ has = @('ios','ios64','iossimulator','macos','posix','posix64','cpuarm','cpuarm64','cpu64bits') + $common; not = @('mswindows','iosdevice','android') }
}
foreach ($p in $cases.Keys) {
  $set = Get-Set $p
  Write-Host "== $p ($($set.Count) symbols)"
  foreach ($s in $cases[$p].has) { Check "$p has $s" ($set -contains $s) }
  foreach ($s in $cases[$p].not) { Check "$p lacks $s" ($set -notcontains $s) }
}
# Compiler ground truth (dcc32 / dcc64 probe, 2026-10-28): EXACT sets.
$exact = @{
  'Win32' = 'assembler,conditionalexpressions,cpu32bits,cpu386,cpux86,dcc,mswindows,nativecode,underscoreimportname,unicode,ver370,weakref,win32'
  'Win64' = 'assembler,conditionalexpressions,cpu64bits,cpux64,dcc,mswindows,nativecode,unicode,ver370,weakref,win64'
}
foreach ($p in $exact.Keys) { $got = ((Get-Set $p) | Sort-Object) -join ','; Check "$p EXACT = compiler output" ($got -eq $exact[$p]) $got }
$unk = Get-Set 'NoSuchPlatform'; $w64 = Get-Set 'Win64'
Check 'unknown platform = Win64 default set' ((($unk -join ',') -eq ($w64 -join ',')) -and $unk.Count -gt 0)
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
