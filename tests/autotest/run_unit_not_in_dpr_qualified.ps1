# Guard: unit-not-in-dpr compares QUALIFIED unit names, so two units sharing a
# last dot-segment are not confused for one another.
#
# THE DEFECT. Both sides of the .dproj-vs-.dpr membership comparison were keyed
# through NormUnit, which truncates to the LAST dot-segment. So
# `DRagLint.Doc.Drift` and `DRagLint.Index.Drift` both keyed as `drift`, and a
# unit present in the .dproj and MISSING from the .dpr was silently satisfied by
# an unrelated namesake. Measured on this repo: DRagLint.Doc.Drift is in the
# .dproj, absent from the .dpr, and the rule reported 0 findings. After the fix
# it reports it -- 0 -> 1, a TRUE finding that had been hidden.
#
# WHY NormUnit WAS NOT SIMPLY CHANGED. Its truncation is load-bearing elsewhere:
# it matches a LEGACY UNQUALIFIED name against a qualified file (`Graphics` in a
# .dpr against `Vcl.Graphics.pas` in the .dproj) -- the FP-9 class it was added
# for, and its own doc-comment says so. A sibling NormUnitQualified was added and
# used only where BOTH sides carry their qualification.
#
# THE FP-9 ARM IS NOT DECORATION -- it caught a real bug in the first attempt.
# The stem fallback was originally gated on "the key being looked up has no dot",
# which reads as equivalent and is not: in the FP-9 case the DOTTED name
# (`vcl.legacy`) is the one being looked up and the UNQUALIFIED one is what it
# must match, so that gate skipped the fallback and produced a FALSE POSITIVE on
# exactly the case the truncation exists for. The fallback now tests the
# COUNTERPART entry's qualification.
#
# Usage: pwsh -File tests/autotest/run_unit_not_in_dpr_qualified.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-dpr-qualified"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Four units:
#   App.Drift  -- in the .dproj AND the .dpr        -> must NOT be reported
#   Lib.Drift  -- in the .dproj, NOT in the .dpr    -> MUST be reported
#                 (same last segment as App.Drift -- the collision)
#   Vcl.Legacy -- in the .dproj as a dotted path, named UNQUALIFIED in the .dpr
#                 -> must NOT be reported (FP-9)
foreach ($u in @('App.Drift','Lib.Drift','Vcl.Legacy')) {
  Write-Ascii (Join-Path $WorkDir ("{0}.pas" -f $u)) @"
unit $u;

interface

implementation

end.
"@
}

Write-Ascii (Join-Path $WorkDir 'P.dpr') @'
program P;

uses
  App.Drift in 'App.Drift.pas',
  Legacy in 'Vcl.Legacy.pas';

begin
end.
'@

Write-Ascii (Join-Path $WorkDir 'P.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>P.dpr</MainSource>
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="App.Drift.pas"/>
        <DCCReference Include="Lib.Drift.pas"/>
        <DCCReference Include="Vcl.Legacy.pas"/>
    </ItemGroup>
</Project>
'@

$db = Join-Path $WorkDir 'p.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
$out = (& $Exe lint --project (Join-Path $WorkDir 'P.dproj') --rule unit-not-in-dpr) -join "`n"
Write-Host ''
foreach ($l in ($out -split "`n" | Select-String 'unit-not-in-dpr')) { Write-Host ("  " + $l) -ForegroundColor DarkGray }

Write-Host ''
Write-Host 'THE FIX -- a namesake in another namespace no longer satisfies the lookup' -ForegroundColor Cyan
Check 'Lib.Drift IS reported (it is in the .dproj, not the .dpr)' ($out -match 'Lib\.Drift') "out=$out"

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
Check 'App.Drift is NOT reported (it IS in the .dpr)' (-not ($out -match 'App\.Drift')) "out=$out"
Check 'FP-9: an unqualified .dpr name still matches a qualified reference' `
    (-not ($out -match 'Vcl\.Legacy')) "out=$out"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
