# Guard: platform-divergent-define -- a conditional symbol that one enabled
# platform's build defines and another's does not, for the same config, AND
# that the code actually tests with {$IFDEF} / {$IFNDEF} / defined().
#
# THE RULE (spec docs\superpowers\specs\2026-10-25-three-lint-rules-design.md,
# rule 1; owner rulings 2026-10-25). For each config (Base + every declared
# config) the EFFECTIVE DCC_Define set per enabled Windows platform is computed
# by DprojEffectiveDefines (Base, Base_<P>, the config chain, each with its
# _<P> group; a value without $(DCC_Define) REPLACES). A symbol in one
# platform's set and not the other's is divergent; it is reported ONCE, at its
# first test site, unless the testing unit $DEFINEs / $UNDEFs it itself, it is
# compiler-predefined, or it is on the platform_divergent_allow list.
#
# POSITIVE: RED (Base_Win32-only EUREKALOG), REPLACE (Cfg_1_Win64 drops a Base
# define), CUSTOM (Cfg_3 'Profiling' divergence), lint-all over an index, and
# the rule running with no --rule (default ON).
# NEGATIVE: (a) both platform groups, (b) moved to Base, (c) never tested -- also
# the guard's own positive control: the RED project minus its IFDEF, (d) the
# unit DEFINEs it, (d2) the unit UNDEFs it, (e) allow-listed, (f) no project,
# (g) a compiler built-in (CPUX86) in one platform group.
#
# Usage: pwsh -File tests/autotest/run_platform_divergent_define.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-platform-divergent-$PID"
)
try {
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# A RAD Studio .dproj: selector groups for Base, both platforms, Debug (Cfg_1),
# Release (Cfg_2) and Profiling (Cfg_3, child of Release), Win32 + Win64
# enabled. $Defs maps a group alias to its DCC_Define value.
function New-Dproj([hashtable]$Defs) {
  $sel = @'
    <PropertyGroup Condition="'$(Config)'=='Base' or '$(Base)'!=''"><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="('$(Platform)'=='Win32' and '$(Base)'=='true') or '$(Base_Win32)'!=''"><Base_Win32>true</Base_Win32><CfgParent>Base</CfgParent><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="('$(Platform)'=='Win64' and '$(Base)'=='true') or '$(Base_Win64)'!=''"><Base_Win64>true</Base_Win64><CfgParent>Base</CfgParent><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Debug' or '$(Cfg_1)'!=''"><Cfg_1>true</Cfg_1><CfgParent>Base</CfgParent><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Release' or '$(Cfg_2)'!=''"><Cfg_2>true</Cfg_2><CfgParent>Base</CfgParent><Base>true</Base></PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Profiling' or '$(Cfg_3)'!=''"><Cfg_3>true</Cfg_3><CfgParent>Cfg_2</CfgParent><Cfg_2>true</Cfg_2><Base>true</Base></PropertyGroup>
'@
  $groups = ''
  foreach ($alias in @('Base','Base_Win32','Base_Win64','Cfg_1','Cfg_1_Win32','Cfg_1_Win64','Cfg_2','Cfg_2_Win32','Cfg_2_Win64','Cfg_3','Cfg_3_Win32','Cfg_3_Win64')) {
    if ($Defs.ContainsKey($alias)) {
      $groups += "    <PropertyGroup Condition=`"'`$($alias)'!=''`"><DCC_Define>$($Defs[$alias])</DCC_Define></PropertyGroup>`n"
    }
  }
  return @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup><MainSource>P.dpr</MainSource></PropertyGroup>
$sel$groups    <ItemGroup><DCCReference Include="U.pas"/></ItemGroup>
    <ProjectExtensions><BorlandProject><Platforms>
        <Platform value="Win32">True</Platform>
        <Platform value="Win64">True</Platform>
    </Platforms></BorlandProject></ProjectExtensions>
</Project>
"@
}

# Line numbers are load-bearing: the IFDEF of $Sym sits on line 7.
function New-Unit([string]$Sym, [string]$Extra='') {
  return @"
unit U;

interface

implementation
$Extra
{`$IFDEF $Sym}
{`$ENDIF}
{`$IFDEF WIN32} {`$ENDIF} {`$IFDEF CPUX86} {`$ENDIF} {`$IF defined(BASEDEF)} {`$IFEND}

end.
"@
}

# One project folder per case: <WorkDir>\<name>\{P.dproj,P.dpr,U.pas}.
function New-Case([string]$Name, [hashtable]$Defs, [string]$Unit, [string]$Config='') {
  $d = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $d | Out-Null
  Write-Ascii (Join-Path $d 'P.dproj') (New-Dproj $Defs)
  Write-Ascii (Join-Path $d 'P.dpr') "program P;`n`nuses`n  U in 'U.pas';`n`nbegin`nend.`n"
  Write-Ascii (Join-Path $d 'U.pas') $Unit
  if ($Config) { Write-Ascii (Join-Path $d 'drag-lint-lint.json') $Config }
  return $d
}

$rule = 'platform-divergent-define'
function Get-Findings([string[]]$LintArgs) {
  $raw = (& $Exe @LintArgs --json 2>$null) -join "`n"
  $start = $raw.IndexOf('[')
  if ($start -lt 0) { return ,@() }
  $arr = $raw.Substring($start) | ConvertFrom-Json
  return ,@($arr | Where-Object { $_.rule -eq $rule })
}
function Lint-Case([string]$Dir, [switch]$NoRule, [switch]$NoProject) {
  $a = @('lint', (Join-Path $Dir 'U.pas'))
  if (-not $NoProject) { $a += @('--project', (Join-Path $Dir 'P.dproj')) }
  if (-not $NoRule)    { $a += @('--rule', $rule) }
  $f = Get-Findings $a
  foreach ($x in $f) { Write-Host ("    {0}:{1} {2}" -f (Split-Path $x.file_path -Leaf), $x.start_line, $x.message) -ForegroundColor DarkGray }
  return ,$f
}

$base = 'BASEDEF;$(DCC_Define)'

Write-Host ''
# positive-control: platform-divergent-define
Write-Host 'POSITIVE -- EUREKALOG only in Base_Win32, tested on line 7' -ForegroundColor Cyan
$red = New-Case 'red' @{ Base=$base; Base_Win32='EUREKALOG;$(DCC_Define)'; Cfg_1='DEBUG;$(DCC_Define)' } (New-Unit 'EUREKALOG')
$f = Lint-Case $red
Check 'RED: exactly 1 finding (one per symbol, not one per config)' ($f.Count -eq 1) "count=$($f.Count)"
Check 'RED: anchored at the IFDEF, line 7' ($f.Count -ge 1 -and $f[0].start_line -eq 7) ''
Check 'RED: message names the symbol, Base_Win32 and Win64' ($f.Count -ge 1 -and $f[0].message -match 'EUREKALOG' -and $f[0].message -match 'Base_Win32' -and $f[0].message -match 'Win64') ''
Check 'RED: severity warning' ($f.Count -ge 1 -and $f[0].severity -eq 'warning') ''
$fd = Lint-Case $red -NoRule
Check 'DEFAULT ON: the rule runs with no --rule' ($fd.Count -eq 1) "count=$($fd.Count)"

Write-Host ''
Write-Host 'POSITIVE -- REPLACE: Cfg_1_Win64 without $(DCC_Define) drops SHARED on Debug|Win64' -ForegroundColor Cyan
$rep = New-Case 'replace' @{ Base='SHARED;BASEDEF;$(DCC_Define)'; Cfg_1='DEBUG;$(DCC_Define)'; Cfg_1_Win64='DEBUG;BASEDEF' } (New-Unit 'SHARED')
$f = Lint-Case $rep
Check 'REPLACE: exactly 1 finding for SHARED, naming Debug' ($f.Count -eq 1 -and $f[0].message -match 'SHARED' -and $f[0].message -match 'Debug') "count=$($f.Count)"

Write-Host ''
Write-Host 'POSITIVE -- CUSTOM config Profiling (Cfg_3) diverges on Win32 only' -ForegroundColor Cyan
$cus = New-Case 'custom' @{ Base=$base; Cfg_3_Win32='PROF32;$(DCC_Define)' } (New-Unit 'PROF32')
$f = Lint-Case $cus
Check 'CUSTOM: exactly 1 finding for PROF32, naming Profiling and Cfg_3_Win32' ($f.Count -eq 1 -and $f[0].message -match 'Profiling' -and $f[0].message -match 'Cfg_3_Win32') "count=$($f.Count)"

Write-Host ''
Write-Host 'NEGATIVE CONTROLS -- each must stay silent' -ForegroundColor Cyan
$n = New-Case 'both'    @{ Base=$base; Base_Win32='EUREKALOG;$(DCC_Define)'; Base_Win64='EUREKALOG;$(DCC_Define)' } (New-Unit 'EUREKALOG')
$f = Lint-Case $n; Check '(a) same define in both platform groups: 0' ($f.Count -eq 0) "count=$($f.Count)"
$n = New-Case 'tobase'  @{ Base='EUREKALOG;BASEDEF;$(DCC_Define)' } (New-Unit 'EUREKALOG')
$f = Lint-Case $n; Check '(b) define moved to Base: 0' ($f.Count -eq 0) "count=$($f.Count)"
$n = New-Case 'untested' @{ Base=$base; Base_Win32='EUREKALOG;$(DCC_Define)' } (New-Unit 'OTHER')
$f = Lint-Case $n; Check '(c) divergent but never tested (the RED project minus its IFDEF): 0' ($f.Count -eq 0) "count=$($f.Count)"
$n = New-Case 'defined' @{ Base=$base; Base_Win32='EUREKALOG;$(DCC_Define)' } (New-Unit 'EUREKALOG' '{$DEFINE EUREKALOG}')
$f = Lint-Case $n; Check '(d) divergent, tested, but the unit DEFINEs it: 0' ($f.Count -eq 0) "count=$($f.Count)"
$n = New-Case 'undefd'  @{ Base=$base; Base_Win32='EUREKALOG;$(DCC_Define)' } (New-Unit 'EUREKALOG' '{$UNDEF EUREKALOG}')
$f = Lint-Case $n; Check '(d2) divergent, tested, but the unit UNDEFs it: 0' ($f.Count -eq 0) "count=$($f.Count)"
$n = New-Case 'allowed' @{ Base=$base; Base_Win32='EUREKALOG;$(DCC_Define)' } (New-Unit 'EUREKALOG') '{ "platform_divergent_allow": ["EurekaLog"] }'
$f = Lint-Case $n; Check '(e) symbol in platform_divergent_allow (case-insensitive): 0' ($f.Count -eq 0) "count=$($f.Count)"
$f = Lint-Case $red -NoProject; Check '(f) no .dproj passed (the RED unit): 0' ($f.Count -eq 0) "count=$($f.Count)"
$n = New-Case 'builtin' @{ Base=$base; Base_Win32='CPUX86;$(DCC_Define)' } (New-Unit 'CPUX86')
$f = Lint-Case $n; Check '(g) a compiler built-in (CPUX86) in one platform group: 0' ($f.Count -eq 0) "count=$($f.Count)"

Write-Host ''
Write-Host 'lint-all over an index of the RED project -- the same single finding' -ForegroundColor Cyan
$db = Join-Path $red 'p.sqlite'
& $Exe index --project (Join-Path $red 'P.dproj') --db $db 2>&1 | Out-Null
$la = Get-Findings @('lint-all', '--db', $db, '--project', (Join-Path $red 'P.dproj'), '--rule', $rule)
foreach ($x in $la) { Write-Host ("    {0}:{1} {2}" -f (Split-Path $x.file_path -Leaf), $x.start_line, $x.message) -ForegroundColor DarkGray }
Check 'lint-all: exactly 1 finding, in U.pas line 7' (($la.Count -eq 1) -and ((Split-Path $la[0].file_path -Leaf) -eq 'U.pas') -and ($la[0].start_line -eq 7)) "count=$($la.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-platform-divergent-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
