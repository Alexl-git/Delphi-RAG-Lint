# drag-lint forms-csv v6 guard. Builds the formsmap-v6 fixture into a scratch
# DB with an EXPLICIT --db (never a live index), runs forms-csv, and asserts the
# v6 tester columns cell by cell: the menu path strings, the control, handler,
# launching routine, modality, the precondition hint, the other-ways count and
# the Confidence value of every row.
#
# The fixture covers: a nested TMainMenu item -> handler -> standalone helper
# -> TForm.Create/ShowModal (traced through call_edges); a TAction-driven button
# on a tab sheet; a handler bound to TWO controls (other ways in = 1); a
# two-hop path; a handler assigned only in code (handler-only); and a form
# nothing opens (unresolved).
#
# R1 (2026-10-06) adds: a popup form declared in the project's
# _D-RAG\drag-lint-project.json ("popupForms", written into a scratch COPY of
# the fixture so the repo carries no _D-RAG folder); one Modal case per cause
# the index can answer -- Create and ShowModal on different lines in a routine
# only the text scan reaches (interface dispatch), an MDI child and a
# Visible = True form created without a Show (read from the .dfm), a form shown
# through its own method (F.Execute -> ShowModal) -- plus a form that stays '?'
# WITH its reason; and the Before-you-start content: a guard message the
# handler stops with, and the hints of EVERY hop of a two-hop path.
#
# Cannot pass vacuously: the row count, the exact header and every asserted
# cell come from a PARSED csv; a missing row makes its cells $null and fails,
# and the positive control below asserts a cell that only v6 can produce.
#
# Usage: pwsh -File tests/autotest/run_forms_csv_v6.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap-v6",
    [string] $WorkDir    = "$env:TEMP\drag-lint-forms-csv-v6-$PID"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$db  = "$WorkDir\fixture6.sqlite"
$out = "$WorkDir\forms6.csv"

# R1: the popup-form declaration is project data, read from the project's own
# _D-RAG\drag-lint-project.json. Work on a copy so the fixture stays clean.
$fx = "$WorkDir\fx"
Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $fx -Recurse
New-Item -ItemType Directory "$fx\_D-RAG" | Out-Null
$popupJson = '{ "ownRoots": ["."], "popupForms": [ { "form": "frmPopup6", "note": "popup via TPopupHost6 (right-click a grid > Layout)" } ] }'
[IO.File]::WriteAllText("$fx\_D-RAG\drag-lint-project.json", $popupJson)

# No project name may remain hard-coded in the engine's forms units.
$srcForms = "$PSScriptRoot\..\..\src\forms"
$hard = @(Get-ChildItem -LiteralPath $srcForms -Filter '*.pas' | Select-String -Pattern 'frmgridlayout|TGridMenuPopup|KnownPopupForms')
Check 'no hard-coded popup form in src\forms' ($hard.Count -eq 0) (($hard | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ' ')

& $Exe index $fx --db $db 2>&1 | Out-Null
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0)
& $Exe forms-csv --project "$fx\Demo6.dproj" --db $db --output $out 2>&1 | Out-Null
Check 'forms-csv exits 0' ($LASTEXITCODE -eq 0)
Check 'csv exists' (Test-Path $out)

$raw = [IO.File]::ReadAllText($out)
Check 'rows are CRLF-terminated' ($raw.EndsWith("`r`n") -and -not ($raw -match "[^`r]`n"))
$lines = @($raw -split "`r`n" | Where-Object { $_ -ne '' })
$header = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes'
Check 'v6 header is row 1' ($lines[0] -ceq $header) $lines[0]
Check 'footer names algorithm v6' ($lines[-1] -match '^,{13}"# forms-csv algorithm v6 \|') $lines[-1]

# ConvertFrom-Csv skips a line starting with '#' as a comment, so the header
# row cannot be its own header; parse the data rows against the known names.
$rows = @($lines[1..($lines.Count - 2)] | ConvertFrom-Csv -Header ($header -split ','))
Check '14 data rows' ($rows.Count -eq 14) "got $($rows.Count)"
function RowOf([string]$Form) { $rows | Where-Object { $_.Form -ceq $Form } | Select-Object -First 1 }

# Root form.
$r = RowOf 'frmMain6'
Cell $r 'How to open'   'Main form (opens at startup)' 'frmMain6'
Cell $r 'Confidence'    'traced'                        'frmMain6'

