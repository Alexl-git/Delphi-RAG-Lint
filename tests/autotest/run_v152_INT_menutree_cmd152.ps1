# drag-lint menu-tree: the 1.52 command table (DragLint.Plugin.Cmd152) is harvested
# with its REAL paths (lane v152 INT-MENUTREE).
#
# The plugin registers its 1.52 commands as RECORDS (TCmd152Command) from each
# DragLint.Plugin.Cmd.X unit's initialization section; BuildCmd152Menu then loops
# over the table and builds every row under EnsurePath(pRoot, Cmd.ParentPath, ..).
# Before this lane the static walk saw that loop once, unbound, and reported ONE
# row 'drag-lint > <dynamic: LevelName> > <dynamic: Cmd.Caption>', so featuregen
# check C said "the live menu has 'drag-lint' and nothing more" for every 1.52
# ide-menu surface.
#
# Real sources: the plugin project of THIS checkout is indexed into a private DB.
# Cannot pass vacuously: every expected path is looked up in the parsed rows
# (a missing row fails by name), the dynamic row must be GONE, hidden rows
# (Visible = False) must be absent, and the merged submenus are counted in the
# PARSED JSON. Positive control: static paths built by Editor.pas outside the
# table ('Code Quality > Run Lint All', the leaf 'Find Usages...') are present --
# a run that returned nothing, or the wrong project, fails there first.
#
# Part 2 (featuregen check, skipped with -SkipFeatureGen): the Editor right-click
# harvest of FeatureGen.Live names the EditorParent level and reads every row
# variable passed to RegisterCmd152, so 'drag-lint > Find Usages > <scope>' is no
# longer "not on the Editor context menu".
#
# Usage: pwsh -File tests/autotest/run_v152_INT_menutree_cmd152.ps1 [-Exe <path>] [-WorkDir <dir>] [-SkipFeatureGen]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-v152-menutree-$PID",
    [switch] $SkipFeatureGen
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $status = if ($Ok) { 'PASS' } else { 'FAIL' }
    $color  = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
function Kids($Node) { if ($null -eq $Node) { return } foreach ($c in @($Node.children)) { $c } }

$Exe = [IO.Path]::GetFullPath($Exe)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$repo  = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$dproj = Join-Path $repo 'src\delphi-plugin\dclDragLintWizard.dproj'
if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }
$db = Join-Path $WorkDir 'plugin.sqlite'

Write-Host '== v152 INT-MENUTREE: Cmd152 rows in menu-tree =='
& $Exe index --project $dproj --db $db 2>&1 | Out-Null
Check 'index the plugin project' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"

$pathsText = & $Exe menu-tree --project $dproj --db $db --format paths 2>&1 | Out-String
Check 'menu-tree --format paths ran' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
$rows = @{}
foreach ($line in ($pathsText -split "`r?`n")) {
    if ($line.Trim() -eq '' -or $line.StartsWith('## ')) { continue }
    $c = $line -split "`t"
    $rows[$c[0]] = if ($c.Count -gt 1) { $c[1] } else { '' }
}

# ---- positive control: static paths outside the table ----
foreach ($p in @('drag-lint > Code Quality > Run Lint All (Full Report)...', 'drag-lint > Find Usages...')) {
    Check "control: static path present: $p" ($rows.ContainsKey($p))
}

# ---- the table rows, at their real paths, with their handlers ----
$want = [ordered]@{
    'drag-lint > Analyze > Check Initialization of Identifier at Cursor...' = 'InvokeCheckInit'
    'drag-lint > Field Repository > Open Field Repository Editor...'        = 'InvokeOpenEditor'
    'drag-lint > Field Repository > Refresh Schema from Database...'        = 'InvokeRefreshSchema'
    'drag-lint > Field Repository > FDMemTable from CSV...'                 = 'InvokeMemTableFromCsv'
    'drag-lint > Find Usages > This symbol'                                 = 'InvokeScopeSymbol'
    'drag-lint > Find Usages > Project'                                     = 'InvokeScopeProject'
    'drag-lint > Find Usages > Group'                                       = 'InvokeScopeGroup'
    'drag-lint > Find Usages > Everywhere'                                  = 'InvokeScopeEverywhere'
    'drag-lint > Code Quality > Disable Rule...'                            = ''
    'drag-lint > Code Quality > Fix with drag-lint (finding at cursor)'     = ''
    'drag-lint > Extract Constant (literal at cursor)...'                   = ''
}
foreach ($p in $want.Keys) {
    $has = $rows.ContainsKey($p)
    Check "row: $p" $has
    if ($has -and $want[$p] -ne '') {
        Check "  handler of it ends in .$($want[$p])" ($rows[$p] -match ('\.' + [regex]::Escape($want[$p]) + '$')) "(got '$($rows[$p])')"
    }
}

