# Guard: ifdef-undefined-symbol -- an {$IFDEF X} / {$IFNDEF X} / defined(X)
# whose X no build of the project ever defines.
#
# THE RULE. X is "defined somewhere" when it is (a) a compiler-predefined
# conditional for ANY platform (VER<nnn>, CPU*, MSWINDOWS, WIN32, ...), (b) in
# the DCC_Define of ANY PropertyGroup of the project's .dproj -- every config x
# every platform, the UNION, not one resolved profile -- (c) a {$DEFINE X}
# anywhere in the unit or the {$I} includes it pulls in, or (d) in the user's
# "ifdef_allow" config list. Anything else is a branch no build compiles --
# usually a typo (EUREKALGO for EUREKALOG).
#
# WHY THE NEGATIVE CONTROLS ARE THE POINT. A rule that fires on every
# unrecognised symbol is trivial; the cost is in the false positives. Each
# negative control below is one of the ways a symbol is legitimately defined,
# and each must stay silent:
#   ONLYBASE64   -- only in Base_Win64 (the group ProfileFromDproj missed until
#                   2026-09-23; the Micronite2027 EUREKALOG shape)
#   ONLYCFG2W32  -- only in Cfg_2_Win32, tested in a DIFFERENT case
#   LOCALDEF     -- a {$DEFINE} earlier in the unit
#   LATERDEF     -- a {$DEFINE} AFTER the test (the include-guard idiom)
#   INCDEF       -- a {$DEFINE} inside a {$I} include
#   DEBUG        -- only in Cfg_1: DEBUG is NOT compiler-predefined
#   built-ins    -- WIN32 WIN64 VER370 VER150 MSWINDOWS CPUX64 CONSOLE
#   THIRDPARTY_VER7 -- allowed through the ifdef_allow config parameter
#   commented    -- an {$IFDEF} inside a // comment is not a directive
#
# AND THE PROJECT GATE. With no project the union in (b) is unknown, so every
# project define would read as undefined. A file linted with no project must
# report NOTHING -- asserted with the same unit that yields 4 findings above.
#
# Usage: pwsh -File tests/autotest/run_ifdef_undefined_symbol.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-ifdef-undefined"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$NoProjDir = Join-Path $WorkDir 'noproj'
New-Item -ItemType Directory $NoProjDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Line numbers below are load-bearing: the positive assertions pin them.
$unitBody = @'
unit U;

interface

implementation

{$DEFINE LOCALDEF}
{$I defs.inc}
{$I+}

{$IFDEF EUREKALGO}
{$ENDIF}
{$IF defined(NOPE)}
{$IFEND}
{$IFNDEF ONLYBASE64}
{$ENDIF}
{$IFDEF OnlyCfg2W32}
{$ENDIF}
{$IFDEF LOCALDEF}
{$ENDIF}
{$IFDEF LATERDEF}
{$ENDIF}
{$IFDEF INCDEF}
{$ENDIF}
{$IFDEF DEBUG}
{$ENDIF}
{$IFDEF WIN32} {$ENDIF} {$IFDEF WIN64} {$ENDIF} {$IFDEF VER370} {$ENDIF}
{$IFDEF VER150} {$ENDIF} {$IFDEF MSWINDOWS} {$ENDIF} {$IFDEF CPUX64} {$ENDIF}
{$IFDEF CONSOLE} {$ENDIF}
{$IFDEF THIRDPARTY_VER7}
{$ENDIF}
{$IF defined(BASEDEF) and not Defined(TYPOO)}
{$ELSEIF defined(ELSEIFTYPO)}
{$IFEND}
// {$IFDEF INCOMMENT} is not a directive
{$DEFINE LATERDEF}

