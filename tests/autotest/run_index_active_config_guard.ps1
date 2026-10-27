<#
  run_index_active_config_guard.ps1 -- a PROJECT index is parsed against the project's
  ACTIVE build config, not a hard-wired Release (LSP C10 / A7-I, owner D5), and the
  fingerprint records it so a config switch re-parses exactly that DB.

  Fixture: proj\App.dproj marks Config=Debug; Debug defines MYFEATURE, Release none.
  proj\uUnit.pas declares OnlyInDebug under {$IFDEF MYFEATURE} and OnlyInRelease under
  {$IFNDEF MYFEATURE}.

    a  marker Debug  -> OnlyInDebug=1 OnlyInRelease=0; fingerprint ends
                        ;cfg=debug;defs=<8hex>   (RED on the Release-hard-wired engine)
    b  summary line  -> "index: defines cfg=Debug source=dproj defs=<8hex>"
    c  marker Release, NO --rebuild -> "Indexer changed since this DB was built" and the
                        two counts SWAP (POSITIVE CONTROL: the limb drives a re-parse)
    d  --build-config Debug on the Release-marked .dproj -> (a) again, limb cfg=debug
    e  FOLDER db (no .dproj) -> fingerprint has NO cfg= limb and is exactly
                        v=<ver>;schema=<n>;pp=1;plat=win64   (libraries untouched)
    f  marker-less .dproj + App.delphilsp.json (-DMYFEATURE, dcc64) -> OnlyInDebug=1,
                        source=delphilsp, limb is the LITERAL ;cfg=<json>;defs=<8hex>
    g  a .dproj defines edit changes defs= and re-parses (same config name)

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-idxcfg-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force "$WorkDir\proj\_D-RAG", "$WorkDir\folder" | Out-Null

function New-Dproj([string]$Path, [string]$Marker, [bool]$WithMarkers = $true, [string]$DebugDefine = 'MYFEATURE') {
  $mk = if ($WithMarkers) {
    "        <Config Condition=""'`$(Config)'==''"">$Marker</Config>`r`n        <Platform Condition=""'`$(Platform)'==''"">Win64</Platform>`r`n"
  } else { '' }
  $t = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{11111111-2222-3333-4444-555555555555}</ProjectGuid>
$mk        <MainSource>App.dpr</MainSource>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Base' or '`$(Base)'!=''">
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Debug' or '`$(Cfg_1)'!=''">
        <CfgParent>Base</CfgParent>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Config)'=='Release' or '`$(Cfg_2)'!=''">
        <CfgParent>Base</CfgParent>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Base)'!=''">
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_1)'!=''">
        <DCC_Define>$DebugDefine;`$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_2)'!=''">
    </PropertyGroup>
</Project>
"@
  Write-Ascii $Path ($t -replace "`r?`n", "`r`n")
}
$Dproj = "$WorkDir\proj\App.dproj"
$Db    = "$WorkDir\proj\_D-RAG\App.sqlite"
New-Dproj $Dproj 'Debug'
Write-Ascii "$WorkDir\proj\App.dpr" "program App;`r`nuses uUnit in 'uUnit.pas';`r`nbegin`r`nend.`r`n"
Write-Ascii "$WorkDir\proj\uUnit.pas" ("unit uUnit;`r`ninterface`r`n{`$IFDEF MYFEATURE}`r`nprocedure OnlyInDebug;`r`n{`$ENDIF}`r`n" +
  "{`$IFNDEF MYFEATURE}`r`nprocedure OnlyInRelease;`r`n{`$ENDIF}`r`nimplementation`r`n{`$IFDEF MYFEATURE}`r`nprocedure OnlyInDebug; begin end;`r`n{`$ENDIF}`r`n" +
  "{`$IFNDEF MYFEATURE}`r`nprocedure OnlyInRelease; begin end;`r`n{`$ENDIF}`r`nend.`r`n")
Write-Ascii "$WorkDir\folder\uLoose.pas" "unit uLoose;`r`ninterface`r`nprocedure LooseProc;`r`nimplementation`r`nprocedure LooseProc; begin end;`r`nend.`r`n"

