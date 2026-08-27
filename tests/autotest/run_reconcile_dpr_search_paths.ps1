<#
  run_reconcile_dpr_search_paths.ps1 -- resolving a .dpr must use the sibling
  .dproj's search paths, and doing so must NOT make EXTRA vacuously empty.

  Why this exists
  ---------------
  A .dpr carries no search paths; they live in the .dproj's DCC_UnitSearchPath.
  TClosureResolver.Resolve read them only in its .dproj branch -- and
  TProjectReconciler.Analyze resolves the closure from the .dpr NO MATTER which
  file it is given, so the .dpr branch is the one reconcile always takes.

  Consequence, reproduced on this repo 2026-08-26: src\doc was not on the path,
  DRagLint.Doc.Drift could not be resolved to a file, it never entered the
  closure, and reconcile reported it as EXTRA -- "listed but never reached via
  uses". That was false, and it is the kind of false report that gets acted on:
  the advice is to remove the unit from the project.

  THE SECOND CHECK IS THE LOAD-BEARING ONE
  ----------------------------------------
  The obvious "fix" is to seed the closure from the .dproj DCCReference list.
  That would make this guard's first check pass and would be WRONG: every listed
  unit would then be in the closure BECAUSE it was listed, EXTRA would be
  vacuously empty for every project forever, and the verb would go green while
  losing the only thing it detects. So a genuinely unreachable listed unit must
  STILL be reported EXTRA. A fix that satisfies check 1 by breaking check 2 is
  not a fix.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_dpr_search_paths"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Host '== reconcile uses the .dproj search paths when resolving a .dpr ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$sub = Join-Path $WorkDir 'sub'
New-Item -ItemType Directory -Force -Path $sub | Out-Null

# Reached ONLY via the .dproj search path: the .dpr names it with no `in`
# clause, and its file lives in sub\ .
Write-Ascii (Join-Path $sub 'Far.Away.pas') @'
unit Far.Away;

interface

implementation

end.
'@

# Listed in the .dproj but used by NOTHING -- must remain EXTRA.
Write-Ascii (Join-Path $WorkDir 'Orphan.Listed.pas') @'
unit Orphan.Listed;

interface

implementation

end.
'@

Write-Ascii (Join-Path $WorkDir 'P.dpr') @'
program P;

uses
  Far.Away;

begin
end.
'@

Write-Ascii (Join-Path $WorkDir 'P.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>P.dpr</MainSource>
        <DCC_UnitSearchPath>sub;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="sub\Far.Away.pas"/>
        <DCCReference Include="Orphan.Listed.pas"/>
    </ItemGroup>
</Project>
'@

$out = (& $Exe reconcile-project (Join-Path $WorkDir 'P.dpr') 2>&1) -join "`n"

Check 'a unit reachable only via the .dproj search path is NOT called EXTRA' `
  (-not ($out -match 'EXTRA[\s\S]{0,300}?Far\.Away')) "out=$out"

# The control that stops the cheap fix: seeding the closure from DCCReference
# would satisfy the check above and empty EXTRA for everything.
Check 'a listed-but-unreachable unit IS still reported EXTRA' `
  ($out -match 'EXTRA[\s\S]{0,300}?Orphan\.Listed') "out=$out"

Check 'reconcile exits cleanly' ($LASTEXITCODE -le 1) "exit=$LASTEXITCODE"

Write-Host ''
if ($script:Failed) { Write-Host 'DPR SEARCH PATHS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DPR SEARCH PATHS GUARD: PASS' -ForegroundColor Green
exit 0