end.
'@
Write-Ascii (Join-Path $WorkDir 'U.pas') $unitBody
Write-Ascii (Join-Path $NoProjDir 'U.pas') $unitBody
Write-Ascii (Join-Path $WorkDir 'defs.inc') "{`$DEFINE INCDEF}`n"
Write-Ascii (Join-Path $NoProjDir 'defs.inc') "{`$DEFINE INCDEF}`n"

Write-Ascii (Join-Path $WorkDir 'P.dpr') @'
program P;

uses
  U in 'U.pas';

begin
{$IFDEF EUREKALOG}
{$ENDIF}
end.
'@

# Real RAD Studio condition shapes: Base, Base_<Platform>, Cfg_N, Cfg_N_<Platform>.
Write-Ascii (Join-Path $WorkDir 'P.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>P.dpr</MainSource>
        <Config Condition="'$(Config)'==''">Debug</Config>
        <Platform Condition="'$(Platform)'==''">Win32</Platform>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''">
        <Base>true</Base>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base)'!=''">
        <DCC_Define>BASEDEF;$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base_Win32)'!=''">
        <DCC_Define>EUREKALOG;$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base_Win64)'!=''">
        <DCC_Define>ONLYBASE64;EUREKALOG;$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Cfg_1)'!=''">
        <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Cfg_2)'!=''">
        <DCC_Define>RELEASE;$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Cfg_2_Win32)'!=''">
        <DCC_Define>ONLYCFG2W32;$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="U.pas"/>
    </ItemGroup>
</Project>
'@

Write-Ascii (Join-Path $WorkDir 'drag-lint-lint.json') @'
{ "ifdef_allow": ["ThirdParty_Ver7"] }
'@

$rule = 'ifdef-undefined-symbol'
function Get-Findings([string[]]$LintArgs) {
  $raw = (& $Exe @LintArgs --json 2>$null) -join "`n"
  $start = $raw.IndexOf('[')
  if ($start -lt 0) { return ,@() }
  $arr = $raw.Substring($start) | ConvertFrom-Json
  return ,@($arr | Where-Object { $_.rule -eq $rule })
}

$unit = Join-Path $WorkDir 'U.pas'
$proj = Join-Path $WorkDir 'P.dproj'

Write-Host ''
Write-Host "lint <file> --project -- the rule fires on the four typos and nothing else" -ForegroundColor Cyan
$f = Get-Findings @('lint', $unit, '--project', $proj, '--rule', $rule)
foreach ($x in $f) { Write-Host ("    {0}:{1} {2}" -f (Split-Path $x.file_path -Leaf), $x.start_line, $x.message) -ForegroundColor DarkGray }
$msgs = ($f | ForEach-Object { "$($_.start_line)|$($_.message)" }) -join "`n"
Check 'POSITIVE: {$IFDEF EUREKALGO} fires on line 11'  ($msgs -match '(?m)^11\|.*EUREKALGO')  $msgs
Check 'POSITIVE: the typo message suggests EUREKALOG (edit distance 2)' ($msgs -match 'EUREKALGO[^\n]*EUREKALOG') $msgs
Check 'POSITIVE: {$IF defined(NOPE)} fires on line 13' ($msgs -match '(?m)^13\|.*NOPE')       $msgs
Check 'POSITIVE: not Defined(TYPOO) fires (mixed-case defined)' ($msgs -match '(?m)^32\|.*TYPOO') $msgs
Check 'POSITIVE: {$ELSEIF defined(ELSEIFTYPO)} fires on line 33' ($msgs -match '(?m)^33\|.*ELSEIFTYPO') $msgs
Check 'NEGATIVE: exactly 4 findings -- every legitimate definition is silent' ($f.Count -eq 4) "count=$($f.Count)"
foreach ($neg in @('ONLYBASE64','OnlyCfg2W32','LOCALDEF','LATERDEF','INCDEF','DEBUG','WIN32','WIN64',
                   'VER370','VER150','MSWINDOWS','CPUX64','CONSOLE','THIRDPARTY_VER7','BASEDEF','INCOMMENT')) {
  Check ("NEGATIVE: $neg is not reported") (-not ($msgs -match "\b$neg\b")) ''
}

