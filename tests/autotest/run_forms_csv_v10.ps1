# drag-lint forms-csv v10 guard: polymorphic launches (spec
# docs\superpowers\specs\2026-10-26-extract-polymorphic-form-launches.md, section 5).
#
#   frmA  opened by an OVERRIDE (TPlanA.EditForm) nobody calls directly; the
#         button calls FPlan.EditForm through IPlan. The index walk reaches
#         btnEdit only through dispatch_edges, and says so in Notes:
#         "via DF.Base.IPlan.EditForm (interface dispatch)".
#   frmC  opened by OpenChild(AClass: TFormClass) = AClass.Create(Self).Show,
#         passed TfrmC at btnOpenClick -- reached through classref_args.
#   frmD  passed through a VARIABLE (LCls := TfrmD; OpenChild(LCls)): no row,
#         so it stays unresolved -- the negative control.
#
# Fixture tests\fixtures\dispatch-forms (shared with run_dispatch_edges.ps1).
# Cells come from a PARSED csv; a missing row reads '<no row>' and fails.
# Positive control: under v9 frmA was "found by: text scan" with no dispatch
# note and frmC was "(no path from frmMain)" -- both cells below fail there.
#
# Usage: pwsh -File tests/autotest/run_forms_csv_v10.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\dispatch-forms",
    [string] $WorkDir    = "$env:TEMP\drag-lint-forms-csv-v10-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $status = if ($Ok) { 'PASS' } else { 'FAIL' }
    $color  = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
function Cell($Row, [string]$Col, [string]$Want, [string]$Tag) {
    $got = if ($null -eq $Row) { '<no row>' } else { [string]$Row.$Col }
    Check "$Tag $Col" ($got -ceq $Want) "want [$Want] got [$got]"
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$db  = "$WorkDir\fixture10.sqlite"
$out = "$WorkDir\forms10.csv"
$fx  = "$WorkDir\fx"
Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $fx -Recurse
New-Item -ItemType Directory "$fx\_D-RAG" | Out-Null
[IO.File]::WriteAllText("$fx\_D-RAG\drag-lint-project.json", '{ "ownRoots": ["."] }')

& $Exe index $fx --db $db 2>&1 | Out-Null
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0)
& $Exe forms-csv --project "$fx\DispatchForms.dproj" --db $db --output $out 2>&1 | Out-Null
Check 'forms-csv exits 0' ($LASTEXITCODE -eq 0)
$raw = [IO.File]::ReadAllText($out)
$lines = @($raw -split "`r`n" | Where-Object { $_ -ne '' })
$header = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes'
Check 'header is row 1' ($lines[0] -ceq $header) $lines[0]
Check 'footer names algorithm v10' ($lines[-1] -match '^,{13}"# forms-csv algorithm v10 \|') $lines[-1]
$rows = @($lines[1..($lines.Count - 2)] | ConvertFrom-Csv -Header ($header -split ','))
Check '4 data rows' ($rows.Count -eq 4) "got $($rows.Count)"
function RowOf([string]$Form) { $rows | Where-Object { $_.Form -ceq $Form } | Select-Object -First 1 }

$r = RowOf 'frmA'
Cell $r 'How to open' 'Edit Plan'                 'frmA'
Cell $r 'Handler'     'TfrmMain.btnEditClick'     'frmA'
Cell $r 'Opened by'   'TPlanA.EditForm'           'frmA'
Cell $r 'Modal'       'Yes'                       'frmA'
Cell $r 'Confidence'  'traced'                    'frmA'
$n = if ($r) { [string]$r.Notes } else { '' }
Check 'frmA Notes found by: index' ($n -match '(^|; )found by: index(;|$)') "[$n]"
Check 'frmA Notes names the dispatch hop' ($n.Contains('via DF.Base.IPlan.EditForm (interface dispatch)')) "[$n]"

$r = RowOf 'frmC'
Cell $r 'How to open' 'Open C'                    'frmC'
Cell $r 'Handler'     'TfrmMain.btnOpenClick'     'frmC'
Cell $r 'Opened by'   'TfrmMain.OpenChild'        'frmC'
Cell $r 'Modal'       'No'                        'frmC'
Cell $r 'Confidence'  'traced'                    'frmC'
$n = if ($r) { [string]$r.Notes } else { '' }
Check 'frmC Notes found by: index' ($n -match '(^|; )found by: index(;|$)') "[$n]"

$r = RowOf 'frmD'
Cell $r 'Confidence'  'unresolved'                'frmD'
Cell $r 'Handler'     ''                          'frmD'

if ($script:Failed) { Write-Host 'run_forms_csv_v10: FAIL'; exit 1 }
Write-Host 'run_forms_csv_v10: PASS'
exit 0
} catch {
    Write-Host "FATAL: $_" -ForegroundColor Red
    exit 2
}
