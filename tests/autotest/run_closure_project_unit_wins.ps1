<#
  run_closure_project_unit_wins.ps1 -- a unit the PROJECT names (`X in 'path'`
  in the .dpr, or a DCCReference) is that file for every unit that uses it; a
  same-named copy on the search path never enters the closure.

  THE PROBLEM (evaluation on ProjectA, 2026-09-28). The closure walk resolved
  each `uses X` by searching the path, first hit wins. When another folder on
  the path held a copy of X, a unit that used X pulled that COPY in beside the
  file the .dpr names: ProjectA indexed 15 such pairs (Fun_Helpers, UTextUtil,
  UWSPartnerC, ...), each unit twice. dcc does not search for a unit the project
  names, so the copy is not compiled -- but it was indexed, and every by-name
  lookup of its symbols then saw two candidates.

  THE FIX. TClosureResolver.Resolve records the project's own unit -> file
  bindings (DCCReference, then the .dpr's `in` paths, which win) and consults
  them before the search path.

  Usage: pwsh -File tests/autotest/run_closure_project_unit_wins.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-closure-unit-wins-$PID"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
foreach ($d in @('shared', 'other')) { New-Item -ItemType Directory (Join-Path $WorkDir $d) -Force | Out-Null }

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function UnitText([string]$Name, [string]$Uses) {
  $u = if ($Uses) { "uses`n  $Uses;`n`n" } else { '' }
  return "unit $Name;`n`ninterface`n`n${u}procedure Run$Name;`n`nimplementation`n`nprocedure Run$Name;`nbegin`nend;`n`nend.`n"
}

# The project names shared\UShared.pas. other\ is on the search path and holds a
# COPY of UShared, next to UOther, which uses UShared.
Write-Ascii (Join-Path $WorkDir 'shared\UShared.pas') (UnitText 'UShared' '')
Write-Ascii (Join-Path $WorkDir 'other\UShared.pas')  (UnitText 'UShared' '')
Write-Ascii (Join-Path $WorkDir 'other\UOther.pas')   (UnitText 'UOther' 'UShared')
Write-Ascii (Join-Path $WorkDir 'UMain.pas')          (UnitText 'UMain' 'UShared, UOther')
Write-Ascii (Join-Path $WorkDir 'App.dpr') @"
program App;

uses
  UShared in 'shared\UShared.pas',
  UMain in 'UMain.pas';

begin
end.
"@
Write-Ascii (Join-Path $WorkDir 'App.dproj') @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <DCC_UnitSearchPath>other;`$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="App.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="shared\UShared.pas"/>
    <DCCReference Include="UMain.pas"/>
  </ItemGroup>
</Project>
"@

$db  = Join-Path $WorkDir 'app.sqlite'
$dry = @((& $Exe index --project (Join-Path $WorkDir 'App.dproj') --db $db --platform win32 --dry-run 2>&1) | ForEach-Object { "$_" })
Check 'dry run exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$scope = @($dry | Where-Object { $_ -match '^\s\s([A-Za-z]:\\|\\\\)' } | ForEach-Object { $_.Trim() })
$shared = @($scope | Where-Object { $_ -like '*\UShared.pas' })
Check 'CONTROL: UOther, reached only through the search path, is in the closure' `
  (@($scope | Where-Object { $_ -like '*\other\UOther.pas' }).Count -eq 1) ($scope -join ' | ')
Check 'ASSERT: exactly ONE UShared.pas is in the closure' ($shared.Count -eq 1) ($shared -join ' | ')
Check 'ASSERT: ... and it is the file the .dpr names (shared\UShared.pas)' `
  (($shared.Count -ge 1) -and ($shared[0] -like '*\shared\UShared.pas')) ($shared -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-closure-unit-wins-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