Write-Host ''
Write-Host 'POSITIVE CONTROLS for two negatives -- the allow-list and DEBUG are live, not blanket' -ForegroundColor Cyan
# Same unit, a project whose .dproj has NO Cfg_1 DEBUG and NO drag-lint-lint.json.
# If THIRDPARTY_VER7 or DEBUG were silenced by something other than the config
# and the .dproj, the two negatives above would pass for the wrong reason.
# A SIBLING of WorkDir, not a child: config discovery walks up from the file,
# and would find WorkDir's drag-lint-lint.json from inside it.
$NoAllowDir = "$WorkDir-noallow"
if (Test-Path $NoAllowDir) { Remove-Item -Recurse -Force $NoAllowDir }
New-Item -ItemType Directory $NoAllowDir | Out-Null
Write-Ascii (Join-Path $NoAllowDir 'U.pas') $unitBody
Write-Ascii (Join-Path $NoAllowDir 'defs.inc') "{`$DEFINE INCDEF}`n"
$dprojNoDebug = ([IO.File]::ReadAllText($proj)) -replace '<DCC_Define>DEBUG;', '<DCC_Define>'
Write-Ascii (Join-Path $NoAllowDir 'P.dproj') $dprojNoDebug
$na = Get-Findings @('lint', (Join-Path $NoAllowDir 'U.pas'), '--project', (Join-Path $NoAllowDir 'P.dproj'), '--rule', $rule)
$naMsgs = ($na | ForEach-Object { "$($_.start_line)|$($_.message)" }) -join "`n"
Check 'CONTROL: without ifdef_allow, THIRDPARTY_VER7 fires' ($naMsgs -match "'THIRDPARTY_VER7'") "count=$($na.Count)"
Check 'CONTROL: without DEBUG in the .dproj, DEBUG fires (it is not compiler-predefined)' ($naMsgs -match "'DEBUG'") "count=$($na.Count)"
Check 'CONTROL: exactly 6 findings (the 4 typos + those two)' ($na.Count -eq 6) "count=$($na.Count)"

Write-Host ''
Write-Host 'THE PROJECT GATE -- the same unit, linted with NO project, reports nothing' -ForegroundColor Cyan
$np = Get-Findings @('lint', (Join-Path $NoProjDir 'U.pas'), '--rule', $rule)
Check 'NO PROJECT: 0 findings (EUREKALGO would fire if the gate were missing)' ($np.Count -eq 0) "count=$($np.Count)"

Write-Host ''
Write-Host 'lint-all -- the project run finds the same 4, and the .dpr EUREKALOG is silent' -ForegroundColor Cyan
$db = Join-Path $WorkDir 'p.sqlite'
& $Exe index --project $proj --db $db 2>&1 | Out-Null
# --enable as well as --rule: the rule ships OFF, and on lint-all only --enable
# (or the config's "enabled") lifts a default-off id.
$la = Get-Findings @('lint-all', '--db', $db, '--project', $proj, '--rule', $rule, '--enable', $rule)
foreach ($x in $la) { Write-Host ("    {0}:{1} {2}" -f (Split-Path $x.file_path -Leaf), $x.start_line, $x.message) -ForegroundColor DarkGray }
Check 'lint-all: exactly 4 findings, all in U.pas' (($la.Count -eq 4) -and (@($la | Where-Object { (Split-Path $_.file_path -Leaf) -ne 'U.pas' }).Count -eq 0)) "count=$($la.Count)"
$pd = Get-Findings @('lint', (Join-Path $WorkDir 'P.dpr'), '--project', $proj, '--rule', $rule)
Check 'NEGATIVE: {$IFDEF EUREKALOG} in the .dpr (Base_Win32/Base_Win64 only) is silent' ($pd.Count -eq 0) "count=$($pd.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
