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
    [string] $WorkDir = "$env:TEMP\drag-lint-formsmap-$PID"
)
try {
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
# v6 (forms-csv algorithm 6): tester columns replace Navigation/Called From/PAS
# lines; every text cell is quoted; the footer sits in the 14th (Notes) column.
# Rows are parsed against the known header because ConvertFrom-Csv reads a line
# starting with '#' as a comment. Per-row cells are asserted, not substrings.
$v6Header = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes'
$rows = ($csv -split "`r`n") | Where-Object { $_ -ne '' }
Check 'column header is row 1' ($rows[0] -eq $v6Header)
$data = @($rows[1..($rows.Count - 2)] | ConvertFrom-Csv -Header ($v6Header -split ','))
function Row([string]$Form) { $data | Where-Object { $_.Form -ceq $Form } | Select-Object -First 1 }
Check 'frmMain row present'  ($null -ne (Row 'frmMain'))
Check 'frmList row present'  ($null -ne (Row 'frmList'))
Check 'frmEdit row present'  ($null -ne (Row 'frmEdit'))
Check 'data module excluded' (-not ($csv -match 'dmDemo'))
# 7 forms + 1 column-header + 1 provenance-footer = 9.
Check 'row count is 7 forms + 1 header + 1 footer' ($rows.Count -eq 9)
$algo = [regex]::Match([IO.File]::ReadAllText("$PSScriptRoot\..\..\src\forms\DRagLint.FormsMap.pas"), "FORMS_CSV_ALGORITHM\s*=\s*'(\d+)'").Groups[1].Value
Check 'provenance is footer (last row, in Notes col)' ($algo -ne '' -and $rows[-1] -match ('^,{13}"# forms-csv algorithm v' + $algo + ' '))
Check 'frmMain is root'               ((Row 'frmMain').'How to open' -eq 'Main form (opens at startup)')
Check 'frmList via Lists'             ((Row 'frmList').'How to open' -eq 'Lists')
Check 'frmEdit via Lists > Edit Item' ((Row 'frmEdit').'How to open' -eq 'Lists -> in frmList: Edit Item')
Check 'frmChild via named ctor'       ((Row 'frmChild').'How to open' -eq 'Lists -> in frmList: Open Child')
Check 'action-bound caption (Reports)' ((Row 'frmReports').'How to open' -eq 'Reports')
Check 'action-bound handler'          ((Row 'frmReports').Handler -eq 'TfrmMain.actReportsExecute')
Check 'keep-the-gap: handler-only'    ((Row 'frmGap').'How to open' -eq '(no control: TfrmMain.OpenGap)' -and (Row 'frmGap').Confidence -eq 'handler-only')
Check 'frmList opened by helper'      ((Row 'frmList').'Opened by' -eq 'TfrmMain.OpenLists')
Check 'unreachable form'              ((Row 'frmLonely').'How to open' -eq '(no path from frmMain)' -and (Row 'frmLonely').Confidence -eq 'unresolved')
Check 'traced rows say so'            ((Row 'frmEdit').Confidence -eq 'traced')
# K6: a real bound on the wall clock of the forms-csv call, replacing a literal
# $true. The fixture is 7 forms; the call is sub-second on this machine, so 60 s
# is two orders of magnitude of headroom and still fails on a genuine hang --
# earlier and with a better name than the battery's 180 s per-runner kill, which
# reports TIMEOUT for the whole runner and names no stage.
Check 'no hang: forms-csv completed within 60 s' ($swCsv.Elapsed.TotalSeconds -lt 60) `
  ("{0:N2}s" -f $swCsv.Elapsed.TotalSeconds)
# Task 7b: root regression (bootstrap procedure must not steal root)
Check 'root regression: frmMain root'            ((Row 'frmMain').'How to open' -eq 'Main form (opens at startup)')
Check 'root regression: frmEdit still reachable'  ((Row 'frmEdit').'How to open' -eq 'Lists -> in frmList: Edit Item')
# Task 7b: backup copy exclusion
Check 'backup copy excluded'  (-not ($csv -match '- Copy'))
Check 'no duplicate frmEdit'  (@($data | Where-Object { $_.Form -ceq 'frmEdit' }).Count -eq 1)

# --- v4 fixture: interface-dispatch + hook-registration navigation ---------
# Task 1 of the forms-csv v4 plan (docs/superpowers/plans/2026-07-05-forms-csv-v4-navigation-plan.md).
# Second, self-contained fixture project exercising two patterns v3 cannot
# bridge: (a) APlan.EditThing dispatched through interface IThingPlan4 to a
# concrete class's launch (Layer 1); (b) a proc-var hook registered in
# initialization (ThingHook := ShowThing4) that indirects to a launch
# (Layer 2). Uses separate variables so it never disturbs the block above.
$FixtureDir4 = "$PSScriptRoot\..\fixtures\formsmap-v4"
$WorkDir4    = "$env:TEMP\drag-lint-formsmap-v4-$PID"
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
$rows4 = ($csv4 -split "`r`n") | Where-Object { $_ -ne '' }
Check 'v4: header present' ($rows4[0] -eq $v6Header)
Check 'v4: footer/provenance line present' ($rows4[-1] -match '^,{13}"# forms-csv algorithm v')
$data4 = @($rows4[1..($rows4.Count - 2)] | ConvertFrom-Csv -Header ($v6Header -split ','))
function Row4([string]$Form) { $data4 | Where-Object { $_.Form -ceq $Form } | Select-Object -First 1 }
# These two chains cross an interface dispatch and a proc-var hook that
# call_edges cannot follow, so they are the text-scan FALLBACK's job in v6.
# Layer 1: interface-dispatch bridge (APlan.EditThing -> TDirectPlan4.EditThing -> frmDirect4)
Check 'v4: frmDirect4 via interface dispatch' ((Row4 'frmDirect4').'How to open' -eq 'Plan' -and (Row4 'frmDirect4').Notes -eq 'found by: text scan')
# Layer 1 + Layer 2: interface-dispatch + proc-var hook (APlan.EditThing -> THookPlan4.EditThing -> ThingHook() -> ShowThing4 -> frmHooked4)
Check 'v4: frmHooked4 via interface dispatch + hook' ((Row4 'frmHooked4').'How to open' -eq 'Plan' -and (Row4 'frmHooked4').'Opened by' -eq 'uHookReg4.ShowThing4')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-formsmap-$PID", "$env:TEMP\drag-lint-formsmap-v4-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
