# Guard: `reconcile-project --apply` must NEVER splice a {$I} include into a
# uses clause -- and must still add the units that genuinely belong there.
#
# THE DEFECT (docs\PLAN-SESSION-81.md section 4, filed as
# INBOX-reconcile-apply-would-splice-inc-files-into-uses.md). The compile
# closure carries .pas AND .inc -- Index.Closure.pas:1010 keeps an include in
# Files on purpose ("don't recurse into .inc for uses, just leave it in Files").
# Index.Reconcile Step 3 then builds the MISSING list straight off that closure
# with NO extension filter, taking TPath.GetFileNameWithoutExtension as the unit
# name. So an include arrived at the writer looking exactly like a missing unit,
# and --apply would have emitted:
#
#     uses ..., QDefs;
#
# which does not compile. The project file is the one artifact a developer
# cannot easily reconstruct, and --apply rewrites it in place.
#
# THE FIX IS "REFUSE IN THE WRITE, KEEP IN THE REPORT", per the owner's stated
# preference: loud over silent. The filter sits at the single point that feeds
# BOTH editors, so the .dpr and the .dproj cannot disagree about what a member
# is, and the refused paths are returned so the reported MISSING count and the
# written count differ for a STATED reason.
#
# CHECK 2 IS THE POSITIVE CONTROL AND IT IS NOT OPTIONAL. An over-broad filter
# -- or one applied to the wrong list -- would refuse everything and still pass
# a test that only asserted "the .inc was not written". App.Helper is a genuine
# missing UNIT in the same run: it MUST still be added. Without this, disabling
# --apply entirely would read as a clean pass.
#
# RED-CHECK -- ACTUALLY RUN, 2026-09-08, against the deployed 19:46 build which
# predates the fix. Measured signature: 1 FAIL, 2 PASS, 3 FAIL, 3b FAIL,
# 4 PASS, 5 PASS. The .dpr it produced is the defect verbatim, and it is NOT
# the shape the INBOX note predicted (`uses ..., QDefs;`) -- the writer emits a
# full member entry, `in` clause and all:
#
#     uses
#       App.Core in 'App.Core.pas',
#       App.Helper in 'App.Helper.pas',
#       QDefs in 'QDefs.inc';
#
# Check 3b was TIGHTENED because of this run: as first written it matched a
# bare 'QDefs', which is present in the same document's `missing` array, so it
# PASSED against the unfixed build -- a check that could not fail. This repo
# has three recorded instances of exactly that. Do not skip the red run.
#
# Usage: pwsh -File tests/autotest/run_reconcile_apply_refuses_inc_files.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-reconcile-inc"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1}" -f $status, $Name) -ForegroundColor $color
    if (-not $Ok -and $Detail) { Write-Host ("      " + $Detail) -ForegroundColor DarkGray }
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

# Closure:  Q.dpr -> App.Core -> {$I QDefs.inc} and -> App.Helper
# Members:  Q.dpr + App.Core only.
# So MISSING = { QDefs.inc (refuse), App.Helper.pas (add) } -- one of each,
# which is what lets checks 1 and 2 discriminate a correct filter from a
# blanket one.
Write-Ascii (Join-Path $WorkDir 'QDefs.inc') @'
{ deliberate: an include file, not a unit }
'@

Write-Ascii (Join-Path $WorkDir 'App.Helper.pas') @'
unit App.Helper;

interface

implementation

end.
'@

Write-Ascii (Join-Path $WorkDir 'App.Core.pas') @'
unit App.Core;

{$I QDefs.inc}

interface

uses
  App.Helper;

implementation

end.
'@

Write-Ascii (Join-Path $WorkDir 'Q.dpr') @'
program Q;

uses
  App.Core in 'App.Core.pas';

begin
end.
'@

Write-Ascii (Join-Path $WorkDir 'Q.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>Q.dpr</MainSource>
    </PropertyGroup>
    <ItemGroup>
        <DCCReference Include="App.Core.pas"/>
    </ItemGroup>
</Project>
'@

$dproj = Join-Path $WorkDir 'Q.dproj'
$dpr   = Join-Path $WorkDir 'Q.dpr'

# Dry run FIRST -- the report must still SHOW the include (kept in the report).
$report = (& $Exe reconcile-project $dproj --json 2>&1) -join "`n"

# Then the write.
$applyOut = (& $Exe reconcile-project $dproj --apply --json 2>&1) -join "`n"
$dprAfter = [System.IO.File]::ReadAllText($dpr)

Write-Host ''
Write-Host 'THE FIX -- an include is never written into a uses clause' -ForegroundColor Cyan
Check '1. the .dpr uses clause does NOT contain QDefs' `
    (-not ($dprAfter -match '(?m)^\s*QDefs\b') -and -not ($dprAfter -match 'QDefs\s+in\s')) `
    "dpr after apply:`n$dprAfter"

Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
# POSITIVE CONTROL. A genuine missing UNIT in the same run must still be added,
# or an over-broad filter would pass check 1 by writing nothing at all.
Check '2. positive control: the genuine missing unit App.Helper IS added' `
    ($dprAfter -match 'App\.Helper') "dpr after apply:`n$dprAfter"

# The refusal is NAMED, not silent -- the reported/written difference must be
# explainable from the output alone.
Check '3. --apply names the refusal (`refused` in JSON)' `
    ($applyOut -match 'refused') "applyOut=$applyOut"
# SCOPED TO THE REFUSAL. A bare `-match 'QDefs'` passes on the unfixed build --
# QDefs is in the `missing` array of the very same document -- so it would have
# been a check that could not fail. It must co-occur with the refusal itself.
Check '3b. the refusal names the include specifically' `
    ($applyOut -match '"refused"[\s\S]{0,300}QDefs') "applyOut=$applyOut"

# KEPT IN THE REPORT, not filtered out of it -- the dry run is the review
# surface and must still show everything the closure pulled in.
Check '4. the dry-run report still lists QDefs under missing' `
    ($report -match 'QDefs') "report=$report"

# The .dpr must remain parseable enough that a re-run is stable: reconciling
# again must not re-offer App.Helper (it is now listed) and must not have
# corrupted the clause.
$report2 = (& $Exe reconcile-project $dproj --json 2>&1) -join "`n"
Check '5. re-running no longer reports App.Helper as missing' `
    (-not ($report2 -match '"unit"\s*:\s*"App\.Helper"')) "report2=$report2"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