# Nested main menu -> handler -> standalone helper -> Create + ShowModal.
$r = RowOf 'frmGroups6'
Cell $r 'Unit'          'uGroups6'                                   'frmGroups6'
Cell $r 'How to open'   'Main menu: Setup > Groups > Assign Groups'  'frmGroups6'
Cell $r 'Click'         'Assign Groups'                              'frmGroups6'
Cell $r 'Control type'  'TMenuItem'                                  'frmGroups6'
Cell $r 'Handler'       'TfrmMain6.mnuAssignGroupsClick'             'frmGroups6'
Cell $r 'Opened by'     'uHelpers6.OpenAssignGroups'                 'frmGroups6'
Cell $r 'Modal'         'Yes'                                        'frmGroups6'
Cell $r 'Before you start' 'frmMain6: select a row in qryItems first (the handler reads qryItems.FieldByName)' 'frmGroups6'
Cell $r 'Other ways in' '0'                                          'frmGroups6'
Cell $r 'Confidence'    'traced'                                     'frmGroups6'
Cell $r 'Notes'         'found by: index'                            'frmGroups6'

# Two hops: the second hop names the form it happens on.
$r = RowOf 'frmGroupEdit6'
Cell $r 'How to open'   'Main menu: Setup > Groups > Assign Groups -> in frmGroups6: Edit Group' 'frmGroupEdit6'
Cell $r 'Click'         'Edit Group'                     'frmGroupEdit6'
Cell $r 'Control type'  'TButton'                        'frmGroupEdit6'
Cell $r 'Handler'       'TfrmGroups6.btnEditGroupClick'  'frmGroupEdit6'
Cell $r 'Confidence'    'traced'                         'frmGroupEdit6'
# R1 Before you start: the tester walks the WHOLE path, so every hop's
# precondition is listed in hop order, not only the last one.
Cell $r 'Before you start' 'frmMain6: select a row in qryItems first (the handler reads qryItems.FieldByName); frmGroups6: select an item in lbGroups first (the handler reads lbGroups.ItemIndex)' 'frmGroupEdit6'

# One handler, two controls: the menu is shown, the tab button is the other way.
$r = RowOf 'frmEdit6'
Cell $r 'How to open'      'Main menu: Edit > Edit Item'   'frmEdit6'
Cell $r 'Click'            'Edit Item'                     'frmEdit6'
Cell $r 'Handler'          'TfrmMain6.btnEditItemClick'    'frmEdit6'
Cell $r 'Opened by'        'TfrmMain6.btnEditItemClick'    'frmEdit6'
Cell $r 'Modal'            'Yes'                           'frmEdit6'
Cell $r 'Before you start' 'frmMain6: select a row in qryItems first (the handler reads qryItems.FieldByName)' 'frmEdit6'
Cell $r 'Other ways in'    '1'                             'frmEdit6'
Cell $r 'Confidence'       'traced'                        'frmEdit6'
Cell $r 'Notes'            "found by: index; also: Tab 'Data' > Edit Item" 'frmEdit6'

# TAction-driven button on a tab sheet; non-modal Show.
$r = RowOf 'frmReports6'
Cell $r 'How to open'   "Tab 'Reports' > Run Reports"     'frmReports6'
Cell $r 'Click'         'Run Reports'                     'frmReports6'
Cell $r 'Control type'  'TButton'                         'frmReports6'
Cell $r 'Handler'       'TfrmMain6.actReportsExecute'     'frmReports6'
Cell $r 'Modal'         'No'                              'frmReports6'
Cell $r 'Confidence'    'traced'                          'frmReports6'

# An action no control shows, run from code (actOpenLog.Execute in a list-box
# double-click): the double-click handler is the way in, not the action.
$r = RowOf 'frmLog6'
Cell $r 'How to open'   'Main menu: Setup > Groups > Assign Groups -> in frmGroups6: [lbGroups] (double-click)' 'frmLog6'
Cell $r 'Click'         '[lbGroups] (double-click)'        'frmLog6'
Cell $r 'Control type'  'TListBox'                         'frmLog6'
Cell $r 'Handler'       'TfrmGroups6.lbGroupsDblClick'     'frmLog6'
Cell $r 'Opened by'     'TfrmGroups6.actOpenLogExecute'    'frmLog6'
Cell $r 'Modal'         'No'                               'frmLog6'
Cell $r 'Confidence'    'traced'                           'frmLog6'

