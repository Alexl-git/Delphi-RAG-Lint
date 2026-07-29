# drag-lint forms-csv smoke test. Builds a tiny fixture project, indexes it,
# runs forms-csv, and asserts the navigation CSV content.
#
# Usage: pwsh -File tests/autotest/run_formsmap.ps1 [-Exe <path>]
#
# Exe target -- register item E8, fixed by T3k. This runner defaulted to
# src\cli\Win32\Debug\drag-lint.exe, which build\build_draglint_win64.bat (the
# canonical build for this work) never refreshes. It was therefore GREEN against
# a hand-built Win32 exe that predated weeks of Win64-built change: not failing,
# NOT MEASURING. That manufactured a false finding -- T3i mutated FormsMap,
# rebuilt Win64, watched this runner stay green, and concluded the check was
# toothless (register E6, later disproved by data-level reproduction).
# Same ruling as run_smoke.ps1 (v0.86 policy, user 2026-07-05): the Win64 CLI is
# the artifact the product ships, so that is what the battery must test. Pass
# -Exe explicitly to run against a Win32 build on purpose.
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap",
    [string] $WorkDir = "$env:TEMP\drag-lint-formsmap"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$db  = "$WorkDir\fixture.sqlite"
$out = "$WorkDir\forms.csv"
& $Exe index $FixtureDir --db $db 2>&1 | Out-Null
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0)
# K6: this call is timed so the 'no hang' check below can be an ASSERTION. It
# used to be `Check 'no hang (script completed)' ($true)` -- a tautology that
# could never fail, inflating this runner's check total by one while measuring
# nothing. Reaching the line already proved the script had not hung; the literal
# $true proved nothing at all.
$swCsv = [System.Diagnostics.Stopwatch]::StartNew()
& $Exe forms-csv --project "$FixtureDir\Demo.dproj" --db $db --out $out 2>&1 | Out-Null
$swCsv.Stop()
Check 'forms-csv exits 0' ($LASTEXITCODE -eq 0)
Check 'csv exists' (Test-Path $out)
$csv = Get-Content $out -Raw
Check 'header present' ($csv -match '#,Unit,FormName,PAS lines,Navigation,Called From,Notes')
$rows = ($csv -split "`r`n") | Where-Object { $_ -ne '' }
Check 'frmMain row present'  ($csv -match 'uDemoMain,frmMain,')
Check 'frmList row present'  ($csv -match 'uDemoList,frmList,')
Check 'frmEdit row present'  ($csv -match 'uDemoEdit,frmEdit,')
Check 'data module excluded' (-not ($csv -match 'dmDemo'))
Check 'pas line count for frmEdit' ($csv -match 'uDemoEdit,frmEdit,16,')
# v2 (9a81345): output gained a '# forms-csv algorithm v...' provenance line.
# v0.86 (header move): the column header is now row 1 and the provenance line is
# the FOOTER (padded with 6 leading commas into the Notes column). Total lines
# unchanged: 7 forms + 1 column-header + 1 provenance-footer = 9.
Check 'row count is 7 forms + 1 header + 1 footer' ($rows.Count -eq 9)
Check 'column header is row 1' ($rows[0] -eq '#,Unit,FormName,PAS lines,Navigation,Called From,Notes')
Check 'provenance is footer (last row, in Notes col)' ($rows[-1] -match '^,,,,,,"?# forms-csv algorithm v')
Check 'frmMain is root (blank nav)'   ($csv -match "uDemoMain,frmMain,\d+,,")
Check 'frmList nav via Lists'         ($csv -match "uDemoList,frmList,\d+,frmMain -> 'Lists' -> frmList,")
Check 'frmEdit nav via Lists>Edit'    ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> frmList -> 'Edit Item' -> frmEdit,")
Check 'frmChild nav via named ctor'   ($csv -match "uDemoChild,frmChild,\d+,frmMain -> 'Lists' -> frmList -> 'Open Child' -> frmChild,")
Check 'action-bound caption (Reports)' ($csv -match "uDemoReports,frmReports,\d+,frmMain -> 'Reports' -> frmReports,")
Check 'keep-the-gap via routine'       ($csv -match "uDemoGap,frmGap,\d+,frmMain -> \(via [^)]+\) -> frmGap,")
Check 'nav interleaves landing forms'  ($csv -match "-> 'Lists' -> frmList -> 'Edit Item' ->")
Check 'unreachable form'               ($csv -match 'uDemoUnreached,frmLonely,\d+,\(no path from MAIN\),')
# v2 (9a81345): standalone-function call sites (Demo.RunAdminBootstrap) are also
# listed as callers, so frmList need not be first in the Called From field.
Check 'called-from for frmEdit'        ($csv -match "uDemoEdit,frmEdit,\d+,[^,]*,[^,]*frmList")
# K6: a real bound on the wall clock of the forms-csv call, replacing a literal
# $true. The fixture is 7 forms; the call is sub-second on this machine, so 60 s
# is two orders of magnitude of headroom and still fails on a genuine hang --
# earlier and with a better name than the battery's 180 s per-runner kill, which
# reports TIMEOUT for the whole runner and names no stage.
Check 'no hang: forms-csv completed within 60 s' ($swCsv.Elapsed.TotalSeconds -lt 60) `
  ("{0:N2}s" -f $swCsv.Elapsed.TotalSeconds)
# Task 7b: root regression (bootstrap procedure must not steal root)
Check 'root regression: frmMain root (blank nav)' ($csv -match "uDemoMain,frmMain,\d+,,")
Check 'root regression: frmEdit still reachable'  ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> frmList -> 'Edit Item' -> frmEdit,")
# Task 7b: backup copy exclusion
Check 'backup copy excluded'  (-not ($csv -match '- Copy'))
Check 'no duplicate frmEdit'  ((($csv -split "`r`n") | Select-String ',frmEdit,').Count -eq 1)

# --- v4 fixture: interface-dispatch + hook-registration navigation ---------
# Task 1 of the forms-csv v4 plan (docs/superpowers/plans/2026-07-05-forms-csv-v4-navigation-plan.md).
# Second, self-contained fixture project exercising two patterns v3 cannot
# bridge: (a) APlan.EditThing dispatched through interface IThingPlan4 to a
# concrete class's launch (Layer 1); (b) a proc-var hook registered in
# initialization (ThingHook := ShowThing4) that indirects to a launch
# (Layer 2). Uses separate variables so it never disturbs the block above.
$FixtureDir4 = "$PSScriptRoot\..\fixtures\formsmap-v4"
$WorkDir4    = "$env:TEMP\drag-lint-formsmap-v4"
if (Test-Path $WorkDir4) { Remove-Item -Recurse -Force $WorkDir4 }
New-Item -ItemType Directory $WorkDir4 | Out-Null
$db4  = "$WorkDir4\fixture4.sqlite"
$out4 = "$WorkDir4\forms4.csv"
& $Exe index $FixtureDir4 --db $db4 2>&1 | Out-Null
Check 'v4: index fixture exits 0' ($LASTEXITCODE -eq 0)
& $Exe forms-csv --project "$FixtureDir4\Demo4.dproj" --db $db4 --out $out4 2>&1 | Out-Null
Check 'v4: forms-csv exits 0' ($LASTEXITCODE -eq 0)
Check 'v4: csv exists' (Test-Path $out4)
$csv4 = Get-Content $out4 -Raw
Check 'v4: header present' ($csv4 -match '#,Unit,FormName,PAS lines,Navigation,Called From,Notes')
$rows4 = ($csv4 -split "`r`n") | Where-Object { $_ -ne '' }
Check 'v4: footer/provenance line present' ($rows4[-1] -match '^,,,,,,"?# forms-csv algorithm v')
# Layer 1: interface-dispatch bridge (APlan.EditThing -> TDirectPlan4.EditThing -> frmDirect4)
Check 'v4: frmDirect4 nav via interface dispatch' ($csv4 -match "uDirect4,frmDirect4,\d+,frmRoot4 -> 'Plan' -> frmDirect4,")
# Layer 1 + Layer 2: interface-dispatch + proc-var hook (APlan.EditThing -> THookPlan4.EditThing -> ThingHook() -> ShowThing4 -> frmHooked4)
Check 'v4: frmHooked4 nav via interface dispatch + hook' ($csv4 -match "uHooked4,frmHooked4,\d+,frmRoot4 -> 'Plan' -> frmHooked4,")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
