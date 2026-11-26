#Requires -Version 7
<#
  run_v1541_CONSOLE.ps1 -- 1.54.1 lane CONSOLE: writeln-in-gui-app asks the PROGRAM, not only the unit.

  The rule read {$APPTYPE CONSOLE} from the linted file alone, so a unit that uses Vcl.Forms in a console
  program was reported "this program has no console". Now the program of the project index (or of --project)
  decides: {$APPTYPE} in its .dpr, else DCC_ConsoleTarget of its .dproj (dcc -CC); AppType in the .dproj never
  reaches the compiler (measured: PE subsystem 2 without -CC / $APPTYPE, 3 with either, GUI directive wins).

  Every case is one project folder: UUse.pas (uses Vcl.Forms, one Writeln) + App.dpr + App.dproj, indexed with
  `index --project`. "silent" cases are paired with "fires" cases that only differ in the program.

  With the pre-lane engine every "silent" check FAILS (RED); the "fires" controls pass.

  Usage: pwsh -File tests\autotest\run_v1541_CONSOLE.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v1541_console_$PID"
)
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe  = (Resolve-Path $Exe).Path
$Rule = 'writeln-in-gui-app'

$script:Fail = 0
$script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function Put([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

# The program text, {0} = the lines between the header and the uses clause.
function Dpr([string]$Head, [string]$Kind = 'program', [string]$Body = '  RunAll;') {
  "$Kind App;`n$Head`nuses`n  UUse in 'UUse.pas';`nbegin`n$Body`nend.`n"
}
# The .dproj text: AppType plus DCC_ConsoleTarget per platform group.
function Dproj([string]$AppType, [string]$Win32 = '', [string]$Win64 = '') {
  $c32 = if ($Win32) { "<DCC_ConsoleTarget>$Win32</DCC_ConsoleTarget>" } else { '' }
  $c64 = if ($Win64) { "<DCC_ConsoleTarget>$Win64</DCC_ConsoleTarget>" } else { '' }
  @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{5E1B6C1B-1541-4C0E-9A55-0123456789AB}</ProjectGuid>
        <MainSource>App.dpr</MainSource>
        <Config Condition="'`$(Config)'==''">Debug</Config>
        <Platform Condition="'`$(Platform)'==''">Win64</Platform>
        <TargetedPlatforms>3</TargetedPlatforms>
        <AppType>$AppType</AppType>
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
    <PropertyGroup Condition="'`$(Base_Win32)'!=''">
        <VerInfo_Locale>1033</VerInfo_Locale>
        $c32
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base_Win64)'!=''">
        <VerInfo_Locale>1033</VerInfo_Locale>
        $c64
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="App.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
        <DCCReference Include="UUse.pas"/>
    </ItemGroup>
</Project>
"@
}
$UnitText = @'
unit UUse;

interface

procedure RunAll;

implementation

uses
  System.SysUtils, Vcl.Forms;

procedure RunAll;
begin
  Application.Title:= 'x';
  Writeln('title=', Application.Title);
end;

end.
'@

# Builds one project folder and its index; returns the db path.
function New-Case([string]$Name, [string]$DprText, [string]$DprojText) {
  $d = Join-Path $WorkDir $Name
  [void](New-Item -ItemType Directory -Force -Path $d)
  Put (Join-Path $d 'UUse.pas') $UnitText
  Put (Join-Path $d 'App.dpr') $DprText
  Put (Join-Path $d 'App.dproj') $DprojText
  $db = Join-Path $d 'App.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $d 'App.dproj') --db $db *> (Join-Path $d 'index.log') }
  if (-not (Test-Path $db)) { throw "no index for case $Name" }
  return $db
}
# lint / lint-all --json print a bare array; the line field is start_line.
function Hits([string]$Json) {
  if ($Json.Trim() -eq '') { return 0 }
  return @($Json | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.rule -eq $Rule }).Count
}
function LintHits([string]$File, [string[]]$Extra) {
  return Hits ((& { $ErrorActionPreference = 'Continue'; & $Exe lint $File --json @Extra 2>$null }) -join "`n")
}
function LintAllHits([string]$Db, [string[]]$Extra = @()) {
  return Hits ((& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --json @Extra 2>$null }) -join "`n")
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
# The IDE path: `lsp --db --full-rules` publishes the rules on didSave.
function LspCodes([string]$File, [string]$Db, [string]$Tag) {
  $uri = 'file:///' + ($File -replace '\\', '/')
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didSave'; params=@{ textDocument=@{ uri=$uri } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $in = Join-Path $WorkDir "$Tag.in"; $so = Join-Path $WorkDir "$Tag.out"; $se = Join-Path $WorkDir "$Tag.err"
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db, '--full-rules') -WorkingDirectory $WorkDir `
    -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $out = [IO.File]::ReadAllText($so)
  return [pscustomobject]@{
    Codes = @([regex]::Matches($out, '"code":"([a-z0-9\-]+)"') | ForEach-Object { $_.Groups[1].Value })
    Cost  = ([IO.File]::ReadAllText($se) -match 'full-rules .+ \d+ ms \d+ findings')
  }
}

[void](New-Item -ItemType Directory -Force -Path $WorkDir)
Push-Location $WorkDir
try {
  $gui = Dproj 'Application'
  $cases = @(
    # name, program text, .dproj text, finding expected, what it proves
    @('g0',  (Dpr ''),                                                        $gui, $true,  'GUI program (positive control)'),
    @('c1',  (Dpr '{$APPTYPE CONSOLE}'),                                      $gui, $false, '$APPTYPE CONSOLE in the .dpr'),
    @('c2',  (Dpr '(*$AppType Console*)'),                                    $gui, $false, '$APPTYPE in the (*$ form'),
    @('c3',  (Dpr '{$IFDEF X}{$APPTYPE CONSOLE}{$ENDIF}'),                    $gui, $false, 'conditional $APPTYPE CONSOLE'),
    @('c4',  (Dpr '{$APPTYPE CONSOLE}{$IFDEF X}{$APPTYPE GUI}{$ENDIF}'),      $gui, $false, 'conditional $APPTYPE GUI does not override'),
    @('c5',  (Dpr '' 'program' '  AllocConsole; RunAll;'),                    $gui, $false, 'AllocConsole in the .dpr'),
    @('c6',  (Dpr ''), (Dproj 'Console' '' 'true'),                                 $false, 'DCC_ConsoleTarget of the platform'),
    @('g1',  (Dpr '// {$APPTYPE CONSOLE}'),                                   $gui, $true,  '$APPTYPE in a comment'),
    @('g2',  (Dpr '' 'program' "  Application.Title:= '{`$APPTYPE CONSOLE}';"), $gui, $true, '$APPTYPE in a string'),
    @('g3',  (Dpr '{$APPTYPE CONSOLE}{$APPTYPE GUI}'),                        $gui, $true,  'the last unconditional $APPTYPE wins'),
    @('g4',  (Dpr '{$APPTYPE GUI}'), (Dproj 'Console' 'true' 'true'),               $true,  '$APPTYPE GUI overrides DCC_ConsoleTarget'),
    @('g5',  (Dpr ''), (Dproj 'Console'),                                           $true,  'AppType Console alone (never reaches dcc)'),
    @('g6',  (Dpr ''), (Dproj 'Application' 'true' ''),                             $true,  'DCC_ConsoleTarget of the other platform'),
    @('g7',  (Dpr ''), (Dproj 'Application' 'false' 'false'),                       $true,  'DCC_ConsoleTarget false'),
    @('l1',  (Dpr '{$APPTYPE CONSOLE}' 'library' ''),                         $gui, $true,  'a library: the host decides')
  )
  foreach ($c in $cases) {
    $db = New-Case $c[0] $c[1] $c[2]
    $n1 = LintHits (Join-Path $WorkDir "$($c[0])\UUse.pas") @('--db', $db)
    $n2 = LintAllHits $db
    $want = if ($c[3]) { 1 } else { 0 }
    Check "$($c[0]) lint: $($c[4]) -> $want"     ($n1 -eq $want) "got $n1"
    Check "$($c[0]) lint-all: $($c[4]) -> $want" ($n2 -eq $want) "got $n2"
  }
  $dbC = Join-Path $WorkDir 'c1\App.sqlite'
  $dbG = Join-Path $WorkDir 'g0\App.sqlite'

  # --rule
  Check 'r1 lint-all --rule: console silent, GUI fires' ((LintAllHits $dbC @('--rule', $Rule)) -eq 0 -and (LintAllHits $dbG @('--rule', $Rule)) -eq 1)

  # another project's console .dpr in the GUI project's folder does not speak for it
  Put (Join-Path $WorkDir 'g0\Tool.dpr') "program Tool;`n{`$APPTYPE CONSOLE}`nbegin`nend.`n"
  Check 'n1 GUI project beside a console .dpr: lint fires'     ((LintHits (Join-Path $WorkDir 'g0\UUse.pas') @('--db', $dbG)) -eq 1)
  Check 'n2 GUI project beside a console .dpr: lint-all fires' ((LintAllHits $dbG) -eq 1)

  # the LSP path (the IDE)
  $lg = LspCodes (Join-Path $WorkDir 'g0\UUse.pas') $dbG 'lsp-g0'
  $lc = LspCodes (Join-Path $WorkDir 'c1\UUse.pas') $dbC 'lsp-c1'
  Check 'p1 LSP: GUI program fires (positive control)' ($lg.Codes -contains $Rule) ($lg.Codes -join ',')
  Check 'p2 LSP: console program is silent, the full rule set ran' ($lc.Cost -and ($lc.Codes -notcontains $Rule)) ($lc.Codes -join ',')

  # no program known: the file's own text decides, as before
  $loose = Join-Path $WorkDir 'loose'
  [void](New-Item -ItemType Directory -Force -Path $loose)
  Put (Join-Path $loose 'UUse.pas') $UnitText
  Check 'u1 loose file, --db of a console project it is not in: fires' ((LintHits (Join-Path $loose 'UUse.pas') @('--db', $dbC)) -eq 1)
  $dbF = Join-Path $WorkDir 'folder.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $WorkDir 'c1') --db $dbF *> (Join-Path $WorkDir 'folder.log') }
  Check 'u2 folder index (names no program): fires' ((LintHits (Join-Path $WorkDir 'c1\UUse.pas') @('--db', $dbF)) -eq 1)

  # --project names the program
  $pc = Join-Path $WorkDir 'c1\App.dproj'
  $pg = Join-Path $WorkDir 'g0\App.dproj'
  Check 'j1 lint --project <console .dproj>: silent' ((LintHits (Join-Path $WorkDir 'c1\UUse.pas') @('--db', $dbF, '--project', $pc)) -eq 0)
  Check 'j2 lint --project <GUI .dproj>: fires'      ((LintHits (Join-Path $WorkDir 'g0\UUse.pas') @('--db', $dbG, '--project', $pg)) -eq 1)

  # the program text is read when linted, not when indexed
  Put (Join-Path $WorkDir 'c1\App.dpr') (Dpr '')
  Check 'e1 the .dpr loses $APPTYPE CONSOLE (no reindex): lint fires' ((LintHits (Join-Path $WorkDir 'c1\UUse.pas') @('--db', $dbC)) -eq 1)
}
finally { Pop-Location }

Write-Host ("run_v1541_CONSOLE: {0} pass, {1} failure(s)" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
