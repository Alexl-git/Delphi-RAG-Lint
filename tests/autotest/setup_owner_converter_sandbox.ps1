<#
  setup_owner_converter_sandbox.ps1 -- (re)creates the T-CONV owner-test sandbox for the
  ConvRulesEditor GUI card (readability, scope line, convert one component, rule-chain dialog).

  Why: the sandbox used to live in C:\TEMP\claude\lanes\146\ide-test\converter-sandbox and was
  hand-made; a disk purge (2026-11-22) deleted it. This script is now its only source.
  The fixture is the one drive-convert-request.ps1 builds for itself (C12 driver), plus the
  chain book of drive-rule-chains.ps1 -- keep the three in step.

  Creates under -Root (default C:\TEMP\owner-tests\converter-sandbox):
    Fix.dproj / Fix.dpr / FixUnit.pas + FixUnit.dfm (Label1, Label2: TLabel; Btn1: TButton)
    rules\Fix.rules (#convert TLabel -> TStaticText) / rules\Btn.rules (#convert TButton -> TcxButton)
    _D-RAG\Fix.sqlite       the project index, built with -Engine
    req-selected.json       convert-request/1, scope 'selected', Label1
    Chain.rules             a two-stage chain TTable -> TFDTable -> TFDMemTable (lines 2, 4)
    start-real.cmd          the editor on the real ORM3 AssignGroups unit (read only: do not Convert/Save)
    start-request.cmd       the editor with --convert-request req-selected.json
    start-chain.cmd         the editor on Chain.rules (Ctrl+S shows the Rule chains dialog)

  Card facts it guarantees (checked at the end, exit 1 if one fails): FixUnit.dfm line 7
  '  object Label1: TLabel', line 12 '  object Label2: TLabel'; FixUnit.pas line 10
  '    Label1: TLabel;', line 11 '    Label2: TLabel;'; the index exits 0 and knows TFixForm.

  Usage: pwsh -NoProfile -File setup_owner_converter_sandbox.ps1 [-Root <dir>] [-Editor <ConvRulesEditor.exe>]
           [-Engine <drag-lint.exe>] [-RealForm <AssignGroups.pas>]
  -Editor defaults to third_party\dll-win64\ConvRulesEditor.exe of this repo (the deployed one);
  -Engine defaults to the drag-lint.exe beside -Editor. An existing -Root is replaced.
#>
[CmdletBinding()]
param(
  [string]$Root     = 'C:\TEMP\owner-tests\converter-sandbox',
  [string]$Editor   = '',
  [string]$Engine   = '',
  [string]$RealForm = 'C:\Projects\DB\ORM3\CLIENT\AssignGroups.pas'
)
$ErrorActionPreference = 'Stop'
if (-not $Editor) { $Editor = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\ConvRulesEditor.exe' }
if (-not (Test-Path -LiteralPath $Editor)) { Write-Host "FATAL: no editor: $Editor" -ForegroundColor Red; exit 2 }
$Editor = (Resolve-Path -LiteralPath $Editor).Path
if (-not $Engine) { $Engine = Join-Path (Split-Path -Parent $Editor) 'drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Engine)) { Write-Host "FATAL: no engine: $Engine" -ForegroundColor Red; exit 2 }
$Engine = (Resolve-Path -LiteralPath $Engine).Path
if (-not (Test-Path -LiteralPath $RealForm)) { Write-Host "WARN: $RealForm not found; start-real.cmd will fail" -ForegroundColor Yellow }

$Ascii = [Text.ASCIIEncoding]::new()
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), $Ascii) }
$script:Fail = 0
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green } else { Write-Host "  [FAIL] $n  $d" -ForegroundColor Red; $script:Fail++ }
}

if (Test-Path -LiteralPath $Root) { [IO.Directory]::Delete($Root, $true) }
$rulesDir = Join-Path $Root 'rules'; $dragDir = Join-Path $Root '_D-RAG'
[void][IO.Directory]::CreateDirectory($rulesDir); [void][IO.Directory]::CreateDirectory($dragDir)
$dproj = Join-Path $Root 'Fix.dproj'; $db = Join-Path $dragDir 'Fix.sqlite'
$pas = Join-Path $Root 'FixUnit.pas'; $dfm = Join-Path $Root 'FixUnit.dfm'

WriteAscii $dproj @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{6D1C6B0E-2F3A-4C1B-9E55-0A1B2C3D4E5F}</ProjectGuid>
        <FrameworkType>VCL</FrameworkType>
        <Base>True</Base>
        <Config Condition="'$(Config)'==''">Debug</Config>
        <Platform Condition="'$(Platform)'==''">Win64</Platform>
        <AppType>Application</AppType>
        <MainSource>Fix.dpr</MainSource>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''">
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Base)'=='true') or '$(Base_Win64)'!=''">
        <Base_Win64>true</Base_Win64>
        <CfgParent>Base</CfgParent>
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base)'!=''">
        <DCC_Namespace>System;Xml;Data;$(DCC_Namespace)</DCC_Namespace>
        <DCC_UnitSearchPath>.\;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base_Win64)'!=''">
        <DCC_Namespace>Winapi;System.Win;Vcl;$(DCC_Namespace)</DCC_Namespace>
    </PropertyGroup>
