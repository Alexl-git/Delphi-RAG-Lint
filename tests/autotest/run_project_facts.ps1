<#
  run_project_facts.ps1 -- `project-facts`: what a project's BUILD does, read
  from its .dproj (owner ruling 2026-09-16, C9; BACKLOG-TRIAGE-2026-09-28 FIX-6).

  THE QUESTION IT ANSWERS. DataCopy defines EUREKALOG_VER7;EUREKALOG and pulls
  ExceptionLog7 in under an IFDEF, but imports no EurekaLog .targets, so an
  msbuild exe carries the code without the post-processing and dies at start-up.
  Nothing in drag-lint read <Import>, the output paths or DCC_UsePackage, and
  nothing related a define to where it is set. The acceptance case: which units
  reference it, and is it compiled in for this config.

  FIXTURE. One .dproj with every group MSBuild selects from, each carrying a
  distinct define, so a define appearing or not is a direct test of group
  selection:
    Base              BASEDEF          Base_Win64  EUREKALOG, EUREKALOG_VER7
    Base_Win32        W32ONLY          Cfg_1       DBGDEF
    Cfg_2             RELDEF           Cfg_2_Win64 X64REL
    rel.optset (Cfg_2)  OPTREL         dbg.optset (Cfg_1)  OPTDBG
  and the three imports RAD Studio writes (no EurekaLog one).

  CASES
    T1 Win64 Release: BASEDEF/Base, EUREKALOG/Base_Win64, RELDEF/Cfg_2,
       X64REL/Cfg_2_Win64, OPTREL/optset:rel.optset; NOT DBGDEF, W32ONLY, OPTDBG
    T2 Win32 Debug: W32ONLY, DBGDEF, OPTDBG; NOT EUREKALOG, RELDEF, OPTREL
    T3 the post-processor notice fires for Win64 Release and names EurekaLog
    T4 it does NOT fire for Win32 Debug (EurekaLog is not ON there)
    P1 CONTROL the same project importing EurekaLog's .targets: no notice
    T5 output paths from the last group that sets them; packages from Base_Win64
    T6 --json carries the same defines and the notice
    T7 --db: "referenced by" lists the unit whose uses name ExceptionLog7
    T8 a missing --dproj exits 2; a missing --db exits 2

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_project_facts_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

$imports = @'
    <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists('$(BDS)\Bin\CodeGear.Delphi.Targets')"/>
    <Import Project="$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj" Condition="Exists('$(APPDATA)\Embarcadero\$(BDSAPPDATABASEDIR)\$(PRODUCTVERSION)\UserTools.proj')"/>
    <Import Project="rel.optset" Condition="'$(Cfg_2)'!='' And Exists('rel.optset')"/>
    <Import Project="dbg.optset" Condition="'$(Cfg_1)'!='' And Exists('dbg.optset')"/>
'@
function Dproj([string]$Extra) {
@"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup Condition="'`$(Config)'=='Base' or '`$(Base)'!=''">
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base)'!=''">
        <DCC_Define>BASEDEF;`$(DCC_Define)</DCC_Define>
        <DCC_ExeOutput>.\base\exe</DCC_ExeOutput>
        <DCC_DcuOutput>.\base\dcu</DCC_DcuOutput>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base_Win32)'!=''">
        <DCC_Define>W32ONLY;`$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base_Win64)'!=''">
        <DCC_Define>EUREKALOG_VER7;EUREKALOG;`$(DCC_Define)</DCC_Define>
        <DCC_UsePackage>rtl;vcl;`$(DCC_UsePackage)</DCC_UsePackage>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_1)'!=''">
        <DCC_Define>DBGDEF;`$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_2)'!=''">
        <DCC_Define>RELDEF;`$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_2_Win64)'!=''">
        <DCC_Define>X64REL;`$(DCC_Define)</DCC_Define>
        <DCC_ExeOutput>.\x64rel\exe</DCC_ExeOutput>
    </PropertyGroup>
$imports$Extra
</Project>
"@
}
W (Join-Path $src 'App.dproj') (Dproj '')
W (Join-Path $src 'Eureka.dproj') (Dproj "    <Import Project=`"`$(APPDATA)\Neos Eureka S.r.l\EurekaLog 7\EurekaLog7.targets`"/>`n")
W (Join-Path $src 'rel.optset') "<Project><PropertyGroup><DCC_Define>OPTREL;`$(DCC_Define)</DCC_Define></PropertyGroup></Project>"
W (Join-Path $src 'dbg.optset') "<Project><PropertyGroup><DCC_Define>OPTDBG;`$(DCC_Define)</DCC_Define></PropertyGroup></Project>"
W (Join-Path $src 'uLog.pas') @'
unit uLog;

interface

procedure Go;

implementation

uses ExceptionLog7;

procedure Go;
begin
end;

end.
'@
W (Join-Path $src 'uPlain.pas') @'
unit uPlain;

interface

procedure Stop;

implementation

procedure Stop;
begin
end;

end.
'@
$dpr = Join-Path $src 'App.dpr'
W $dpr @'
program App;
uses
  uLog in 'uLog.pas',
  uPlain in 'uPlain.pas';
begin
end.
'@

