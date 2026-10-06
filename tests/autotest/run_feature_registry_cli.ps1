#Requires -Version 7.3
<#
  run_feature_registry_cli.ps1 -- every registry engine verb works on a SCRATCH
  copy of the registry (never the tracked one), refuses what the spec says it
  refuses, and writes nothing when it refuses. Review Focus 4: '&&' / '&' in a
  menu node resolve to the same entry for blast-radius and move-menu.
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$WorkDir = "$env:TEMP\drag-lint-feature-registry-cli-$PID")
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
function Sha($f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
Write-Host '== feature registry: engine CLI ==' -ForegroundColor Cyan
$cli = Join-Path $Repo 'tools\feature-registry.ps1'
Check 'CLI present' (Test-Path -LiteralPath $cli) $cli
if (-not (Test-Path -LiteralPath $cli)) { Write-Host 'FEATURE REGISTRY CLI: FAIL' -ForegroundColor Red; exit 1 }

# --- a scratch repo: registry data + the few source files the module reads ----
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
$S = Join-Path $WorkDir 'repo'
New-Item -ItemType Directory -Path (Join-Path $S 'features\entries'), (Join-Path $S 'docs\wiki'), (Join-Path $S 'src\core'), (Join-Path $S 'charts\src') -Force | Out-Null
foreach ($d in 'schema', 'families', 'templates') { if (Test-Path -LiteralPath (Join-Path $Repo "features\$d")) { Copy-Item -LiteralPath (Join-Path $Repo "features\$d") -Destination (Join-Path $S 'features') -Recurse -Force } }
foreach ($f in 'groups.json', 'teams.json', 'exemptions.json', 'related-projects.json') { Copy-Item -LiteralPath (Join-Path $Repo "features\$f") -Destination (Join-Path $S 'features') -Force }
Copy-Item -LiteralPath (Join-Path $Repo 'CHANGELOG.md') -Destination $S -Force
Copy-Item -LiteralPath (Join-Path $Repo 'src\core\DRagLint.Core.Model.pas') -Destination (Join-Path $S 'src\core') -Force
Copy-Item -LiteralPath (Join-Path $Repo 'charts\src\Ask-Report.ps1') -Destination (Join-Path $S 'charts\src') -Force
foreach ($pg in 'Maintenance', 'Uses-Report-CSV', 'Zz-Other', 'Uses-Audit') { [IO.File]::WriteAllText((Join-Path $S "docs\wiki\$pg.md"), "# $pg`r`n", [Text.Encoding]::ASCII) }
Remove-Item -LiteralPath (Join-Path $S 'features\entries\*') -Force -ErrorAction SilentlyContinue
function Run { param([string[]]$ArgList) $o = & pwsh -NoProfile -File $cli @ArgList -Repo $S 2>&1 | Out-String; return [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }

# --- add --------------------------------------------------------------------
$r = Run @('add', '-Id', 'uses-report-csv', '-Title', 'Uses Report (CSV)', '-Group', 'no-such-group', '-Owner', 'ENGINE', '-Summary', 'Every uses edge of a project as a CSV for a spreadsheet', '-Intro', 'Writes one row per uses edge.', '-WikiPage', 'Uses-Report-CSV', '-Surface', 'cli:uses-report ;; ide-menu:drag-lint > Uses & Dependencies > Uses Report (CSV)...', '-By', 'guard')
Check 'add refuses an unknown group and names the choices' (($r.Code -eq 1) -and ($r.Out -match 'unknown group') -and ($r.Out -match 'maintenance')) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
Check 'and wrote nothing' (-not (Test-Path -LiteralPath (Join-Path $S 'features\entries\uses-report-csv.json')))
$r = Run @('add', '-Id', 'uses-report-csv', '-Title', 'Uses Report (CSV)', '-Group', 'graphs-reports', '-Owner', 'ENGINE', '-Summary', 'Every uses edge of a project as a CSV for a spreadsheet', '-Intro', 'Writes one row per uses edge.', '-WikiPage', 'Uses-Report-CSV', '-Surface', 'cli:uses-report ;; ide-menu:drag-lint > Uses & Dependencies > Uses Report (CSV)...', '-By', 'guard')
$f1 = Join-Path $S 'features\entries\uses-report-csv.json'
Check 'add creates the entry file' (($r.Code -eq 0) -and (Test-Path -LiteralPath $f1)) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
Import-Module (Join-Path $Repo 'tools\FeatureRegistry.psm1') -Force
$p = Get-RegistryPaths -Repo $S
$e1 = Read-FeatureEntry -Path $f1
Check 'the file is canonical' ((Test-EntryCanonicalBytes -Read $e1 -KeyOrder (Get-EntryKeyOrder -Paths $p)) -eq '')
Check 'lastVerified = today / caller / current build' (($e1.Entry.lastVerified.date -eq (Get-Date -Format 'yyyy-MM-dd')) -and ($e1.Entry.lastVerified.by -eq 'guard') -and ($e1.Entry.lastVerified.build -eq (Get-CurrentBuildVersion -Paths $p)))
Check 'since defaults to the current build' ($e1.Entry.since -eq (Get-CurrentBuildVersion -Paths $p))
Check 'surfaces parsed from -Surface specs' (($e1.Entry.surfaces.Count -eq 2) -and ($e1.Entry.surfaces[1].path -eq 'drag-lint > Uses & Dependencies > Uses Report (CSV)...'))
$r = Run @('add', '-Id', 'uses-report-csv', '-Title', 'Dup', '-Group', 'graphs-reports', '-Owner', 'ENGINE', '-Summary', 'A duplicate that must be refused by the engine', '-WikiPage', 'Maintenance', '-Surface', 'cli:info')
Check 'add refuses a duplicate id' (($r.Code -eq 1) -and ($r.Out -match 'already exists'))
$r = Run @('add', '-Id', 'rule.zz', '-Title', 'Bad id', '-Group', 'linting', '-Owner', 'ENGINE', '-Summary', 'A hand id inside the importer namespace is refused', '-Intro', 'x', '-WikiPage', 'Maintenance', '-Surface', 'cli:info')
Check 'add refuses an id in a family namespace' (($r.Code -eq 1) -and ($r.Out -match 'importers own'))
$r = Run @('add', '-Id', 'zz-new-team-feature', '-Title', 'New team feature', '-Group', 'maintenance', '-Owner', 'DOCS', '-Summary', 'Registered by a team that did not exist a second ago', '-Intro', 'Proves -NewTeam.', '-WikiPage', 'Maintenance', '-Surface', 'workflow:docs\wiki\Maintenance.md', '-NewTeam', '-TeamTitle', 'Docs team', '-TeamSummary', 'Writes the manual and the wiki.')
$teams = (Get-Content -LiteralPath (Join-Path $S 'features\teams.json') -Raw | ConvertFrom-Json).teams
Check 'add -NewTeam registers the team with order max+10' (($r.Code -eq 0) -and (@($teams | Where-Object { $_.id -eq 'DOCS' -and $_.order -eq 40 }).Count -eq 1)) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
$r = Run @('add', '-Id', 'zz-new-group-feature', '-Title', 'New group feature', '-Group', 'testing', '-Owner', 'ENGINE', '-Summary', 'Registered into a group created on the way in', '-Intro', 'Proves -NewGroup.', '-WikiPage', 'Zz-Other', '-Surface', 'cli:selftest', '-NewGroup', '-GroupTitle', 'Testing', '-GroupSummary', 'Self-tests and the battery.')
$groups = (Get-Content -LiteralPath (Join-Path $S 'features\groups.json') -Raw | ConvertFrom-Json).groups
Check 'add -NewGroup registers the group with order max+10' (($r.Code -eq 0) -and (@($groups | Where-Object { $_.id -eq 'testing' -and $_.order -eq 130 }).Count -eq 1))
# Spec 5.3: groups.json / teams.json stay one row per line, keys in id/title/order/summary order.
$gl = @(Get-Content -LiteralPath (Join-Path $S 'features\groups.json'))
Check 'groups.json keeps its one-row-per-line layout' (($gl.Count -eq ($groups.Count + 4)) -and ($gl -contains '    { "id": "testing", "title": "Testing", "order": 130, "summary": "Self-tests and the battery." }')) "($($gl.Count) lines)"

# --- update -----------------------------------------------------------------
$before = Sha $f1
$r = Run @('update', '-Id', 'uses-report-csv', '-Set', 'summary=Too short')
Check 'update refuses an invalid value and leaves the file untouched' (($r.Code -eq 1) -and ((Sha $f1) -eq $before)) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
$r = Run @('update', '-Id', 'uses-report-csv', '-Set', 'aliases=["uses csv","dependency spreadsheet"] ;; audience=human')
$e1 = Read-FeatureEntry -Path $f1
Check 'update applies a JSON array and a scalar' (($r.Code -eq 0) -and ($e1.Entry.aliases -contains 'uses csv') -and ($e1.Entry.audience -eq 'human'))
$r = Run @('update', '-Id', 'uses-report-csv', '-Set', 'aliases=')
$e1 = Read-FeatureEntry -Path $f1
Check 'update with an empty value removes the key' (($r.Code -eq 0) -and -not $e1.Entry.Contains('aliases'))

# --- find -------------------------------------------------------------------
$r = Run @('find', '-Text', 'spreadsheet', '-Json')
Check 'find hits an entry through its summary' (($r.Code -eq 0) -and ($r.Out -match '"Id":\s*"uses-report-csv"'))
$r = Run @('find', '-Text', 'zz-definitely-nothing')
Check 'find with no hit exits 1' ($r.Code -eq 1)

# --- blast-radius, REVIEW FOCUS 4 -------------------------------------------
$r = Run @('blast-radius', '-MenuPath', 'drag-lint > Uses && Dependencies', '-Json')
Check 'blast-radius with && finds the entry stored with &' (($r.Code -eq 0) -and ($r.Out -match 'uses-report-csv') -and ($r.Out -match 'Uses-Report-CSV'))
$r = Run @('blast-radius', '-MenuPath', 'drag-lint > Nowhere')
Check 'blast-radius on an empty node exits 1' ($r.Code -eq 1)
$r = Run @('blast-radius', '-VerbName', 'uses-report', '-Json')
Check 'blast-radius by verb' (($r.Code -eq 0) -and ($r.Out -match 'uses-report-csv'))

# --- move-menu --------------------------------------------------------------
$before = Sha $f1
$r = Run @('move-menu', '-From', 'drag-lint > Uses && Dependencies', '-To', 'drag-lint > Dependencies', '-WhatIf', '-Json')
Check 'move-menu -WhatIf with && lists the entry stored with & and writes nothing' (($r.Code -eq 0) -and ($r.Out -match 'uses-report-csv') -and ((Sha $f1) -eq $before))
$r = Run @('move-menu', '-From', 'drag-lint > Uses & Dependencies', '-To', 'drag-lint > Dependencies', '-Json')
$e1 = Read-FeatureEntry -Path $f1
Check 'move-menu rewrites the path prefix and keeps the leaf' (($r.Code -eq 0) -and ($e1.Entry.surfaces[1].path -eq 'drag-lint > Dependencies > Uses Report (CSV)...')) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
Check 'move-menu reports the wiki page to revisit' ($r.Out -match 'Uses-Report-CSV')
Check 'moved file is canonical' ((Test-EntryCanonicalBytes -Read $e1 -KeyOrder (Get-EntryKeyOrder -Paths $p)) -eq '')
$r = Run @('move-menu', '-From', 'drag-lint > Uses & Dependencies', '-To', 'drag-lint > Elsewhere')
Check 'move-menu with no match exits 1' ($r.Code -eq 1)
$r = Run @('move-menu', '-From', 'drag-lint > Reports', '-To', 'drag-lint > Charts', '-Json')
$cq = Get-Content -LiteralPath (Join-Path $S 'features\families\chart-questions.json') -Raw | ConvertFrom-Json
Check 'move-menu over the Reports node rewrites the chart family menuPrefix' (($r.Code -eq 0) -and ($cq.defaults.menuPrefix -eq 'drag-lint > Charts'))
$cqNew = @(Get-Content -LiteralPath (Join-Path $S 'features\families\chart-questions.json')); $cqOld = @(Get-Content -LiteralPath (Join-Path $Repo 'features\families\chart-questions.json'))
$cqDiff = @(for ($i = 0; $i -lt [Math]::Max($cqNew.Count, $cqOld.Count); $i++) { if ($cqNew[$i] -cne $cqOld[$i]) { $i } })
Check 'and edits only that one line of the hand-laid-out family file' (($cqNew.Count -eq $cqOld.Count) -and ($cqDiff.Count -eq 1)) "($($cqDiff.Count) line(s) differ)"

# --- deprecate --------------------------------------------------------------
$r = Run @('deprecate', '-Id', 'zz-new-group-feature', '-SupersededBy', 'uses-report-csv')
$e2 = Read-FeatureEntry -Path (Join-Path $S 'features\entries\zz-new-group-feature.json')
Check 'deprecate sets status and supersededBy' (($r.Code -eq 0) -and ($e2.Entry.status -eq 'deprecated') -and ($e2.Entry.supersededBy -eq 'uses-report-csv'))
$r = Run @('deprecate', '-Id', 'uses-report-csv', '-SupersededBy', 'no-such-id')
Check 'deprecate refuses an unknown successor' ($r.Code -eq 1)

# --- check (well-formed) and normalise ------------------------------------------
$r = Run @('check', '-Level', 'WellFormed')
Check 'check WellFormed passes on the scratch registry' ($r.Code -eq 0) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)
$lf = ([IO.File]::ReadAllText($f1)) -replace "`r`n", "`n"; [IO.File]::WriteAllText($f1, $lf, [Text.Encoding]::ASCII)
$r = Run @('check', '-Level', 'WellFormed')
Check 'check reports an LF entry as not canonical, naming it' (($r.Code -eq 1) -and ($r.Out -match 'uses-report-csv\.json: not canonical'))
$r = Run @('normalise')
Check 'normalise rewrites it and names the file' (($r.Code -eq 0) -and ($r.Out -match 'uses-report-csv\.json'))
Check 'and nothing else (the engine writes are already canonical)' ($r.Out -match 'normalised 1 file') ($r.Out.Trim() -split "`n" | Select-Object -First 1)
$r = Run @('normalise')
Check 'a second normalise rewrites nothing' (($r.Code -eq 0) -and ($r.Out -match '0 file'))
$r = Run @('check', '-Level', 'WellFormed')
Check 'check passes again' ($r.Code -eq 0)
$r = Run @('bogus-verb')
Check 'an unknown verb exits 2' ($r.Code -eq 2)

Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY CLI: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY CLI: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-feature-registry-cli-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