# ---- the unbound loop row is gone ----
$dyn = @($rows.Keys | Where-Object { $_ -match '<dynamic: (Cmd\.|LevelName)' })
Check 'no <dynamic: Cmd.* / LevelName> row is left' ($dyn.Count -eq 0) "($($dyn -join ' | '))"

# ---- hidden rows (Visible = False) are not on the live menu ----
foreach ($cap in @('Verify All Callers Pass an In-Range Index...')) {
    $hit = @($rows.Keys | Where-Object { $_.EndsWith(' > ' + $cap) })
    Check "hidden row absent: $cap" ($hit.Count -eq 0) "($($hit -join ' | '))"
}
# Positive control for the absence above: rows registered VISIBLE (1.52 TTFINISH made the ORM and Param Array rows
# public) ARE on the live menu, so an absent hidden row is not a walk that saw nothing.
foreach ($cap in @('Param Array Assistant...', 'Generate / Update ORM Source...')) {
    $hit = @($rows.Keys | Where-Object { $_.EndsWith(' > ' + $cap) })
    Check "visible row present: $cap" ($hit.Count -eq 1) "($($hit -join ' | '))"
}

# ---- one submenu per caption: rows find the existing submenu, they never duplicate it ----
$json = & $Exe menu-tree --project $dproj --db $db --format json 2>$null | Out-String
$doc = $json | ConvertFrom-Json
$root = @($doc.roots) | Where-Object { $_.caption -eq 'drag-lint' } | Select-Object -First 1
Check 'json: drag-lint root parsed' ($null -ne $root)
foreach ($sub in @('Code Quality', 'Find Usages', 'Field Repository', 'Analyze')) {
    $n = @(Kids $root | Where-Object { $_.caption -eq $sub -and $_.kind -eq 'submenu' }).Count
    Check "json: exactly one '$sub' submenu under drag-lint" ($n -eq 1) "(got $n)"
}
$cq = Kids $root | Where-Object { $_.caption -eq 'Code Quality' -and $_.kind -eq 'submenu' } | Select-Object -First 1
$cqCaps = @(Kids $cq | ForEach-Object { $_.caption })
Check "json: 'Code Quality' keeps its static items AND gains the table rows" (($cqCaps -contains 'Run Lint All (Full Report)...') -and ($cqCaps -contains 'Disable Rule...')) "($($cqCaps.Count) children)"

# ---- featuregen: the Editor context harvest names the EditorParent level and every registered row variable ----
# (FeatureGen.Live read only 'Command.Caption := ..' and no EditorParent, so the four Find Usages scope rows -- a
# Row variable, EditorParent 'Find Usages' -- were "not on the Editor context menu"; a TaskDialog's TD.Caption must
# NOT become an editor item.) Control: check C ran (it judges ide-menu paths against the tree: a hidden row's
# registered path is still reported), so the absence below is not a check that never ran.
if (-not $SkipFeatureGen) {
    . (Join-Path $repo 'tools\featuregen-ensure.ps1')
    $fg = Get-FeatureGenExe -Repo $repo
    $chk = & $fg check --level full --repo $repo --engine $Exe 2>&1 | Out-String
    $cLines = @($chk -split "`r?`n" | Where-Object { $_ -match '^\s*C: ' })
    # Control: since 1.52 TTFINISH no registered ide-menu path is hidden, so a clean registry prints NO C line; prove
    # instead that check ran at full level AND read the live menu tree (its menu-tree NOTE lines come from that walk).
    Check 'control: featuregen check full ran and read the menu tree' (($chk -match 'check \(full\): (PASS|FAIL)') -and ($chk -match '\[NOTE\] menu-tree: ')) "($($cLines.Count) C lines)"
    foreach ($s in @('This symbol', 'Project', 'Group', 'Everywhere')) {
        $bad = @($cLines | Where-Object { $_ -match [regex]::Escape("'drag-lint > Find Usages > $s'") })
        Check "featuregen: no C line for 'drag-lint > Find Usages > $s' (menu or Editor context)" ($bad.Count -eq 0) "($($bad.Count))"
    }
    $nearest = @($cLines | Where-Object { $_ -match 'Editor context menu \(nearest: [^)]*drag-lint > drag-lint: Disable Rule' })
    Check 'featuregen: a TaskDialog caption is not an Editor context item' ($nearest.Count -eq 0)
}

if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
