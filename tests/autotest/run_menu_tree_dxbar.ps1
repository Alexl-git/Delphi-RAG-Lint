# drag-lint menu-tree --with-dfm guard (spec docs\superpowers\specs\2026-10-24-dxbar-menus.md):
# .dfm-declared menu surfaces (DevExpress bars, ribbon tabs, backstage, bar
# popups, VCL TMainMenu / TPopupMenu) become roots, and code-added bar links
# (local link, Bars[0] insert, `with` receiver, helper with the popup passed in)
# are grafted into them.
#
# Fixture tests\fixtures\formsmap-v9 (shared with run_forms_csv_v9.ps1).
#
# Cannot pass vacuously: the paths are compared cell by cell with
# expected-paths.txt (row count included) and a one-cell golden edit must be
# reported (positive control); every JSON value comes from a PARSED document,
# so a missing root yields $null and fails. Positive control for the flag:
# WITHOUT --with-dfm the code links stay external roots (popGrid, barLists),
# so a graft that ignored the flag would fail here.
#
# Usage: pwsh -File tests/autotest/run_menu_tree_dxbar.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap-v9",
    [string] $WorkDir    = "$env:TEMP\drag-lint-menu-tree-dxbar-$PID"
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
# rows as 'path|handler|confidence'; '## ...' header lines kept verbatim
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
function Compare-Rows($Want, $Got) {
    $bad = @()
    if ($Want.Count -ne $Got.Count) { $bad += "row count want $($Want.Count) got $($Got.Count)" }
    for ($i = 0; $i -lt $Want.Count; $i++) {
        $g = if ($i -lt $Got.Count) { $Got[$i] } else { '<no row>' }
        if ($Want[$i] -cne $g) { $bad += "row $($i + 1): want [$($Want[$i])] got [$g]" }
    }
    return ,$bad
}
function Kids($Node) { if ($null -eq $Node) { return ,@() } return ,@($Node.children) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fx = "$WorkDir\fx"
Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $fx -Recurse
New-Item -ItemType Directory "$fx\_D-RAG" | Out-Null
[IO.File]::WriteAllText("$fx\_D-RAG\drag-lint-project.json", '{ "ownRoots": ["."] }')
$proj = "$fx\Demo9.dproj"
$db   = "$WorkDir\fixture9.sqlite"
& $Exe index $fx --db $db *> "$WorkDir\index.log"
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: fixture index failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 2 }

# --- help names the flag ---
$help = (& $Exe menu-tree --help 2>&1 | Out-String)
Check 'menu-tree --help lists --with-dfm' ($help -match '--with-dfm')

# --- paths, cell by cell ---
$want = Get-Rows (Get-Content "$fx\expected-paths.txt" -Raw) $false
Check 'golden has rows' ($want.Count -ge 15) "($($want.Count))"
$paths = (& $Exe menu-tree --project $proj --db $db --with-dfm --format paths 2> "$WorkDir\paths.err" | Out-String)
Check 'menu-tree --with-dfm --format paths exits 0' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE) $(Get-Content "$WorkDir\paths.err" -Raw)"
$got = Get-Rows $paths $true
$bad = Compare-Rows $want $got
Check 'paths equal expected-paths.txt cell by cell' ($bad.Count -eq 0) (($bad | Select-Object -First 6) -join '; ')

# --- positive control: the comparer sees a one-cell change ---
$seeded = @($want)
$seeded[1] = $seeded[1] -replace '\|derived$', '|certain'
$ctl = Compare-Rows $seeded $got
Check 'positive control: a one-cell golden edit is reported' ($ctl.Count -ge 1) "($($ctl.Count) mismatch(es))"