function Facts([string]$Dproj, [string]$Plat, [string]$Cfg, [string[]]$Extra = @()) {
  $o = & $exePath project-facts --dproj $Dproj --platform $Plat --config $Cfg @Extra 2>$null
  return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($o -join "`n") }
}
function DefineLine([string]$Text, [string]$Name) {
  foreach ($l in ($Text -split "`n")) { if ($l -match ('^\s+' + [regex]::Escape($Name) + '\s+(.+)$')) { return $Matches[1].Trim() } }
  return $null
}
$app = Join-Path $src 'App.dproj'

# ---- T1 Win64 Release --------------------------------------------------------
$r = Facts $app 'win64' 'Release'
Check 'V Win64 Release report exits 0' ($r.Exit -eq 0) $r.Text
$exp = @{ BASEDEF = 'Base'; EUREKALOG = 'Base_Win64'; RELDEF = 'Cfg_2'; X64REL = 'Cfg_2_Win64'; OPTREL = 'optset:rel.optset' }
foreach ($k in $exp.Keys) {
  $src1 = DefineLine $r.Text $k
  Check "T1 $k is ON, set by $($exp[$k])" ($src1 -eq $exp[$k]) "got '$src1'"
}
foreach ($k in 'DBGDEF', 'W32ONLY', 'OPTDBG') { Check "T1 $k is NOT on for Win64 Release" ($null -eq (DefineLine $r.Text $k)) '' }
Check 'T1 a builtin is attributed to builtin (win64)' ((DefineLine $r.Text 'win64') -eq 'builtin') ''

# ---- T3 / T5 on the same report ----------------------------------------------
Check 'T3 the notice fires and names EurekaLog' ($r.Text -match '!\s+EurekaLog is compiled in') $r.Text
Check 'T5 exe output is the LAST group that sets it (Cfg_2_Win64)' ($r.Text -match 'exe output : \.\\x64rel\\exe') ''
Check 'T5 dcu output falls back to Base' ($r.Text -match 'dcu output : \.\\base\\dcu') ''
Check 'T5 packages come from Base_Win64 (rtl;vcl)' ($r.Text -match 'packages\s+: 2 -- rtl;vcl') ''
Check 'T5 all four imports are listed' ($r.Text -match 'imports \(4\)') ''

# ---- T2 / T4 Win32 Debug -----------------------------------------------------
$r2 = Facts $app 'win32' 'Debug'
foreach ($k in 'W32ONLY', 'DBGDEF', 'OPTDBG') { Check "T2 $k is ON for Win32 Debug" ($null -ne (DefineLine $r2.Text $k)) '' }
foreach ($k in 'EUREKALOG', 'RELDEF', 'OPTREL') { Check "T2 $k is NOT on for Win32 Debug" ($null -eq (DefineLine $r2.Text $k)) '' }
Check 'T4 no post-processor notice where EurekaLog is not ON' ($r2.Text -match 'notices\s+: none') $r2.Text

# ---- P1 control: the targets ARE imported ------------------------------------
$r3 = Facts (Join-Path $src 'Eureka.dproj') 'win64' 'Release'
Check 'P1 CONTROL EUREKALOG is ON in the control project too' ($null -ne (DefineLine $r3.Text 'EUREKALOG')) ''
Check 'P1 CONTROL with EurekaLog7.targets imported there is no notice' ($r3.Text -match 'notices\s+: none') $r3.Text

# ---- T6 --json ---------------------------------------------------------------
$j = (Facts $app 'win64' 'Release' @('--json')).Text | ConvertFrom-Json
Check 'T6 --json carries EUREKALOG with source Base_Win64' `
      (@($j.defines | Where-Object { $_.name -eq 'EUREKALOG' -and ($_.sources -contains 'Base_Win64') }).Count -eq 1) ''
Check 'T6 --json carries the notice' (@($j.notices | Where-Object { $_ -match 'EurekaLog' }).Count -eq 1) ''
Check 'T6 --json imports have kinds' (@($j.imports | Where-Object { $_.kind -eq 'optset' }).Count -eq 2) ''

# ---- T7 --db referenced by ---------------------------------------------------
$db = Join-Path $WorkDir 'App.sqlite'
& $exePath index --project $dpr --db $db 2>&1 | Out-Null
$r4 = Facts $app 'win64' 'Release' @('--db', $db)
Check 'T7 --db lists uLog.pas as referencing ExceptionLog7' ($r4.Text -match 'uLog\.pas\s+\(ExceptionLog7\)') $r4.Text
Check 'T7b and not uPlain.pas' ($r4.Text -notmatch 'uPlain\.pas') ''
$j4 = (Facts $app 'win64' 'Release' @('--db', $db, '--json')).Text | ConvertFrom-Json
Check 'T7c --json referenced_by.EurekaLog has one entry' (@($j4.referenced_by.EurekaLog).Count -eq 1) ''

# ---- T8 exit codes -----------------------------------------------------------
$r5 = Facts (Join-Path $src 'Missing.dproj') 'win64' 'Release'
Check "T8 a missing --dproj exits 2 (got $($r5.Exit))" ($r5.Exit -eq 2) ''
$r6 = Facts $app 'win64' 'Release' @('--db', (Join-Path $WorkDir 'none.sqlite'))
Check "T8 a missing --db exits 2 (got $($r6.Exit))" ($r6.Exit -eq 2) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_project_facts_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