# Handler assigned in code only: the routine is known, no control is.
$r = RowOf 'frmNag6'
Cell $r 'How to open'   '(no control: TfrmMain6.DoNagTimer)' 'frmNag6'
Cell $r 'Click'         ''                                   'frmNag6'
Cell $r 'Handler'       'TfrmMain6.DoNagTimer'               'frmNag6'
Cell $r 'Modal'         'Yes'                                'frmNag6'
Cell $r 'Confidence'    'handler-only'                       'frmNag6'
Cell $r 'Notes'         'found by: index; DoNagTimer is not bound to any control in uMain6.dfm (assigned in code?)' 'frmNag6'

# Nothing opens it.
$r = RowOf 'frmLonely6'
Cell $r 'How to open'   '(no path from frmMain6)'                  'frmLonely6'
Cell $r 'Confidence'    'unresolved'                               'frmLonely6'
Cell $r 'Notes'         'no caller found (index or text scan)'     'frmLonely6'

# R1 popup form: declared in _D-RAG\drag-lint-project.json, nothing in code.
$r = RowOf 'frmPopup6'
Cell $r 'Confidence'    'unresolved'                                           'frmPopup6'
Cell $r 'Notes'         'popup via TPopupHost6 (right-click a grid > Layout)'  'frmPopup6'

# R1 Modal cause A: Create and ShowModal on different lines, in a view-model
# routine reached only by the text scan (interface dispatch). Its guard
# message is a Before-you-start item even though the edge is a text edge.
$r = RowOf 'frmImport6'
Cell $r 'How to open'      "Tab 'More' > Import"          'frmImport6'
Cell $r 'Handler'          'TfrmMain6.btnImportClick'     'frmImport6'
Cell $r 'Opened by'        'TImportVM6.OpenImport'        'frmImport6'
Cell $r 'Modal'            'Yes'                          'frmImport6'
Cell $r 'Before you start' 'frmMain6: it refuses with "Connect to a source first" until that is set up' 'frmImport6'
Cell $r 'Notes'            'found by: text scan'          'frmImport6'

# R1 Modal cause B: an MDI child is shown on creation and cannot be modal.
$r = RowOf 'frmMdi6'
Cell $r 'Modal'         'No'                                                       'frmMdi6'
Cell $r 'Notes'         'found by: index; modal from uMdi6.dfm: FormStyle = fsMDIChild' 'frmMdi6'

# R1 Modal cause C: Visible = True in the .dfm, created without a Show.
$r = RowOf 'frmPanel6'
Cell $r 'Modal'         'No'                                                  'frmPanel6'
Cell $r 'Notes'         'found by: index; modal from uPanel6.dfm: Visible = True' 'frmPanel6'

# R1 Modal cause D: shown through a method of the form (F.Execute -> ShowModal),
# and a guard the handler raises is the tester's precondition.
$r = RowOf 'frmSerial6'
Cell $r 'Opened by'        'TfrmMain6.btnSerialClick'     'frmSerial6'
Cell $r 'Modal'            'Yes'                          'frmSerial6'
Cell $r 'Before you start' 'frmMain6: it refuses with "Add an item before defining serial numbers" until that is set up' 'frmSerial6'
Cell $r 'Notes'            'found by: index'              'frmSerial6'

# R1 undetermined: created into a field and shown elsewhere -- stays '?' and
# says why, never a guess.
$r = RowOf 'frmCache6'
Cell $r 'Modal'         '?'                                   'frmCache6'
Cell $r 'Notes'         'found by: index; modal unknown: TfrmMain6.btnCacheClick creates frmCache6 but does not show it there' 'frmCache6'
Check 'no row says ? without a reason' (@($rows | Where-Object { $_.Modal -ceq '?' -and $_.Notes -notmatch 'modal unknown: ' }).Count -eq 0)

# Positive control: the tester-result column exists and is blank on every row,
# and at least one row carries a v6-only multi-level menu path -- a v5 CSV
# (caption-only Navigation) cannot satisfy this.
Check 'positive control: Tester result blank on all rows' (@($rows | Where-Object { $_.'Tester result' -ne '' }).Count -eq 0 -and $rows.Count -gt 0)
Check 'positive control: a nested menu path is present' (@($rows | Where-Object { $_.'How to open' -like 'Main menu: * > * > *' }).Count -ge 1)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath "$env:TEMP\drag-lint-forms-csv-v6-$PID") { Remove-Item -LiteralPath "$env:TEMP\drag-lint-forms-csv-v6-$PID" -Recurse -Force -ErrorAction SilentlyContinue }
}
