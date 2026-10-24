# drag-lint forms-csv v8 guard: code-added menu items (menu-tree external
# roots) are merged into the form's .dfm menu tree, so "How to open" names the
# code-built item and its handler feeds the launch trace.
#
# Fixture tests\fixtures\formsmap-v8: frmMain8's .dfm declares mnuMain > mnuTools
# with one design-time child; FormCreate adds a direct item, an item through
# a helper in another unit (the parent arrives as a PARAMETER), and a submenu
# with a child. frmSide8's .dfm has ANOTHER item named mnuTools that gains its
# own code item -- the two must not merge.
#
# Cannot pass vacuously: every cell comes from a PARSED csv / JSON; a missing
# row or root makes the value $null and fails. Positive control: the
# code-added rows are asserted with cells only v8 can produce (v7 printed
# "(no control: ...)" for each of them), and the design-time row is asserted
# too so a graft that REPLACES the .dfm children fails.
#
# Usage: pwsh -File tests/autotest/run_forms_csv_v8.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap-v8",
    [string] $WorkDir    = "$env:TEMP\drag-lint-forms-csv-v8-$PID"
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
$db  = "$WorkDir\fixture8.sqlite"
$out = "$WorkDir\forms8.csv"
$fx  = "$WorkDir\fx"
Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $fx -Recurse
New-Item -ItemType Directory "$fx\_D-RAG" | Out-Null
[IO.File]::WriteAllText("$fx\_D-RAG\drag-lint-project.json", '{ "ownRoots": ["."] }')

& $Exe index $fx --db $db 2>&1 | Out-Null
Check 'index fixture exits 0' ($LASTEXITCODE -eq 0)

# --- menu-tree: the external roots forms-csv consumes ---------------------
$json = (& $Exe menu-tree --project "$fx\Demo8.dproj" --db $db --format json 2>$null) -join "`n"
Check 'menu-tree exits 0' ($LASTEXITCODE -eq 0)
$tree = $json | ConvertFrom-Json
$ext  = @($tree.external)
Check 'two external roots named mnuTools (one per form, not merged)' ((@($ext | Where-Object { $_.ident -ceq 'mnuTools' })).Count -eq 2) "got $($ext.Count): $(($ext | ForEach-Object { "$($_.ident)@$($_.identPath)" }) -join ', ')"
$mainExt = $ext | Where-Object { $_.identPath -like '*\uMain8.pas' } | Select-Object -First 1
$sideExt = $ext | Where-Object { $_.identPath -like '*\uSide8.pas' } | Select-Object -First 1
$mainCaps = @($mainExt.children | ForEach-Object { $_.caption })
Check 'main mnuTools: Code &Reports, Helper Export, More' (($mainCaps -join '|') -ceq 'Code &Reports|Helper Export|More') ($mainCaps -join '|')
$helper = @($mainExt.children | Where-Object { $_.caption -ceq 'Helper Export' }) | Select-Object -First 1
Check 'helper item: handler bound at the call site' ($null -ne $helper -and $helper.handler -ceq 'uMain8.TfrmMain8.mnuHelperExportClick') "got [$($helper.handler)]"
Check 'no external root named after the helper parameter' (@($ext | Where-Object { $_.ident -ceq 'pParent' }).Count -eq 0)
$sideCaps = @($sideExt.children | ForEach-Object { $_.caption })
Check 'side mnuTools: only Side Code' (($sideCaps -join '|') -ceq 'Side Code') ($sideCaps -join '|')

# --- forms-csv v8: code-added items in "How to open" ----------------------
& $Exe forms-csv --project "$fx\Demo8.dproj" --db $db --output $out 2>&1 | Out-Null
Check 'forms-csv exits 0' ($LASTEXITCODE -eq 0)
$raw = [IO.File]::ReadAllText($out)
$lines = @($raw -split "`r`n" | Where-Object { $_ -ne '' })
$header = '#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes'
Check 'header is row 1' ($lines[0] -ceq $header) $lines[0]
Check 'footer names algorithm v8' ($lines[-1] -match '^,{13}"# forms-csv algorithm v8 \|') $lines[-1]
$rows = @($lines[1..($lines.Count - 2)] | ConvertFrom-Csv -Header ($header -split ','))
Check '7 data rows' ($rows.Count -eq 7) "got $($rows.Count)"
function RowOf([string]$Form) { $rows | Where-Object { $_.Form -ceq $Form } | Select-Object -First 1 }

# Design-time item: unchanged by the graft.
$r = RowOf 'frmDesign8'
Cell $r 'How to open'  'Main menu: Tools > Design Item' 'frmDesign8'
Cell $r 'Handler'      'TfrmMain8.mnuDesignClick'       'frmDesign8'

# Direct code item (accelerator stripped as for a .dfm caption).
$r = RowOf 'frmReports8'
Cell $r 'How to open'  'Main menu: Tools > Code Reports'    'frmReports8'
Cell $r 'Click'        'Code Reports'                       'frmReports8'
Cell $r 'Control type' 'TMenuItem'                          'frmReports8'
Cell $r 'Handler'      'TfrmMain8.mnuCodeReportsClick'      'frmReports8'
Cell $r 'Opened by'    'TfrmMain8.mnuCodeReportsClick'      'frmReports8'
Cell $r 'Confidence'   'traced'                             'frmReports8'

# Item added by a helper in another unit, parent passed in.
$r = RowOf 'frmExport8'
Cell $r 'How to open'  'Main menu: Tools > Helper Export'   'frmExport8'
Cell $r 'Handler'      'TfrmMain8.mnuHelperExportClick'     'frmExport8'
Cell $r 'Confidence'   'traced'                             'frmExport8'

# Code submenu under the .dfm item.
$r = RowOf 'frmDeep8'
Cell $r 'How to open'  'Main menu: Tools > More > Deep Item' 'frmDeep8'
Cell $r 'Confidence'   'traced'                              'frmDeep8'

# Second form: its own mnuTools, its own code item, reached in two hops.
$r = RowOf 'frmSideChild8'
Cell $r 'How to open'  'Side -> in frmSide8: Main menu: Side Tools > Side Code' 'frmSideChild8'
Cell $r 'Handler'      'TfrmSide8.mnuSideCodeClick'                             'frmSideChild8'

if ($script:Failed) { Write-Host 'forms-csv v8 guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'forms-csv v8 guard: PASS' -ForegroundColor Green
exit 0
}
catch {
    Write-Host "GUARD BROKEN: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
