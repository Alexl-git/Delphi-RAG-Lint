# drag-lint menu-tree guard (code-built menu reader, spec
# docs\superpowers\specs\2026-10-23-code-built-menu-reader-design.md section 5).
#
# Indexes a scratch COPY of tests\fixtures\menutree with an explicit --db (never
# a live index), runs `menu-tree --format paths` and compares every row with
# the hand-written golden expected-paths.txt CELL BY CELL (path, handler,
# confidence; the file:line column is not pinned). Also: --format json parses
# with schema menu-tree/1; no --db -> exit 2 with "menu-tree: need --db"; a
# fixture unit touched after indexing -> exit 3 (stale index refused).
#
# Cannot pass vacuously: rows come from PARSED output, a missing row compares
# as '<no row>' and fails, and the positive control feeds the same comparer a
# golden with one cell changed and requires it to report a mismatch.
#
# Usage: pwsh -File tests/autotest/run_menu_tree_guard.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\menutree",
    [string] $WorkDir    = "$env:TEMP\drag-lint-menu-tree-guard-$PID"
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
# rows as 'path|handler|confidence'; '## external <ident>' lines kept verbatim
function Get-Rows([string]$Text, [bool]$HasSource) {
    $rows = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.Trim() -eq '') { continue }
        if ($line.StartsWith('## ')) { $rows += $line.Trim(); continue }
        $c = $line -split "`t"
        if ($HasSource -and $c.Count -eq 4) { $rows += "$($c[0])|$($c[1])|$($c[3])" }
        elseif ((-not $HasSource) -and $c.Count -eq 3) { $rows += "$($c[0])|$($c[1])|$($c[2])" }
        else { $rows += "<malformed: $line>" }
    }
    return ,$rows
}
# list of mismatch descriptions ('' entries never added)
function Compare-Rows($Want, $Got) {
    $bad = @()
    if ($Want.Count -ne $Got.Count) { $bad += "row count want $($Want.Count) got $($Got.Count)" }
    for ($i = 0; $i -lt $Want.Count; $i++) {
        $g = if ($i -lt $Got.Count) { $Got[$i] } else { '<no row>' }
        if ($Want[$i] -cne $g) { $bad += "row $($i + 1): want [$($Want[$i])] got [$g]" }
    }
    return ,$bad
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$fx = "$WorkDir\fx"
Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $fx -Recurse
$proj = "$fx\MenuTreeFixture.dproj"
$db   = "$WorkDir\fixture.sqlite"
& $Exe index --project $proj --db $db *> "$WorkDir\index.log"
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: fixture index failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 2 }
$want = Get-Rows (Get-Content "$fx\expected-paths.txt" -Raw) $false
Check 'golden has rows' ($want.Count -ge 10) "($($want.Count))"

# --- paths, cell by cell ---
$paths = (& $Exe menu-tree --project $proj --db $db --format paths 2> "$WorkDir\paths.err" | Out-String)
Check 'menu-tree --format paths exits 0' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
$got = Get-Rows $paths $true
$bad = Compare-Rows $want $got
Check 'paths equal expected-paths.txt cell by cell' ($bad.Count -eq 0) (($bad | Select-Object -First 5) -join '; ')

# --- positive control: the comparer sees a one-cell change ---
$seeded = @($want)
$seeded[1] = $seeded[1] -replace '\|certain$', '|derived'
$ctl = Compare-Rows $seeded $got
Check 'positive control: a one-cell golden edit is reported' ($ctl.Count -eq 1) "($($ctl.Count) mismatch(es))"

# --- json ---
$jsonText = (& $Exe menu-tree --project $proj --db $db --format json 2> "$WorkDir\json.err" | Out-String)
$jsonExit = $LASTEXITCODE
$j = $null
try { $j = $jsonText | ConvertFrom-Json } catch { $j = $null }
Check 'menu-tree --format json exits 0 and parses' (($jsonExit -eq 0) -and ($null -ne $j)) "(exit $jsonExit)"
Check 'json schema = menu-tree/1' ($null -ne $j -and $j.schema -eq 'menu-tree/1') "(got [$($j.schema)])"
# external: TFixtureForm.mnuTools + the four MT.TwoClass field roots (TFirstMenu/TSecondMenu x FMenu/FPopup)
Check 'json: two roots, five external roots' ($null -ne $j -and @($j.roots).Count -eq 2 -and @($j.external).Count -eq 5) ''

# --- usage: no --db ---
$err = (& $Exe menu-tree --project $proj 2>&1 | Out-String)
Check 'no --db -> exit 2' ($LASTEXITCODE -eq 2) "(exit $LASTEXITCODE)"
Check 'no --db -> "menu-tree: need --db"' ($err -match 'menu-tree: need --db') ''

# --- stale: touch a fixture unit after indexing ---
Add-Content -LiteralPath "$fx\MT.Builder.pas" -Value "`r`n{ touched by run_menu_tree_guard }" -Encoding ascii
& $Exe menu-tree --project $proj --db $db --format paths *> "$WorkDir\stale.out"
Check 'touched unit -> exit 3 (stale index refused)' ($LASTEXITCODE -eq 3) "(exit $LASTEXITCODE)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL run_menu_tree_guard' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_menu_tree_guard' -ForegroundColor Green
exit 0
} catch {
    Write-Host "FAIL run_menu_tree_guard: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