# --- json: kinds, separators, idents, notes ---
$jsonText = (& $Exe menu-tree --project $proj --db $db --with-dfm --format json 2> "$WorkDir\json.err" | Out-String)
$j = $null
try { $j = $jsonText | ConvertFrom-Json } catch { $j = $null }
Check 'json exits 0 and parses' ($null -ne $j)
$roots = @($j.roots)
function RootOf([string]$Ident) { $roots | Where-Object { $_.ident -ceq $Ident } | Select-Object -First 1 }
$lists = RootOf 'TfrmMain9.barLists'
Check 'barLists root: form + identPath = the .dfm' ($null -ne $lists -and $lists.form -ceq 'TfrmMain9' -and $lists.identPath -like '*\uMain9.dfm') "form [$($lists.form)] identPath [$($lists.identPath)]"
$lk = (Kids $lists | ForEach-Object { $_.kind }) -join ','
Check 'barLists children: item,separator,item,item' ($lk -ceq 'item,separator,item,item') $lk
$home9 = RootOf 'TfrmMain9.barHome'
$hk = (Kids $home9 | ForEach-Object { $_.kind }) -join ','
Check 'barHome children: header (TdxBarStatic), item' ($hk -ceq 'header,item') $hk
$mm = RootOf 'TfrmMain9.barMainMenu'
$setup = Kids $mm | Where-Object { $_.caption -ceq '&Setup' } | Select-Object -First 1
$sk = (Kids $setup | ForEach-Object { $_.kind }) -join ','
Check 'Setup submenu: item,separator,item (BeginGroup)' ($sk -ceq 'item,separator,item') $sk
$presets = Kids $mm | Select-Object -First 1
Check 'Presets inserted at 0 into Bars[0], kind submenu, derived' ($null -ne $presets -and $presets.caption -ceq 'Presets' -and $presets.kind -ceq 'submenu' -and $presets.confidence -ceq 'derived') "[$($presets.caption)/$($presets.kind)/$($presets.confidence)]"
$ext = @($j.external)
$extIds = ($ext | ForEach-Object { $_.ident }) -join ','
Check 'only popGridMenu9 stays external (form links grafted)' ($extIds -ceq 'popGridMenu9') $extIds
$gp = $ext | Select-Object -First 1
$gk = (Kids $gp | ForEach-Object { $_.kind }) -join ','
Check 'popGridMenu9 children: submenu,separator,item' ($gk -ceq 'submenu,separator,item') $gk
$notes = @($j.notes)
Check 'NOTE unlinked bar item btnOrphan' (@($notes | Where-Object { $_ -match 'unlinked bar item' -and $_ -match 'btnOrphan' }).Count -eq 1) (($notes | Select-Object -First 4) -join ' | ')
Check 'NOTE dynamic caption' (@($notes | Where-Object { $_ -match '^dynamic caption' }).Count -ge 1)

# --- flag off: the walker's code links stay external roots ---
$offText = (& $Exe menu-tree --project $proj --db $db --format json 2> "$WorkDir\off.err" | Out-String)
$off = $null
try { $off = $offText | ConvertFrom-Json } catch { $off = $null }
$offIds = @($off.external | ForEach-Object { $_.ident })
Check 'flag off: no dfm roots' ($null -ne $off -and @($off.roots).Count -eq 0) "($(@($off.roots).Count) roots)"
Check 'flag off: popGrid and barLists are external roots' (($offIds -ccontains 'popGrid') -and ($offIds -ccontains 'barLists')) ($offIds -join ',')

# --- stale .dfm: exit 3 ---
[IO.File]::AppendAllText("$fx\uMain9.dfm", "`r`n")
& $Exe menu-tree --project $proj --db $db --with-dfm --format paths *> "$WorkDir\stale.out"
$staleExit = $LASTEXITCODE
$staleOut  = Get-Content "$WorkDir\stale.out" -Raw
# exit 3 alone is not enough: an unknown-argument failure also exits 3
Check 'a .dfm changed since indexing -> exit 3, names the .dfm' (($staleExit -eq 3) -and ($staleOut -match 'stale index') -and ($staleOut -match 'uMain9\.dfm')) "(exit $staleExit) $staleOut"

if ($script:Failed) { Write-Host 'menu-tree dxbar guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'menu-tree dxbar guard: PASS' -ForegroundColor Green
exit 0
}
catch {
    Write-Host "GUARD BROKEN: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
