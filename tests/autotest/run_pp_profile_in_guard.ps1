<#
  run_pp_profile_in_guard.ps1 -- `pp-profile --in <file.pas>` prints the define
  profile of the file's OWN project's ACTIVE build (LSP C10 / A7-L, Task 1).

  Output contract of `pp-profile --in`: header lines  dproj= platform= config=
  source=builtins|dproj|delphilsp  digest=  then a blank line, then the sorted
  lowercased symbols (the existing format).

  Cases (fixture: proj\App.dproj marks Config=Debug, Platform=Win32; Debug adds
  MYFEATURE; proj\uUnit.pas is in the project; other\uLoose.pas is not):
    a  proj\uUnit.pas            -> source=dproj config=Debug platform=Win32,
                                    myfeature + win32 present, win64 absent
    b  other\uLoose.pas          -> source=builtins, no myfeature (POSITIVE CONTROL
                                    that the profile is per FILE)
    c  App.delphilsp.json beside, .dproj has markers -> the .dproj WINS (owner D1,
                                    2026-10-26): source=dproj platform=Win32,
                                    myfeature present, otherflag ABSENT
    c2 marker-less .dproj + JSON -> source=delphilsp platform=Win64, otherflag
                                    present, myfeature ABSENT (the JSON replaces)
    c3 0-byte .dproj + JSON      -> the same as c2 (unreadable .dproj)
    d  marker -> Release, no JSON -> config=Release, myfeature absent
    e  two .dproj in the folder   -> source=builtins (ambiguity rule D2)
    f  marker-less .dproj         -> config=Release (the default), Notes in play
    g  `pp-profile --dproj` output has NO header lines (old path byte-identical)

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-pp-in-$PID"
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
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force "$WorkDir\proj", "$WorkDir\other", "$WorkDir\amb" | Out-Null

