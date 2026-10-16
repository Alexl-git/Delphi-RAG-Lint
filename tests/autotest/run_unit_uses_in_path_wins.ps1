<#
  run_unit_uses_in_path_wins.ps1 -- the project file's `UFoo in 'sub\UFoo.pas'`
  names the file every `uses UFoo` of the project resolves to (Gitea
  drag-lint#10, resolver 1.20.0-alpha).

  THE DEFECT. ResolveUnitUseTargets mapped a used-unit name to a .pas by stem
  alone, and with two indexed copies of UFoo.pas the LAST path read won --
  byte order of the path, ignoring the .dpr's `in`. Two ways to get there:
    a2  the .dproj also carries a DCCReference to another UFoo.pas (the closure
        admits both), and that path sorts later;
    b3  a copy was indexed into the same database earlier (a widened index --
        on ProjectA, an orphan UErrors.pas under D:\Components, which sorts
        after D:\WorkRepo).
  Every `uses UFoo` then pointed at the copy, whose routines differ, and
  `find-callers --name FooRight --resolved` answered "0 caller(s)", exit 1.

  WHAT THIS ASSERTS (each case its own database)
    1. a2: find-callers --resolved finds RunMain for FooRight            <- THE FIX
    2. b3: the same                                                      <- THE FIX
    3. CONTROL (a): copies only on the search path -- the closure already
       took the `in` file, still 1 caller
    4. CONTROL (b2): a copy with a path that sorts EARLIER -- 1 caller
    5. CONTROL: two project files naming DIFFERENT UFoo.pas settle nothing:
       the stem rule's answer (last path) stands, as before

  RED-CHECK: against the pre-fix build 1 and 2 FAIL (0 callers); 3, 4 and 5
  pass on both builds.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$Root = Join-Path C:\TEMP "draglint_inpath_$PID"
if (Test-Path $Root) { Get-ChildItem $Root -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $Root -Force | Out-Null

function W([string]$Path, [string]$Body) {
  New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
  $n = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText($Path, $n, [Text.Encoding]::ASCII)
}
function U([string]$Name, [string]$Proc, [string]$Uses) {
  $u = if ($Uses) { "uses`n  $Uses;`n`n" } else { '' }
  "unit $Name;`n`ninterface`n`n${u}procedure $Proc;`n`nimplementation`n`nprocedure $Proc;`nbegin`nend;`n`nend.`n"
}
function MakeProj([string]$Dir, [string]$SearchPath, [switch]$DccRefCopy) {
  W "$Dir\P\sub\UFoo.pas" (U 'UFoo' 'FooRight' '')
  W "$Dir\P\UMain.pas" "unit UMain;`n`ninterface`n`nuses UFoo;`n`nprocedure RunMain;`n`nimplementation`n`nprocedure RunMain;`nbegin`n  FooRight;`nend;`n`nend.`n"
  W "$Dir\P\App.dpr" "program App;`n`nuses`n  UFoo in 'sub\UFoo.pas',`n  UMain in 'UMain.pas';`n`nbegin`nend.`n"
  $extra = if ($DccRefCopy) { "`n    <DCCReference Include=`"..\z_high\UFoo.pas`"/>" } else { '' }
  W "$Dir\P\App.dproj" @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <DCC_UnitSearchPath>$SearchPath;`$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="App.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="sub\UFoo.pas"/>
    <DCCReference Include="UMain.pas"/>$extra
  </ItemGroup>
</Project>
"@
  W "$Dir\A_low\UFoo.pas"  (U 'UFoo' 'FooCopyLow' '')
  W "$Dir\z_high\UFoo.pas" (U 'UFoo' 'FooCopyHigh' '')
}
function Idx([string[]]$IdxArgs) { & $Exe @IdxArgs *> $null; return $LASTEXITCODE }
function Callers([string]$Db) {
  $o = @(& $Exe query find-callers --name FooRight --db $Db --resolved 2>$null)
  return @($o | Where-Object { $_ -match 'RunMain' }).Count
}

Write-Host ''
Write-Host '=== the cases that resolved to the copy ===' -ForegroundColor Cyan
$d = "$Root\a2"; MakeProj $d '..\A_low' -DccRefCopy
$null = Idx @('index','--project',"$d\P\App.dproj",'--db',"$d\a2.sqlite",'--platform','win32')
$n = Callers "$d\a2.sqlite"
Check '1. a2 (DCCReference to a later-sorting copy): FooRight has its caller' ($n -ge 1) "callers=$n"

$d = "$Root\b3"; MakeProj $d '.'
$null = Idx @('index',"$d\z_high",'--db',"$d\b.sqlite",'--platform','win32')
$null = Idx @('index','--project',"$d\P\App.dproj",'--db',"$d\b.sqlite",'--platform','win32')
$n = Callers "$d\b.sqlite"
Check '2. b3 (later-sorting copy indexed first): FooRight has its caller' ($n -ge 1) "callers=$n"

Write-Host ''
Write-Host '=== CONTROLS ===' -ForegroundColor Cyan
$d = "$Root\a"; MakeProj $d '..\A_low;..\z_high'
$null = Idx @('index','--project',"$d\P\App.dproj",'--db',"$d\a.sqlite",'--platform','win32')
$n = Callers "$d\a.sqlite"
Check '3. CONTROL (a): copies on the search path only -- 1 caller' ($n -ge 1) "callers=$n"

$d = "$Root\b2"; MakeProj $d '.'
$null = Idx @('index',"$d\A_low",'--db',"$d\b.sqlite",'--platform','win32')
$null = Idx @('index','--project',"$d\P\App.dproj",'--db',"$d\b.sqlite",'--platform','win32')
$n = Callers "$d\b.sqlite"
Check '4. CONTROL (b2): an earlier-sorting copy -- 1 caller' ($n -ge 1) "callers=$n"

# Two programs in one LIBRARY-style folder database, each naming its own UFoo:
# neither `in` may win for the other, so the stem answer (last path) stands.
$d = "$Root\two"
W "$d\A\UFoo.pas" (U 'UFoo' 'FooA' '')
W "$d\Z\UFoo.pas" (U 'UFoo' 'FooZ' '')
W "$d\UUse.pas" "unit UUse;`n`ninterface`n`nuses UFoo;`n`nprocedure CallIt;`n`nimplementation`n`nprocedure CallIt;`nbegin`n  FooZ;`nend;`n`nend.`n"
W "$d\PA.dpr" "program PA;`n`nuses`n  UFoo in 'A\UFoo.pas',`n  UUse in 'UUse.pas';`n`nbegin`nend.`n"
W "$d\PZ.dpr" "program PZ;`n`nuses`n  UFoo in 'Z\UFoo.pas',`n  UUse in 'UUse.pas';`n`nbegin`nend.`n"
$null = Idx @('index',$d,'--db',"$d\t.sqlite",'--platform','win32')
$o = @(& $Exe query find-callers --name FooZ --db "$d\t.sqlite" --resolved 2>$null)
$n = @($o | Where-Object { $_ -match 'CallIt' }).Count
Check '5. CONTROL: two project files disagree -> the stem answer (Z, the later path) stands' ($n -ge 1) "callers=$n"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_inpath_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
