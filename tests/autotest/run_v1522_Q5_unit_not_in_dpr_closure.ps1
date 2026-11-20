<#
  run_v1522_Q5_unit_not_in_dpr_closure.ps1 -- lane v1522 Q5.

  Owner ruling Q5 (2026-11-19): unit-not-in-dpr covers the FULL compile closure minus the
  library / third-party roots (registry library paths plus the manifest Library section's
  "include" folders, the same set unit-not-in-library and reconcile-project call "the library").

  Fixture (built here, in a temp folder):
    app\App.dpr / App.dproj   lists UMain only; search path ..\shared;..\vendor
    app\UMain.pas             uses UMid
    app\UMid.pas              NOT listed; uses UDeep, UShared, UVendor
    app\UDeep.pas             NOT listed; reached only transitively (UMain -> UMid -> UDeep)
    shared\UShared.pas        NOT listed; outside the project root, not a library folder
    vendor\UVendor.pas        NOT listed; under a manifest Library "include" folder
    .drag-lint.json           Library section, include = vendor
  CASES
    T1  UDeep (transitive, own root) is reported by unit-not-in-dpr
    T2  UMid (direct, own root) is reported
    T3  UShared (closure, outside the root, not library) is reported exactly once
    L1  UVendor (under a library root) is NOT reported
    P1  positive control: the same run with a manifest WITHOUT the include reports UVendor
    P2  positive control: --disable unit-not-in-dpr reports none of them

  pwsh -File tests\autotest\run_v1522_Q5_unit_not_in_dpr_closure.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function W([string]$p, [string]$t) {
  [IO.Directory]::CreateDirectory((Split-Path -Parent $p)) | Out-Null
  [IO.File]::WriteAllText($p, ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

$Rule = 'unit-not-in-dpr'
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v1522-q5-' + [guid]::NewGuid().ToString('N'))
$App  = Join-Path $Work 'app'
$Dproj = Join-Path $App 'App.dproj'
$Db    = Join-Path $Work 'app.sqlite'

W "$App\App.dproj" @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>App.dpr</MainSource><Config Condition="'$(Config)'==''">Debug</Config><Base>true</Base></PropertyGroup>
  <PropertyGroup Condition="'$(Base)'!=''"><DCC_UnitSearchPath>..\shared;..\vendor;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="App.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="UMain.pas"/>
  </ItemGroup>
</Project>
'@
W "$App\App.dpr" "program App;`n`nuses`n  UMain in 'UMain.pas';`n`nbegin`n  MainRun;`nend.`n"
W "$App\UMain.pas" "unit UMain;`n`ninterface`n`nprocedure MainRun;`n`nimplementation`n`nuses`n  UMid;`n`nprocedure MainRun;`nbegin`n  MidRun;`nend;`n`nend.`n"
W "$App\UMid.pas" "unit UMid;`n`ninterface`n`nprocedure MidRun;`n`nimplementation`n`nuses`n  UDeep, UShared, UVendor;`n`nprocedure MidRun;`nbegin`n  DeepRun;`n  SharedRun;`n  VendorRun;`nend;`n`nend.`n"
W "$App\UDeep.pas" "unit UDeep;`n`ninterface`n`nprocedure DeepRun;`n`nimplementation`n`nprocedure DeepRun;`nbegin`nend;`n`nend.`n"
W "$Work\shared\UShared.pas" "unit UShared;`n`ninterface`n`nprocedure SharedRun;`n`nimplementation`n`nprocedure SharedRun;`nbegin`nend;`n`nend.`n"
W "$Work\vendor\UVendor.pas" "unit UVendor;`n`ninterface`n`nprocedure VendorRun;`n`nimplementation`n`nprocedure VendorRun;`nbegin`nend;`n`nend.`n"

$vendorJson = ("$Work\vendor" -replace '\\', '\\')
$CfgInc = @"
{
  "indexes": {
    "sections": [
      { "name": "Library", "source": "registry-libraries", "platforms": ["Win64"],
        "include": ["$vendorJson"] }
    ]
  }
}
"@
$CfgNoInc = @'
{
  "indexes": {
    "sections": [
      { "name": "Library", "source": "registry-libraries", "platforms": ["Win64"] }
    ]
  }
}
'@

function LintAll([string[]]$extra) {
  Push-Location $App
  try {
    $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --project $Dproj --rule $Rule --json @extra 2>$null }) -join "`n"
  } finally { Pop-Location }
  $arr = @()
  try { $arr = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { Write-Host ('  raw: ' + $raw) }
  $hits = @($arr | Where-Object { $_.rule -eq $Rule })
  $hits | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f $_.file_path, $_.start_line, $_.message) }
  return ,$hits
}
function CountUnit($hits, [string]$unit) { return @($hits | Where-Object { ('' + $_.message) -match ('"' + $unit + '"') }).Count }

try {
  W "$Work\.drag-lint.json" $CfgInc
  Push-Location $App
  try {
    $idx = (& { $ErrorActionPreference = 'Continue'; & $Exe index --project $Dproj --db $Db 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0) { Write-Host $idx; Check 'index exit 0' $false; throw 'index failed' }

  $h = LintAll @()
  Check 'T1 UDeep (transitive, own root) reported'          ((CountUnit $h 'UDeep') -ge 1)   ("n=$(CountUnit $h 'UDeep')")
  Check 'T2 UMid (own root) reported'                       ((CountUnit $h 'UMid') -ge 1)    ("n=$(CountUnit $h 'UMid')")
  Check 'T3 UShared (outside root, not library) reported once' ((CountUnit $h 'UShared') -eq 1) ("n=$(CountUnit $h 'UShared')")
  Check 'L1 UVendor (library include root) NOT reported'    ((CountUnit $h 'UVendor') -eq 0) ("n=$(CountUnit $h 'UVendor')")

  W "$Work\.drag-lint.json" $CfgNoInc
  $p = LintAll @()
  Check 'P1 positive control: no include -> UVendor reported' ((CountUnit $p 'UVendor') -eq 1) ("n=$(CountUnit $p 'UVendor')")

  $off = LintAll @('--disable', $Rule)
  Check 'P2 positive control: --disable -> nothing'          ($off.Count -eq 0) ("n=$($off.Count)")
} finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