</Project>
'@
WriteAscii (Join-Path $Root 'Fix.dpr') @'
program Fix;

uses
  Vcl.Forms,
  FixUnit in 'FixUnit.pas' {FixForm};

begin
  Application.Initialize;
  Application.Run;
end.
'@
WriteAscii $pas @'
unit FixUnit;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;

type
  TFixForm = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    Btn1: TButton;
  end;

var
  FixForm: TFixForm;

implementation

{$R *.dfm}

end.
'@
WriteAscii $dfm @'
object FixForm: TFixForm
  Left = 0
  Top = 0
  Caption = 'Fix'
  ClientHeight = 100
  ClientWidth = 200
  object Label1: TLabel
    Left = 8
    Top = 8
    Caption = 'one'
  end
  object Label2: TLabel
    Left = 8
    Top = 32
    Caption = 'two'
  end
  object Btn1: TButton
    Left = 8
    Top = 56
    Caption = 'go'
  end
end
'@
WriteAscii (Join-Path $rulesDir 'Fix.rules') @'
#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls
#link Caption <- Caption
#link Left <- Left
#link Top <- Top
'@
WriteAscii (Join-Path $rulesDir 'Btn.rules') @'
#convert Vcl.StdCtrls.TButton -> cxButtons.TcxButton, cxButtons
#link Caption <- Caption
#link Left <- Left
#link Top <- Top
'@
# The chain book of drive-rule-chains.ps1 ($CHAIN_TEXT): the two #convert lines are 2 and 4.
WriteAscii (Join-Path $Root 'Chain.rules') @'
#depth 2
#convert Bde.DBTables.TTable -> FireDAC.Comp.Client.TFDTable
#link TableName <- TableName
#convert FireDAC.Comp.Client.TFDTable -> FireDAC.Comp.Client.TFDMemTable
#link Name <- Name
'@

# convert-request/1, the shape drive-convert-request.ps1 WriteRequest writes (UTF-8, no BOM: JSON).
$req = Join-Path $Root 'req-selected.json'
$r = [ordered]@{
  schema = 'convert-request/1'; written = (Get-Date -Format s); source = 'owner-sandbox'; ide_pid = 0
  scope = 'selected'; project_file = $dproj; project_db = $db; platform = 'Win64'; rules_folder = $rulesDir
  units = @(@{ pas = $pas; dfm = $dfm; form_class = 'TFixForm'; components = @(@{ name = 'Label1'; type = 'TLabel' }) })
}
[IO.File]::WriteAllText($req, ($r | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

WriteAscii (Join-Path $Root 'start-real.cmd') ("@echo off`r`nrem T-CONV step 1: the real ORM3 AssignGroups unit. Read only: do NOT press Convert or Save.`r`nstart `"`" `"$Editor`" --form `"$RealForm`"`r`n")
WriteAscii (Join-Path $Root 'start-request.cmd') ("@echo off`r`nrem T-CONV steps 2-3: the IDE convert request for Label1 on FixUnit.`r`ncd /d `"%~dp0`"`r`nstart `"`" `"$Editor`" --convert-request `"$req`" --form `"$pas`" --project-db `"$db`"`r`n")
WriteAscii (Join-Path $Root 'start-chain.cmd') ("@echo off`r`nrem T-CONV step 5: press Ctrl+S to see the Rule chains dialog.`r`ncd /d `"%~dp0`"`r`nstart `"`" `"$Editor`" `"$(Join-Path $Root 'Chain.rules')`"`r`n")

Write-Host "Indexing $dproj with $Engine" -ForegroundColor Cyan
Push-Location $Root
try {
  $out = & { $ErrorActionPreference = 'Continue'; $null | & $Engine index --project $dproj --db $db 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $q = & { $ErrorActionPreference = 'Continue'; $null | & $Engine query --name TFixForm --db $db 2>&1 | Out-String }
} finally { Pop-Location }
$summary = (($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)

$dl = [IO.File]::ReadAllLines($dfm); $pl = [IO.File]::ReadAllLines($pas)
Check 'index exit 0, Fix.sqlite exists' (($code -eq 0) -and (Test-Path -LiteralPath $db)) "exit=$code $summary"
Check 'index knows TFixForm' ($q -match 'TFixForm') $q
Check 'FixUnit.dfm line 7 = Label1: TLabel' ($dl[6] -ceq '  object Label1: TLabel') $dl[6]
Check 'FixUnit.dfm line 12 = Label2: TLabel' ($dl[11] -ceq '  object Label2: TLabel') $dl[11]
Check 'FixUnit.pas line 10 = Label1: TLabel;' ($pl[9] -ceq '    Label1: TLabel;') $pl[9]
Check 'FixUnit.pas line 11 = Label2: TLabel;' ($pl[10] -ceq '    Label2: TLabel;') $pl[10]
Check 'three start-*.cmd files' (@(Get-ChildItem -LiteralPath $Root -Filter 'start-*.cmd').Count -eq 3)
Write-Host "sandbox: $Root  index: $summary"
if ($script:Fail -gt 0) { Write-Host "FAILED: $($script:Fail) check(s)" -ForegroundColor Red; exit 1 }
Write-Host 'OK' -ForegroundColor Green
exit 0
