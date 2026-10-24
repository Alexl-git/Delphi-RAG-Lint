# drag-lint menu-drift app guard (spec docs\superpowers\specs\2026-10-24-dxbar-menus.md,
# decision 6 / T6): an APPLICATION's registry of `app-menu` surfaces
# ({ "type": "app-menu", "form": "TfrmMain9", "path": "Main menu > Setup > Groups" })
# against the .dfm + code menu tree of the formsmap-v9 fixture, keyed by
# (form, path). An app-menu surface implies --with-dfm; the registry is found
# at <project>\_D-RAG\menu-registry when --registry is not given.
#
# Cannot pass vacuously: every count comes from the parsed menu-drift/1 JSON
# summary ($null fails); the baseline must be exactly 0/0/0 AND each seeded
# edit must move exactly the one counter it targets (positive controls).
#
# Usage: pwsh -File tests/autotest/run_menu_drift_app.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap-v9",
    [string] $WorkDir    = "$env:TEMP\drag-lint-menu-drift-app-$PID"
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

# one drift run on a registry copy edited by $Edit; returns exit, summary, parsed doc
function Run-Drift([string]$Tag, [scriptblock]$Edit, [string[]]$Extra = @(), [switch]$DefaultLocation) {
    $reg = if ($DefaultLocation) { "$fx\_D-RAG\menu-registry" } else { "$WorkDir\reg-$Tag" }
    if (Test-Path $reg) { [IO.Directory]::Delete($reg, $true) }
    Copy-Item -LiteralPath "$fx\menu-registry" -Destination $reg -Recurse
    if ($Edit) { & $Edit $reg }
    $regArgs = if ($DefaultLocation) { @() } else { @('--registry', $reg) }
    $txt = (& $Exe menu-drift --project $proj --db $db @regArgs @Extra --format json 2> "$WorkDir\$Tag.err" | Out-String)
    $code = $LASTEXITCODE
    $doc = $null
    try { $doc = $txt | ConvertFrom-Json } catch { $doc = $null }
    if ($DefaultLocation) { [IO.Directory]::Delete($reg, $true) }
    $s = $doc.summary
    [pscustomobject]@{ Exit = $code; Doc = $doc; M = $s.missing; U = $s.unregistered; V = $s.moved; N = $s.notes
        Line = "exit=$code missing=$($s.missing) unregistered=$($s.unregistered) moved=$($s.moved) notes=$($s.notes)" }
}
function SetPath([string]$Reg, [string]$Id, [string]$Path) {
    $f = "$Reg\entries\$Id.json"
    $j = Get-Content $f -Raw | ConvertFrom-Json
    $j.surfaces[0].path = $Path
    [IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 5), [Text.Encoding]::ASCII)
}

# --- baseline: every live leaf registered once per place it is shown -> no drift ---
$b = Run-Drift 'base' $null
Check 'baseline (app-menu implies --with-dfm): exit 0, 0/0/0' (($b.Exit -eq 0) -and ($b.M -eq 0) -and ($b.U -eq 0) -and ($b.V -eq 0)) $b.Line
$d = Run-Drift 'default' $null -DefaultLocation
Check 'registry found at <project>\_D-RAG\menu-registry without --registry' (($d.Exit -eq 0) -and ($d.M -eq 0) -and ($d.U -eq 0)) $d.Line

# --- unseeded: no app-menu surface -> no .dfm tree, nothing to compare (no code-only roots here) ---
$u = Run-Drift 'unseeded' { param($r) Get-ChildItem "$r\entries" | ForEach-Object { [IO.File]::Delete($_.FullName) } }
Check 'unseeded registry: exit 0, 0/0/0' (($u.Exit -eq 0) -and ($u.M -eq 0) -and ($u.U -eq 0) -and ($u.V -eq 0)) $u.Line

# --- delete an entry -> exactly one UNREGISTERED ---
$c = Run-Drift 'delete' { param($r) [IO.File]::Delete("$r\entries\users.json") }
$up = @($c.Doc.unregistered | ForEach-Object { $_.path })
Check 'entry deleted: exit 1, unregistered=1 (Main menu > Setup > Users)' (($c.Exit -eq 1) -and ($c.U -eq 1) -and ($c.M -eq 0) -and ($up -ccontains 'Main menu > Setup > Users')) "$($c.Line) $($up -join ' | ')"
$sk = @($c.Doc.unregistered | ForEach-Object { $_.skeleton }) -join ''
Check 'skeleton is an app-menu surface with the form' ($sk -match '"type": "app-menu"' -and $sk -match '"form": "TfrmMain9"') $sk

# --- caption changed in the registry -> MISSING with renamed? ---
$c = Run-Drift 'rename' { param($r) SetPath $r 'customers-ribbon' 'Ribbon: Lists > Lists Bar > Customer Listing' }
$hint = @($c.Doc.missing | ForEach-Object { $_.hint }) -join ''
Check 'caption change: exit 1, missing=1 with renamed?' (($c.Exit -eq 1) -and ($c.M -eq 1) -and ($c.U -eq 0) -and ($hint -match 'renamed\?')) "$($c.Line) $hint"

# --- registered under another parent -> MOVED ---
$c = Run-Drift 'move' { param($r) SetPath $r 'home' 'Main menu > Setup > Home Page' }
Check 'moved: exit 1, moved=1, nothing else' (($c.Exit -eq 1) -and ($c.V -eq 1) -and ($c.M -eq 0) -and ($c.U -eq 0)) $c.Line

# --- a path under a parent with a dynamic leaf -> a note, never missing ---
$c = Run-Drift 'dynamic' { param($r) [IO.File]::WriteAllText("$r\entries\preset-one.json", '{ "id": "preset-one", "surfaces": [ { "type": "app-menu", "form": "TfrmMain9", "path": "Main menu > Presets > Preset One" } ] }') }
$dn = @($c.Doc.notes | Where-Object { $_ -match '^dynamic caption' }).Count
Check 'dynamic: exit 0, missing=0, dynamic-caption note' (($c.Exit -eq 0) -and ($c.M -eq 0) -and ($dn -ge 1)) "$($c.Line) dynamic notes=$dn"

# --- an item linked three times, one link unregistered -> that link is UNREGISTERED ---
$c = Run-Drift 'twice' { param($r) [IO.File]::Delete("$r\entries\customers-qat.json") }
$up = @($c.Doc.unregistered | ForEach-Object { $_.path })
Check 'item linked 3x, QAT link unregistered: exactly that path' (($c.U -eq 1) -and ($up -ccontains "Toolbar 'Quick Access Toolbar' > Customer List")) "$($c.Line) $($up -join ' | ')"

# --- the form is part of the key: the same paths for another form cover nothing ---
$c = Run-Drift 'otherform' { param($r) Get-ChildItem "$r\entries" | ForEach-Object { $t = [IO.File]::ReadAllText($_.FullName).Replace('TfrmMain9', 'TfrmOther'); [IO.File]::WriteAllText($_.FullName, $t) } }
Check 'surfaces of another form: all 12 live leaves unregistered, 12 missing' (($c.U -eq 12) -and ($c.M -eq 12)) $c.Line

if ($script:Failed) { Write-Host 'menu-drift app guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'menu-drift app guard: PASS' -ForegroundColor Green
exit 0
}
catch {
    Write-Host "GUARD BROKEN: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