function New-Dproj([string]$Path, [string]$Marker, [bool]$WithMarkers = $true) {
  $mk = if ($WithMarkers) {
    "        <Config Condition=""'`$(Config)'==''"">$Marker</Config>`r`n        <Platform Condition=""'`$(Platform)'==''"">Win32</Platform>`r`n"
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
        <DCC_Define>MYFEATURE;`$(DCC_Define)</DCC_Define>
    </PropertyGroup>
    <PropertyGroup Condition="'`$(Cfg_2)'!=''">
    </PropertyGroup>
</Project>
"@
  Write-Ascii $Path ($t -replace "`r?`n", "`r`n")
}
$Dproj = "$WorkDir\proj\App.dproj"
New-Dproj $Dproj 'Debug'
Write-Ascii "$WorkDir\proj\App.dpr" "program App;`r`nuses uUnit in 'uUnit.pas';`r`nbegin`r`nend.`r`n"
Write-Ascii "$WorkDir\proj\uUnit.pas" "unit uUnit;`r`ninterface`r`nimplementation`r`nend.`r`n"
Write-Ascii "$WorkDir\other\uLoose.pas" "unit uLoose;`r`ninterface`r`nimplementation`r`nend.`r`n"

# Run pp-profile --in; return @{ H = header hashtable; Syms = symbol list; Raw = text }.
function PpIn([string]$File) {
  $out = & $Exe pp-profile --in $File 2>&1 | ForEach-Object { "$_" }
  $h = @{}; $syms = @(); $blank = $false
  foreach ($l in $out) {
    if ($l -match '^\(loaded defaults') { continue }
    if ($l.Trim() -eq '') { $blank = $true; continue }
    if (-not $blank -and $l -match '^(\w+)=(.*)$') { $h[$Matches[1]] = $Matches[2].Trim() }
    elseif ($blank) { $syms += $l.Trim() }
  }
  return @{ H = $h; Syms = $syms; Raw = ($out -join "`n") }
}

# ---- a: file inside the project -> the project's ACTIVE build ----
$r = PpIn "$WorkDir\proj\uUnit.pas"
Check 'a source=dproj'        ($r.H['source'] -eq 'dproj')    ($r.Raw.Split("`n")[0..4] -join ' ')
Check 'a config=Debug'        ($r.H['config'] -eq 'Debug')
Check 'a platform=Win32'      ($r.H['platform'] -eq 'Win32')
Check 'a myfeature present'   ($r.Syms -contains 'myfeature')
Check 'a win32 present'       ($r.Syms -contains 'win32')
Check 'a win64 absent'        ($r.Syms -notcontains 'win64')
Check 'a digest is 8 hex'     ($r.H['digest'] -match '^[0-9a-f]{8}$')

# ---- b: loose file -> built-ins (POSITIVE CONTROL: per-file, not per-process) ----
$r = PpIn "$WorkDir\other\uLoose.pas"
Check 'b source=builtins'     ($r.H['source'] -eq 'builtins')
Check 'b no myfeature'        ($r.Syms -notcontains 'myfeature')
Check 'b has builtins'        ($r.Syms -contains 'mswindows')

# ---- c: delphilsp.json beside a .dproj WITH markers: the .dproj wins (D1) ----
$json = '{"settings":{"project":"file:///x/App.dpr","dllname":"dcc64370.dll","dccOptions":"-$O- -DOTHERFLAG;;FRAMEWORK_VCL -E.\\Win64\\Debug -I\"C:\\a b\\c\"","projectFiles":[]}}'
Write-Ascii "$WorkDir\proj\App.delphilsp.json" $json
$r = PpIn "$WorkDir\proj\uUnit.pas"
Check 'c source=dproj'        ($r.H['source'] -eq 'dproj') ($r.Raw.Split("`n")[0..4] -join ' ')
Check 'c platform=Win32'      ($r.H['platform'] -eq 'Win32')
Check 'c myfeature present'   ($r.Syms -contains 'myfeature')
Check 'c otherflag ABSENT'    ($r.Syms -notcontains 'otherflag')

# ---- c2: marker-less .dproj + JSON -> the JSON serves and REPLACES ----
New-Dproj $Dproj 'Debug' $false
$r = PpIn "$WorkDir\proj\uUnit.pas"
Check 'c2 source=delphilsp'   ($r.H['source'] -eq 'delphilsp') ($r.Raw.Split("`n")[0..4] -join ' ')
Check 'c2 platform=Win64'     ($r.H['platform'] -eq 'Win64')
Check 'c2 otherflag present'  ($r.Syms -contains 'otherflag')
Check 'c2 framework_vcl present' ($r.Syms -contains 'framework_vcl')
Check 'c2 myfeature ABSENT'   ($r.Syms -notcontains 'myfeature')
Check 'c2 win64 present'      ($r.Syms -contains 'win64')

# ---- c3: 0-byte (unreadable) .dproj + JSON -> the JSON serves ----
[IO.File]::WriteAllBytes($Dproj, [byte[]]@())
$r = PpIn "$WorkDir\proj\uUnit.pas"
Check 'c3 source=delphilsp'   ($r.H['source'] -eq 'delphilsp') ($r.Raw.Split("`n")[0..4] -join ' ')
Check 'c3 otherflag present'  ($r.Syms -contains 'otherflag')

# ---- d: JSON gone, marker -> Release ----
[IO.File]::Delete("$WorkDir\proj\App.delphilsp.json")
New-Dproj $Dproj 'Release'
$r = PpIn "$WorkDir\proj\uUnit.pas"
Check 'd source=dproj'        ($r.H['source'] -eq 'dproj')
Check 'd config=Release'      ($r.H['config'] -eq 'Release')
Check 'd myfeature absent'    ($r.Syms -notcontains 'myfeature')

# ---- e: two .dproj in one folder, no DB -> ambiguous -> built-ins ----
New-Dproj "$WorkDir\amb\A.dproj" 'Debug'
New-Dproj "$WorkDir\amb\B.dproj" 'Debug'
Write-Ascii "$WorkDir\amb\uAmb.pas" "unit uAmb;`r`ninterface`r`nimplementation`r`nend.`r`n"
$r = PpIn "$WorkDir\amb\uAmb.pas"
Check 'e source=builtins'     ($r.H['source'] -eq 'builtins')
Check 'e no myfeature'        ($r.Syms -notcontains 'myfeature')

# ---- f: marker-less .dproj -> Release default ----
New-Dproj $Dproj 'Debug' $false
$r = PpIn "$WorkDir\proj\uUnit.pas"
Check 'f source=dproj'        ($r.H['source'] -eq 'dproj')
Check 'f config=Release'      ($r.H['config'] -eq 'Release')
Check 'f myfeature absent'    ($r.Syms -notcontains 'myfeature')

# ---- g: the --dproj path prints symbols only (no header lines) ----
New-Dproj $Dproj 'Debug'
$g = @(& $Exe pp-profile --dproj $Dproj --platform Win32 --config Debug 2>&1 | ForEach-Object { "$_" } |
       Where-Object { $_ -notmatch '^\(loaded defaults' })
# Lane INC2: value lines ('compilerversion=37') follow the symbols; a HEADER line is one of the --in keys.
Check 'g no header lines'     (-not ($g | Where-Object { $_ -match '^(dproj|platform|config|source|digest)=' })) ($g -join ' ')
Check 'g myfeature present'   ($g -contains 'myfeature')
}
catch { Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red; $script:Failed = $true }
finally {
  try { if ($WorkDir -and (Test-Path $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { Write-Host 'run_pp_profile_in_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_pp_profile_in_guard: PASS' -ForegroundColor Green
exit 0
