# drag-lint forms-csv smoke test. Builds a tiny fixture project, indexes it,
# runs forms-csv, and asserts the navigation CSV content.
#
# Usage: pwsh -File tests/autotest/run_formsmap.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\src\cli\Win32\Debug\drag-lint.exe",
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
& $Exe forms-csv --project "$FixtureDir\Demo.dproj" --db $db --out $out 2>&1 | Out-Null
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
Check 'row count is 7 forms + header' ($rows.Count -eq 8)
Check 'frmMain is root (blank nav)'   ($csv -match "uDemoMain,frmMain,\d+,,")
Check 'frmList nav via Lists'         ($csv -match "uDemoList,frmList,\d+,frmMain -> 'Lists',")
Check 'frmEdit nav via Lists>Edit'    ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> 'Edit Item',")
Check 'frmChild nav via named ctor'   ($csv -match "uDemoChild,frmChild,\d+,frmMain -> 'Lists' -> 'Open Child',")
Check 'action-bound caption (Reports)' ($csv -match "uDemoReports,frmReports,\d+,frmMain -> 'Reports',")
Check 'keep-the-gap via routine'       ($csv -match "uDemoGap,frmGap,\d+,frmMain -> \(via ")
Check 'unreachable form'               ($csv -match 'uDemoUnreached,frmLonely,\d+,\(no path from MAIN\),')
Check 'called-from for frmEdit'        ($csv -match "uDemoEdit,frmEdit,\d+,[^,]*,frmList")
Check 'no hang (script completed)'     ($true)
# Task 7b: root regression (bootstrap procedure must not steal root)
Check 'root regression: frmMain root (blank nav)' ($csv -match "uDemoMain,frmMain,\d+,,")
Check 'root regression: frmEdit still reachable'  ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> 'Edit Item',")
# Task 7b: backup copy exclusion
Check 'backup copy excluded'  (-not ($csv -match '- Copy'))
Check 'no duplicate frmEdit'  ((($csv -split "`r`n") | Select-String ',frmEdit,').Count -eq 1)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
