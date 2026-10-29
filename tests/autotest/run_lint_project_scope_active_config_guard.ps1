<#
  run_lint_project_scope_active_config_guard.ps1 -- the SCOPE of a `--project X.dproj`
  lint run (BuildProjectFileScope: which units it lints) follows X's ACTIVE build
  config, the same config its DEFINES follow since C10 (owner D5). Before this fix the
  closure was resolved against a hard-wired Release profile, so a unit pulled in only
  under an {$IFDEF} of the active Debug config was silently out of scope, and a
  Release-only unit was linted although the active build never compiles it.

  Fixture: proj\App.dproj marks Config=<marker>; Debug defines MYFEATURE, Release none.
  App.dpr uses uCommon always, uDebugOnly under {$IFDEF MYFEATURE}, uReleaseOnly under
  {$IFNDEF MYFEATURE}. Each unit holds one magic literal, so a unit in scope yields a
  magic-literal finding and one out of scope yields none. The DB is a FOLDER index, so
  all three units are indexed whatever the config: only the lint scope decides.

    a  marker Debug   -> uDebugOnly in scope, uReleaseOnly NOT   (RED on the Release-fixed engine)
    b  marker Debug   -> uCommon in scope                       (POSITIVE CONTROL: findings are produced at all)
    c  marker Release -> uReleaseOnly in scope, uDebugOnly NOT   (POSITIVE CONTROL: the scope MOVES with the config)

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lintscopecfg-$PID"
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
New-Item -ItemType Directory -Force "$WorkDir\proj", "$WorkDir\db" | Out-Null

function New-Dproj([string]$Path, [string]$Marker) {
  $t = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{22222222-3333-4444-5555-666666666666}</ProjectGuid>
        <Config Condition="'`$(Config)'==''">$Marker</Config>
        <Platform Condition="'`$(Platform)'==''">Win64</Platform>
        <MainSource>App.dpr</MainSource>
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
function New-Unit([string]$Name, [int]$Literal) {
  Write-Ascii "$WorkDir\proj\$Name.pas" ("unit $Name;`r`ninterface`r`nfunction Get$Name`: Integer;`r`nimplementation`r`n" +
    "function Get$Name`: Integer;`r`nbegin`r`n  Result:= $Literal;`r`nend;`r`nend.`r`n")
}
$Dproj = "$WorkDir\proj\App.dproj"
$Db    = "$WorkDir\db\App.sqlite"
New-Dproj $Dproj 'Debug'
Write-Ascii "$WorkDir\proj\App.dpr" ("program App;`r`nuses`r`n  uCommon in 'uCommon.pas'`r`n" +
  "  {`$IFDEF MYFEATURE}, uDebugOnly in 'uDebugOnly.pas'{`$ENDIF}`r`n" +
  "  {`$IFNDEF MYFEATURE}, uReleaseOnly in 'uReleaseOnly.pas'{`$ENDIF};`r`nbegin`r`nend.`r`n")
New-Unit 'uCommon'      48611
New-Unit 'uDebugOnly'   48622
New-Unit 'uReleaseOnly' 48633

# FOLDER index: every unit is in the DB, whatever the config.
& $Exe index "$WorkDir\proj" --db $Db *> "$WorkDir\index.log"
$idxCode = $LASTEXITCODE
. (Join-Path $PSScriptRoot 'exe-hint.ps1')   # Get-ExeStartFailureHint (CLIFIX C2)
if (-not (Test-Path $Db)) { $hint = Get-ExeStartFailureHint $idxCode; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: index produced no DB; see $WorkDir\index.log" -ForegroundColor Red; exit 2 }

# The units a --project lint-all run reports magic-literal findings for.
function ScopedUnits([string[]]$Extra = @()) {
  $o = & $Exe lint-all --db $Db --project $Dproj @Extra --enable magic-literal --json 2>$null | Out-String
  $start = $o.IndexOf('[')
  if ($start -lt 0) { return @("<no json: $o>") }
  try { $arr = @($o.Substring($start) | ConvertFrom-Json) } catch { return @("<unparsed: $o>") }
  return @($arr | Where-Object { $_.rule -eq 'magic-literal' } |
    ForEach-Object { [IO.Path]::GetFileNameWithoutExtension([string]$_.file_path) } | Sort-Object -Unique)
}

# ---- a/b: marker Debug ----
$u = ScopedUnits
$d = "units=[$($u -join ',')]"
Check 'a Debug: uDebugOnly in scope'      ($u -contains 'uDebugOnly')        $d
Check 'a Debug: uReleaseOnly out of scope' (-not ($u -contains 'uReleaseOnly')) $d
Check 'b Debug: uCommon in scope (control)' ($u -contains 'uCommon')         $d

# ---- c: marker Release ----
New-Dproj $Dproj 'Release'
$u = ScopedUnits
$d = "units=[$($u -join ',')]"
Check 'c Release: uReleaseOnly in scope'  ($u -contains 'uReleaseOnly')      $d
Check 'c Release: uDebugOnly out of scope' (-not ($u -contains 'uDebugOnly')) $d
Check 'c Release: uCommon in scope'       ($u -contains 'uCommon')           $d

# ---- d/e: --build-config overrides the marker (scope AND defines together) ----
# marker is Release now; --build-config Debug must flip the scope to the Debug build.
$u = ScopedUnits @('--build-config', 'Debug')
$d = "units=[$($u -join ',')]"
Check 'd marker Release + --build-config Debug: uDebugOnly in scope'      ($u -contains 'uDebugOnly')            $d
Check 'd marker Release + --build-config Debug: uReleaseOnly out of scope' (-not ($u -contains 'uReleaseOnly'))  $d
# and the reverse: marker Debug, --build-config Release.
New-Dproj $Dproj 'Debug'
$u = ScopedUnits @('--build-config', 'Release')
$d = "units=[$($u -join ',')]"
Check 'e marker Debug + --build-config Release: uReleaseOnly in scope'    ($u -contains 'uReleaseOnly')          $d
Check 'e marker Debug + --build-config Release: uDebugOnly out of scope'  (-not ($u -contains 'uDebugOnly'))     $d

if ($script:Failed) { Write-Host 'run_lint_project_scope_active_config_guard: FAIL' -ForegroundColor Red; exit 1 }
[IO.Directory]::Delete($WorkDir, $true)
Write-Host 'run_lint_project_scope_active_config_guard: PASS' -ForegroundColor Green
exit 0
