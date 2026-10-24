# drag-lint forms-csv v9 guard: code-added DevExpress bar links (menu-tree
# external roots: a local ItemLinks.Add link, a sub-item inserted into
# Bars[0], a helper with the popup passed in) are grafted into the form's
# .dfm bar tree, so "How to open" names the code-linked item.
#
# Fixture tests\fixtures\formsmap-v9 (shared with run_menu_tree_dxbar.ps1).
#
# Cannot pass vacuously: every cell comes from a PARSED csv; a missing row
# makes the value '<no row>' and fails. Positive control: the code-linked rows
# (frmC9, frmD9, frmE9) carry cells only v9 can produce (v8 printed
# "(no control: ...)" for them), and the .dfm-declared rows (frmA9, frmB9,
# frmF9) are asserted too, so a graft that REPLACES the .dfm links fails.
#
# Usage: pwsh -File tests/autotest/run_forms_csv_v9.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap-v9",
    [string] $WorkDir    = "$env:TEMP\drag-lint-forms-csv-v9-$PID"
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
$db  = "$WorkDir\fixture9.sqlite"
$out = "$WorkDir\forms9.csv"
$fx  = "$WorkDir\fx"
Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $fx -Recurse
New-Item -ItemType Directory "$fx\_D-RAG" | Out-Null
[IO.File]::WriteAllText("$fx\_D-RAG\drag-lint-project.json", '{ "ownRoots": ["."] }')

& $Exe index $fx --db $db 2>&1 | Out-Null
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0)

& $Exe forms-csv --project "$fx\Demo9.dproj" --db $db --output $out 2>&1 | Out-Null
Check 'forms-csv exits 0' ($LASTEXITCODE -eq 0)
$raw = [IO.File]::ReadAllText($out)
$lines = @($raw -split "`r`n" | Where-Object { $_ -ne '' })
$header = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes'
Check 'header is row 1' ($lines[0] -ceq $header) $lines[0]
Check 'footer names algorithm v9' ($lines[-1] -match '^,{13}"# forms-csv algorithm v9 \|') $lines[-1]
$rows = @($lines[1..($lines.Count - 2)] | ConvertFrom-Csv -Header ($header -split ','))
Check '7 data rows' ($rows.Count -eq 7) "got $($rows.Count)"
function RowOf([string]$Form) { $rows | Where-Object { $_.Form -ceq $Form } | Select-Object -First 1 }

# .dfm-declared: action-bound button under the main-menu bar's sub-item.
$r = RowOf 'frmA9'
Cell $r 'How to open'  'Main menu: Setup > Groups'                 'frmA9'
Cell $r 'Control type' 'TdxBarButton'                              'frmA9'
# .dfm-declared ribbon item (bar caption differs from the tab caption).
$r = RowOf 'frmB9'
Cell $r 'How to open'  'Ribbon: Lists > Lists Bar > Customer List' 'frmB9'
Cell $r 'Control type' 'TdxBarLargeButton'                         'frmB9'
# Code: a TdxBarButton linked onto barLists through a local link.
$r = RowOf 'frmC9'
Cell $r 'How to open'  'Ribbon: Lists > Lists Bar > Vendor List'   'frmC9'
Cell $r 'Click'        'Vendor List'                               'frmC9'
Cell $r 'Control type' 'TdxBarButton'                              'frmC9'
Cell $r 'Handler'      'TfrmMain9.btnVendorsClick'                 'frmC9'
Cell $r 'Confidence'   'traced'                                    'frmC9'
# Code: a sub-item inserted at 0 into Bars[0] (the IsMainMenu bar).
$r = RowOf 'frmD9'
Cell $r 'How to open'  'Main menu: Presets > Reset Presets'        'frmD9'
Cell $r 'Handler'      'TfrmMain9.btnResetClick'                   'frmD9'
# Code: helper-added button on the .dfm popup.
$r = RowOf 'frmE9'
Cell $r 'How to open'  'Right-click menu popGrid > Export Grid'    'frmE9'
Cell $r 'Handler'      'TfrmMain9.btnExportClick'                  'frmE9'
# .dfm-declared backstage button.
$r = RowOf 'frmF9'
Cell $r 'How to open'  'File menu > Exit'                          'frmF9'

if ($script:Failed) { Write-Host 'forms-csv v9 guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'forms-csv v9 guard: PASS' -ForegroundColor Green
exit 0
}
catch {
    Write-Host "GUARD BROKEN: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