function IndexProj([string[]]$Extra = @()) {
  return (& $Exe index --project $Dproj --db $Db @Extra 2>&1 | ForEach-Object { "$_" }) -join "`n"
}
function Fp([string]$Database) {
  $j = & $Exe sql --query "SELECT value FROM schema_meta WHERE key='indexer_fingerprint'" --db $Database --json 2>$null | Out-String
  try { return [string](($j | ConvertFrom-Json).rows[0][0]) } catch { return "<unparsed: $j>" }
}
function Cnt([string]$Name) {
  $o = & $Exe query --name $Name --db $Db --exact --json 2>$null | Out-String
  try {
    $x = $o | ConvertFrom-Json
    if ($null -eq $x) { return 0 } else { return @($x).Count }
  } catch { return -1 }
}

# ---- a/b: marker Debug ----
$log = IndexProj
$fp = Fp $Db
Check 'a OnlyInDebug=1'    ((Cnt 'OnlyInDebug') -eq 1)   "got $(Cnt 'OnlyInDebug')"
Check 'a OnlyInRelease=0'  ((Cnt 'OnlyInRelease') -eq 0) "got $(Cnt 'OnlyInRelease')"
Check 'a fingerprint cfg=debug limb' ($fp -match ';cfg=debug;defs=[0-9a-f]{8}$') $fp
$fpDebug = $fp
Check 'b summary line' ($log -match 'index: defines cfg=Debug source=dproj defs=[0-9a-f]{8}') ($log -split "`n" | Select-String 'defines' | Select-Object -First 1)

# ---- c: flip to Release, no --rebuild ----
New-Dproj $Dproj 'Release'
$log = IndexProj
$fp = Fp $Db
Check 'c announces fingerprint change' ($log -match 'Indexer changed since this DB was built')
Check 'c OnlyInDebug=0'    ((Cnt 'OnlyInDebug') -eq 0)
Check 'c OnlyInRelease=1'  ((Cnt 'OnlyInRelease') -eq 1)
Check 'c limb cfg=release' ($fp -match ';cfg=release;defs=[0-9a-f]{8}$') $fp

# ---- d: --build-config Debug on the Release-marked .dproj ----
$log = IndexProj @('--build-config', 'Debug')
$fp = Fp $Db
Check 'd OnlyInDebug=1'    ((Cnt 'OnlyInDebug') -eq 1)
Check 'd OnlyInRelease=0'  ((Cnt 'OnlyInRelease') -eq 0)
Check 'd limb cfg=debug'   ($fp -match ';cfg=debug;defs=[0-9a-f]{8}$') $fp
Check 'd same fingerprint as a' ($fp -eq $fpDebug)

# ---- e: FOLDER db has no cfg limb ----
$FDb = "$WorkDir\folder\folder.sqlite"
& $Exe index "$WorkDir\folder" --db $FDb 2>&1 | Out-Null
$ffp = Fp $FDb
Check 'e folder fingerprint has NO cfg limb' ($ffp -match '^v=[^;]+;schema=\d+;pp=1;plat=win64$') $ffp

# ---- f: marker-less .dproj + delphilsp.json -> literal cfg=<json> ----
New-Dproj $Dproj 'Debug' $false
Write-Ascii "$WorkDir\proj\App.delphilsp.json" '{"settings":{"project":"file:///x/App.dpr","dllname":"dcc64370.dll","dccOptions":"-$O- -DMYFEATURE;;FRAMEWORK_VCL -E.\\Win64\\Debug","projectFiles":[]}}'
$log = IndexProj
$fp = Fp $Db
Check 'f OnlyInDebug=1'    ((Cnt 'OnlyInDebug') -eq 1)
Check 'f source=delphilsp' ($log -match 'source=delphilsp') ($log -split "`n" | Select-String 'defines' | Select-Object -First 1)
Check 'f literal cfg=<json> limb' ($fp -match ';cfg=<json>;defs=[0-9a-f]{8}$') $fp
[IO.File]::Delete("$WorkDir\proj\App.delphilsp.json")

# ---- g: same config name, different define set -> defs= changes, re-parse ----
New-Dproj $Dproj 'Debug' $true 'MYFEATURE'
$null = IndexProj
$fpA = Fp $Db
New-Dproj $Dproj 'Debug' $true 'MYFEATURE;EXTRADEF'
$log = IndexProj
$fpB = Fp $Db
Check 'g defs digest changed' ($fpA -ne $fpB -and $fpB -match ';cfg=debug;defs=') "$fpA -> $fpB"
Check 'g re-parse announced'  ($log -match 'Indexer changed since this DB was built')

if ($script:Failed) { Write-Host 'index active-config guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'index active-config guard: PASS' -ForegroundColor Green; exit 0
