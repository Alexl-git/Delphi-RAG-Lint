#Requires -Version 7
<#
  run_markerless_dproj_platform_guard.ps1 -- 144 lspctx tail / ruling a3 (L-C20): the per-file
  build lint, lint-all and the LSP preprocess against (TProjectProfileCache -> ResolveActiveBuild)
  takes the SAME platform the index takes (EffectiveIndexPlatform) for a .dproj with no active
  $(Platform) marker and no <project>.delphilsp.json: Win32. Before 148 LS it defaulted to Win64,
  so a Win32-only legacy project was linted with WIN64 / CPUX64 defines against a Win32 index.
    A  marker-less, Win32-only .dproj, no --platform -> pp-profile --in prints platform=Win32
       and the profile holds WIN32, not WIN64.
    B  POSITIVE CONTROL: the same project WITH a $(Platform) marker naming Win64 -> platform=Win64
       (the marker still decides; a guard that always printed Win32 fails here).
    C  CONTROL: an explicit --platform win64 on the marker-less project -> platform=Win64.
  Run from any CWD, pwsh 7. -Exe defaults to the repo build.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-markerless-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
. (Join-Path $PSScriptRoot 'lsp_stdio_helpers.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }

$unit = "unit uLegacy;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n"
function DprojText([string]$platformMarker) {
  $marker = if ($platformMarker) { "    <Platform Condition=`"'`$(Platform)'==''`">$platformMarker</Platform>`r`n" } else { '' }
  return "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`r`n  <PropertyGroup>`r`n" +
    "    <MainSource>Legacy.dpr</MainSource>`r`n$marker    <TargetedPlatforms>1</TargetedPlatforms>`r`n  </PropertyGroup>`r`n" +
    "  <ItemGroup>`r`n    <DCCReference Include=`"uLegacy.pas`"/>`r`n  </ItemGroup>`r`n</Project>`r`n"
}
function RunCase([string]$name, [string]$marker, [string[]]$extra) {
  $d = Join-Path $WorkDir $name
  New-Item -ItemType Directory $d -Force | Out-Null
  WriteAnsi (Join-Path $d 'uLegacy.pas') $unit
  WriteAnsi (Join-Path $d 'Legacy.dpr') "program Legacy;`r`n`r`nuses`r`n  uLegacy in 'uLegacy.pas';`r`n`r`nbegin`r`nend.`r`n"
  WriteAnsi (Join-Path $d 'Legacy.dproj') (DprojText $marker)
  $ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $Exe pp-profile --in (Join-Path $d 'uLegacy.pas') @extra 2>$null
  $ErrorActionPreference = $ea
  return @($out)
}
function Plat($out) { $l = @($out | Where-Object { $_ -like 'platform=*' }); if ($l.Count) { return $l[0].Substring(9) } else { return '' } }

Write-Host ''
Write-Host 'run_markerless_dproj_platform_guard -- marker-less .dproj lints as Win32 (ruling a3)' -ForegroundColor Cyan
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$a = RunCase 'a-markerless' '' @()
Check 'A: owning .dproj found' (@($a | Where-Object { $_ -like 'dproj=*Legacy.dproj' }).Count -eq 1) "out=$($a[0..4] -join ' | ')"
Check 'A: marker-less Win32-only .dproj -> platform=Win32' ((Plat $a) -eq 'Win32') "platform=$(Plat $a)"
Check 'A: profile holds WIN32, not WIN64' (($a -contains 'WIN32') -and -not ($a -contains 'WIN64')) "WIN32=$($a -contains 'WIN32') WIN64=$($a -contains 'WIN64')"
$b = RunCase 'b-marker64' 'Win64' @()
Check 'B control: a Win64 marker still decides -> platform=Win64' ((Plat $b) -eq 'Win64') "platform=$(Plat $b)"
$c = RunCase 'c-override' '' @('--platform', 'win64')
Check 'C control: --platform win64 wins -> platform=Win64' ((Plat $c) -eq 'Win64') "platform=$(Plat $c)"
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { exit 1 }
