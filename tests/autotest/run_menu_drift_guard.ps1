# drag-lint menu-drift guard (spec docs\superpowers\specs\2026-10-23-code-built-menu-reader-design.md,
# sections 7 and 11): the code-built menu tree vs the registry's ide-menu paths.
#
# Fixture part (tests\fixtures\menutree, indexed into SCRATCH DBs with an
# explicit --db; registries and sources are scratch COPIES):
#   negative control  unseeded registry                -> exit 0, missing=0 unregistered=0 moved=0
#   control 1         one entry deleted                -> exit 1, exactly one UNREGISTERED
#   control 2         a registry caption changed       -> exit 1, exactly one MISSING with "renamed?"
#   control 3         a registry parent segment changed-> exit 1, exactly one MOVED
#   control 4         helper AddItem renamed PutItem   -> exit 0 (recognition is by body)
#   control 5         a caption made dynamic in source -> exit 0, missing=0, notes = baseline + 1
#   stale control     a unit touched after indexing    -> exit 3
# Real part: the drag-lint IDE plugin itself --
#   menu-drift --project src\delphi-plugin\dclDragLintWizard.dproj
#              --db src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite --registry features
# PASS only on exit 0. Exit 3 (stale) or a missing DB is "GUARD BROKEN", never a
# pass: tests\autotest\prepare_battery.ps1 builds / refreshes that DB.
#
# Cannot pass vacuously: every class count is read from the parsed summary line
# (a missing line fails), and each control must produce its OWN class.
#
# Usage: pwsh -File tests/autotest/run_menu_drift_guard.ps1 [-Exe <path>] [-PluginDb <db>]
[CmdletBinding()]
param(
    [string] $Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\menutree",
    [string] $Repo       = "$PSScriptRoot\..\..",
    [string] $PluginDb   = '',
    [string] $WorkDir    = "$env:TEMP\drag-lint-menu-drift-guard-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Broken = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $status = if ($Ok) { 'PASS' } else { 'FAIL' }
    $color  = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
# runs menu-drift; returns @{ Exit; Text; Missing; Unregistered; Moved; Notes } (counts $null without a summary line)
function Invoke-Drift([string]$Proj, [string]$Db, [string]$Reg) {
    $text = (& $Exe menu-drift --project $Proj --db $Db --registry $Reg 2>&1 | Out-String)
    $r = @{ Exit = $LASTEXITCODE; Text = $text; Missing = $null; Unregistered = $null; Moved = $null; Notes = $null }
    $m = [regex]::Match($text, 'menu-drift: missing=(\d+) unregistered=(\d+) moved=(\d+) notes=(\d+)')
    if ($m.Success) {
        $r.Missing = [int]$m.Groups[1].Value; $r.Unregistered = [int]$m.Groups[2].Value
        $r.Moved = [int]$m.Groups[3].Value;   $r.Notes = [int]$m.Groups[4].Value
    }
    return $r
}
function Counts($R) { "exit=$($R.Exit) missing=$($R.Missing) unregistered=$($R.Unregistered) moved=$($R.Moved) notes=$($R.Notes)" }
function New-FixtureCopy([string]$Name) {
    $d = Join-Path $WorkDir $Name
    Copy-Item -LiteralPath (Resolve-Path $FixtureDir).Path -Destination $d -Recurse
    return $d
}
function Index-Copy([string]$Dir) {
    $db = "$Dir.sqlite"
    & $Exe index --project "$Dir\MenuTreeFixture.dproj" --db $db *> "$Dir.index.log"
    if ($LASTEXITCODE -ne 0) { throw "index of $Dir failed (exit $LASTEXITCODE)" }
    return $db
}
function Set-RegistryPath([string]$RegDir, [string]$Entry, [string]$From, [string]$To) {
    $f = Join-Path $RegDir "entries\$Entry.json"
    $t = [IO.File]::ReadAllText($f)
    if (-not $t.Contains($From)) { throw "seed: '$From' not in $f" }
    [IO.File]::WriteAllText($f, $t.Replace($From, $To), [Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$repoRoot = (Resolve-Path $Repo).Path

# --- fixture: negative control ---
$fx   = New-FixtureCopy 'fx'
$db   = Index-Copy $fx
$proj = "$fx\MenuTreeFixture.dproj"
$base = Invoke-Drift $proj $db "$fx\registry"
Check 'negative control: unseeded -> exit 0, missing=0 unregistered=0 moved=0' (($base.Exit -eq 0) -and ($base.Missing -eq 0) -and ($base.Unregistered -eq 0) -and ($base.Moved -eq 0)) (Counts $base)

# --- control 1: delete one entry -> unregistered ---
$reg1 = Join-Path $WorkDir 'reg1'; Copy-Item -LiteralPath "$fx\registry" -Destination $reg1 -Recurse
Remove-Item -LiteralPath "$reg1\entries\about.json"
$r1 = Invoke-Drift $proj $db $reg1
Check 'control 1: entry deleted -> exit 1, exactly one UNREGISTERED' (($r1.Exit -eq 1) -and ($r1.Unregistered -eq 1) -and ($r1.Missing -eq 0) -and ($r1.Moved -eq 0) -and ($r1.Text -match 'UNREGISTERED Fixture > About')) (Counts $r1)

# --- control 2: change a registry caption -> missing with renamed? ---
$reg2 = Join-Path $WorkDir 'reg2'; Copy-Item -LiteralPath "$fx\registry" -Destination $reg2 -Recurse
Set-RegistryPath $reg2 'export' 'Fixture > Export Everything' 'Fixture > Export Everything Now'
$r2 = Invoke-Drift $proj $db $reg2
Check 'control 2: caption changed -> exit 1, exactly one MISSING with renamed?' (($r2.Exit -eq 1) -and ($r2.Missing -eq 1) -and ($r2.Unregistered -eq 0) -and ($r2.Moved -eq 0) -and ($r2.Text -match "renamed\? -> 'Export Everything'")) (Counts $r2)

# --- control 3: change a parent segment -> moved ---
$reg3 = Join-Path $WorkDir 'reg3'; Copy-Item -LiteralPath "$fx\registry" -Destination $reg3 -Recurse
Set-RegistryPath $reg3 'about' 'Fixture > About' 'Fixture > Catalog > About'
$r3 = Invoke-Drift $proj $db $reg3
Check 'control 3: parent changed -> exit 1, exactly one MOVED' (($r3.Exit -eq 1) -and ($r3.Moved -eq 1) -and ($r3.Missing -eq 0) -and ($r3.Unregistered -eq 0) -and ($r3.Text -match 'now at Fixture > About')) (Counts $r3)

# --- control 4: rename the helper in a source copy -> tree unchanged ---
$fx4 = New-FixtureCopy 'fx4'
$b = "$fx4\MT.Builder.pas"
[IO.File]::WriteAllText($b, [regex]::Replace([IO.File]::ReadAllText($b), '\bAddItem\b', 'PutItem'), [Text.ASCIIEncoding]::new())
$db4 = Index-Copy $fx4
$r4 = Invoke-Drift "$fx4\MenuTreeFixture.dproj" $db4 "$fx4\registry"
Check 'control 4: helper renamed -> exit 0, no drift' (($r4.Exit -eq 0) -and ($r4.Missing -eq 0) -and ($r4.Unregistered -eq 0) -and ($r4.Moved -eq 0)) (Counts $r4)

# --- control 5: a caption made dynamic -> a note, never missing ---
$fx5 = New-FixtureCopy 'fx5'
$b = "$fx5\MT.Builder.pas"
$src = [IO.File]::ReadAllText($b)
if (-not $src.Contains("AddItem(Root, 'Open...', DoOpen);")) { throw 'seed 5: Open... call not found' }
[IO.File]::WriteAllText($b, $src.Replace("AddItem(Root, 'Open...', DoOpen);", 'AddItem(Root, ParamStr(0), DoOpen);'), [Text.ASCIIEncoding]::new())
$db5 = Index-Copy $fx5
$r5 = Invoke-Drift "$fx5\MenuTreeFixture.dproj" $db5 "$fx5\registry"
Check 'control 5: dynamic caption -> exit 0, missing=0, notes = baseline + 1' (($r5.Exit -eq 0) -and ($r5.Missing -eq 0) -and ($null -ne $base.Notes) -and ($r5.Notes -eq $base.Notes + 1)) ("$(Counts $r5) baseline notes=$($base.Notes)")

# --- stale control: touch a unit after indexing -> exit 3 ---
Add-Content -LiteralPath "$fx\MT.Catalog.pas" -Value "`r`n{ touched by run_menu_drift_guard }" -Encoding ascii
$rs = Invoke-Drift $proj $db "$fx\registry"
Check 'stale control: touched unit -> exit 3 + stale message' (($rs.Exit -eq 3) -and ($rs.Text -match 'menu-drift: stale index')) (Counts $rs)

# --- the real plugin ---
$plugProj = Join-Path $repoRoot 'src\delphi-plugin\dclDragLintWizard.dproj'
if ($PluginDb -eq '') { $PluginDb = Join-Path $repoRoot 'src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite' }
if (-not (Test-Path -LiteralPath $PluginDb)) {
    Write-Host "  GUARD BROKEN: plugin index missing: $PluginDb -- run tests\autotest\prepare_battery.ps1" -ForegroundColor Red
    $script:Broken = $true
} else {
    $real = Invoke-Drift $plugProj $PluginDb (Join-Path $repoRoot 'features')
    if (($real.Exit -eq 3) -and ($real.Text -match 'stale index')) {
        Write-Host "  GUARD BROKEN: plugin index is stale -- drag-lint index --project `"$plugProj`" --db `"$PluginDb`"" -ForegroundColor Red
        $script:Broken = $true
    } else {
        Check 'real: the plugin menu matches the registry (menu-drift exit 0)' ($real.Exit -eq 0) (Counts $real)
        if ($real.Exit -ne 0) { ($real.Text -split "`r?`n" | Where-Object { $_ -match '^(MISSING|MOVED|UNREGISTERED)' } | Select-Object -First 25) | ForEach-Object { Write-Host "      $_" } }
    }
}

Write-Host ''
if ($script:Broken) { Write-Host 'GUARD BROKEN run_menu_drift_guard' -ForegroundColor Red; exit 1 }
if ($script:Failed) { Write-Host 'FAIL run_menu_drift_guard' -ForegroundColor Red; exit 1 }
Write-Host 'PASS run_menu_drift_guard' -ForegroundColor Green
exit 0
} catch {
    Write-Host "FAIL run_menu_drift_guard: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
