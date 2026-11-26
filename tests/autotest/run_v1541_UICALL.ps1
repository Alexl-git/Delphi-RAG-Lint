#Requires -Version 7
<#
  run_v1541_UICALL.ps1 -- 1.54.1 INT: ui-call-in-console-or-service asks the PROGRAM, as writeln-in-gui-app does.

  Both halves of the rule decided "console program" by matching {$APPTYPE CONSOLE} in the raw .dpr text: the
  per-file v151 check (DRagLint.V151.APP.Support UiCallInConsoleOrService) and the cross-unit APP2 pass
  (DRagLint.V152.APP2.Support CONSOLE_RE). So a .dproj with DCC_ConsoleTarget (dcc -CC) was missed, a
  {$APPTYPE CONSOLE} inside a comment counted, and a later {$APPTYPE GUI} did not win. Now both use the
  writeln-in-gui-app helper (ProjectHasConsole / the run's program probe, lane CONSOLE 2ff48067d).

  Every case is one project folder: App.dpr (one direct ShowMessage, one call to UAsk.Ask) + UAsk.pas (Ask
  shows a dialog) + App.dproj, indexed with `index --project`.
    lint App.dpr        -> the per-file check: 1 finding in a console program (the direct call), 0 otherwise
    lint-all            -> per-file + cross-unit: 2 findings in a console program (direct call + the call to Ask)

  With the pre-change engine the cases d1 / m1 / m2 FAIL (RED); the controls pass.

  Usage: pwsh -File tests\autotest\run_v1541_UICALL.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v1541_uicall_$PID"
)
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe  = (Resolve-Path $Exe).Path
$Rule = 'ui-call-in-console-or-service'

$script:Fail = 0
$script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function Put([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Dpr([string]$Head) {
  "program App;`n$Head`nuses`n  Vcl.Dialogs,`n  UAsk in 'UAsk.pas';`nbegin`n  ShowMessage('direct');`n  Ask;`nend.`n"
}
function Dproj([string]$Win64 = '') {
  $c64 = if ($Win64) { "<DCC_ConsoleTarget>$Win64</DCC_ConsoleTarget>" } else { '' }
  @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{5E1B6C1B-1541-4C0E-9A55-0123456789AC}</ProjectGuid>
        <MainSource>App.dpr</MainSource>
        <Config Condition="'`$(Config)'==''">Debug</Config>
        <Platform Condition="'`$(Platform)'==''">Win64</Platform>
        <TargetedPlatforms>3</TargetedPlatforms>
        <AppType>Application</AppType>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Base' or '`$(Base)'!=''">
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="('`$(Platform)'=='Win64' and '`$(Base)'=='true') or '`$(Base_Win64)'!=''">
        <Base_Win64>true</Base_Win64>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Debug' or '`$(Cfg_1)'!=''">
        <Cfg_1>true</Cfg_1>
        <CfgParent>Base</CfgParent>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base)'!=''">
        <DCC_Namespace>System;Vcl;`$(DCC_Namespace)</DCC_Namespace>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base_Win64)'!=''">
        <VerInfo_Locale>1033</VerInfo_Locale>
        $c64
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="App.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
        <DCCReference Include="UAsk.pas"/>
    </ItemGroup>
</Project>
"@
}
$UnitText = @'
unit UAsk;

interface

procedure Ask;

implementation

uses
  Vcl.Dialogs;

procedure Ask;
begin
  ShowMessage('from the unit');
end;

end.
'@
function New-Case([string]$Name, [string]$DprText, [string]$DprojText) {
  $d = Join-Path $WorkDir $Name
  [void](New-Item -ItemType Directory -Force -Path $d)
  Put (Join-Path $d 'UAsk.pas') $UnitText
  Put (Join-Path $d 'App.dpr') $DprText
  Put (Join-Path $d 'App.dproj') $DprojText
  $db = Join-Path $d 'App.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $d 'App.dproj') --db $db *> (Join-Path $d 'index.log') }
  if (-not (Test-Path $db)) { throw "no index for case $Name" }
  return $db
}
# lint / lint-all --json print a bare array.
function Hits([string]$Json) {
  if ($Json.Trim() -eq '') { return 0 }
  return @($Json | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.rule -eq $Rule }).Count
}
function LintHits([string]$File, [string[]]$Extra) {
  return Hits ((& { $ErrorActionPreference = 'Continue'; & $Exe lint $File --json @Extra 2>$null }) -join "`n")
}
function LintAllHits([string]$Db) {
  return Hits ((& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --json 2>$null }) -join "`n")
}

[void](New-Item -ItemType Directory -Force -Path $WorkDir)
Push-Location $WorkDir
try {
  $cases = @(
    # name, program head, DCC_ConsoleTarget Win64, console expected, what it proves
    @('c0', '{$APPTYPE CONSOLE}',                    '',     $true,  '$APPTYPE CONSOLE (positive control)'),
    @('g0', '',                                      '',     $false, 'GUI program (negative control)'),
    @('d1', '',                                      'true', $true,  'DCC_ConsoleTarget of the platform, no $APPTYPE'),
    @('m1', '// {$APPTYPE CONSOLE}',                 '',     $false, '$APPTYPE CONSOLE inside a comment'),
    @('m2', '{$APPTYPE CONSOLE}{$APPTYPE GUI}',      '',     $false, 'the last unconditional $APPTYPE wins'),
    @('m3', '{$IFDEF X}{$APPTYPE CONSOLE}{$ENDIF}',  '',     $true,  'conditional $APPTYPE CONSOLE counts')
  )
  foreach ($c in $cases) {
    $db = New-Case $c[0] (Dpr $c[1]) (Dproj $c[2])
    $n1 = LintHits (Join-Path $WorkDir "$($c[0])\App.dpr") @('--db', $db)
    $n2 = LintAllHits $db
    $w1 = if ($c[3]) { 1 } else { 0 }
    $w2 = if ($c[3]) { 2 } else { 0 }
    Check "$($c[0]) lint App.dpr: $($c[4]) -> $w1" ($n1 -eq $w1) "got $n1"
    Check "$($c[0]) lint-all: $($c[4]) -> $w2"     ($n2 -eq $w2) "got $n2"
  }
  # a loose .dpr (no index): its own text still decides
  $loose = Join-Path $WorkDir 'loose'
  [void](New-Item -ItemType Directory -Force -Path $loose)
  Put (Join-Path $loose 'App.dpr') (Dpr '{$APPTYPE CONSOLE}')
  Check 'u1 loose console .dpr, no --db: fires' ((LintHits (Join-Path $loose 'App.dpr') @()) -eq 1)
  Put (Join-Path $loose 'App.dpr') (Dpr '// {$APPTYPE CONSOLE}')
  Check 'u2 loose .dpr, $APPTYPE only in a comment: silent' ((LintHits (Join-Path $loose 'App.dpr') @()) -eq 0)
}
finally { Pop-Location }

Write-Host ("run_v1541_UICALL: {0} pass, {1} failure(s)" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
