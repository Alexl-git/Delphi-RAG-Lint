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

# Fix round 1, finding 1: add is ATOMIC -- a refused entry writes no group/team either.
$gSha = Sha (Join-Path $S 'features\groups.json'); $tSha = Sha (Join-Path $S 'features\teams.json')
$r = Run @('add', '-Id', 'zz-atomic', '-Title', 'Atomic add', '-Group', 'zz-atomic-group', '-Owner', 'ZZATOMIC', '-Summary', 'Too short.', '-Intro', 'x', '-WikiPage', 'Maintenance', '-Surface', 'cli:info', '-NewGroup', '-GroupTitle', 'Atomic group', '-GroupSummary', 'Never written.', '-NewTeam', '-TeamTitle', 'Atomic team', '-TeamSummary', 'Never written.')
Check 'add -NewGroup -NewTeam with an invalid entry is refused' (($r.Code -eq 1) -and ($r.Out -match 'nothing written')) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
Check 'and leaves groups.json and teams.json byte-identical' (((Sha (Join-Path $S 'features\groups.json')) -eq $gSha) -and ((Sha (Join-Path $S 'features\teams.json')) -eq $tSha) -and -not (Test-Path -LiteralPath (Join-Path $S 'features\entries\zz-atomic.json')))
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

# Fix round 1, finding 3: move-menu is ATOMIC -- an unreadable family file
# (LF endings: Read-FamilyDefinition refuses it) aborts BEFORE any entry is written.
$cqPath = Join-Path $S 'features\families\chart-questions.json'; $cqSave = [IO.File]::ReadAllBytes($cqPath)
[IO.File]::WriteAllText($cqPath, ([IO.File]::ReadAllText($cqPath) -replace "`r`n", "`n"), [Text.Encoding]::ASCII)
$entSha = @(Get-ChildItem -LiteralPath (Join-Path $S 'features\entries') -File | Sort-Object Name | ForEach-Object { $_.Name + '=' + (Sha $_.FullName) }) -join ';'
$r = Run @('move-menu', '-From', 'drag-lint > Dependencies', '-To', 'drag-lint > Deps')
$entSha2 = @(Get-ChildItem -LiteralPath (Join-Path $S 'features\entries') -File | Sort-Object Name | ForEach-Object { $_.Name + '=' + (Sha $_.FullName) }) -join ';'
Check 'move-menu with a broken family file is refused, naming it' (($r.Code -eq 1) -and ($r.Out -match 'chart-questions\.json')) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
Check 'and leaves every entry file byte-identical (the matching one included)' ($entSha2 -eq $entSha)
[IO.File]::WriteAllBytes($cqPath, $cqSave)
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
# Check A polices the templates' ASCII/CRLF, so normalise must repair their line
# endings and trailing newline too (an LF template with no final newline).
$tplF = Join-Path $S 'features\templates\Home.intro.md'
$tplOrig = [IO.File]::ReadAllText($tplF)
[IO.File]::WriteAllText($tplF, ($tplOrig -replace "`r`n", "`n").TrimEnd("`n"), [Text.Encoding]::ASCII)
$r = Run @('check', '-Level', 'WellFormed')
Check 'check reports an LF template, naming it' (($r.Code -eq 1) -and ($r.Out -match 'Home\.intro\.md')) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)
$r = Run @('normalise')
Check 'normalise repairs the template (CRLF + trailing newline) and names it' (($r.Code -eq 0) -and ($r.Out -match 'Home\.intro\.md') -and ([IO.File]::ReadAllText($tplF) -ceq $tplOrig)) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
$r = Run @('check', '-Level', 'WellFormed')
Check 'check passes again' ($r.Code -eq 0)
$r = Run @('bogus-verb')
Check 'an unknown verb exits 2' ($r.Code -eq 2)

# --- Fix round 1, finding 2: family children, on a LIVE scratch repo --------
# A second scratch repo with what Get-LiveSurface reads (engine exe for --help
# and rules --json only, the harvested sources, the full wiki page set) plus the
# two family parent entries. Spec 18: blast-radius sees what move-menu touches.
$L = Join-Path $WorkDir 'live'
$dl = Join-Path $L 'third_party\dll-win64'
New-Item -ItemType Directory -Path (Join-Path $L 'features\entries'), (Join-Path $L 'docs\wiki'), $dl, (Join-Path $L 'tests\autotest'), (Join-Path $L 'build'), (Join-Path $L 'charts') -Force | Out-Null
foreach ($d in 'schema', 'families') { Copy-Item -LiteralPath (Join-Path $Repo "features\$d") -Destination (Join-Path $L 'features') -Recurse -Force }
foreach ($x in 'groups.json', 'teams.json', 'exemptions.json', 'related-projects.json') { Copy-Item -LiteralPath (Join-Path $Repo "features\$x") -Destination (Join-Path $L 'features') -Force }
Copy-Item -LiteralPath (Join-Path $Repo 'CHANGELOG.md') -Destination $L -Force
Get-ChildItem -LiteralPath (Join-Path $Repo 'docs\wiki') -Filter '*.md' -File | Copy-Item -Destination (Join-Path $L 'docs\wiki') -Force
foreach ($x in 'src\core\DRagLint.Core.Model.pas', 'src\cli\DRagLint.CLI.pas', 'src\storage\DRagLint.Storage.Schema.pas', 'src\mcp\DRagLint.MCP.Server.pas',
               'src\delphi-plugin\DragLint.Plugin.Editor.pas', 'src\delphi-plugin\DragLint.Plugin.AboutForm.pas', 'src\delphi-plugin\DragLint.Plugin.ReportText.pas', 'build\pack-lint-release.ps1',
               'src\delphi-plugin\DragLint.Plugin.StructureForm.pas', 'src\delphi-plugin\DragLint.Plugin.ProjectMenu.pas') {
  $to = Join-Path $L $x; New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null; Copy-Item -LiteralPath (Join-Path $Repo $x) -Destination $to -Force
}
Copy-Item -LiteralPath (Join-Path $Repo 'charts\src') -Destination (Join-Path $L 'charts') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Repo 'tests\autotest\lib') -Destination (Join-Path $L 'tests\autotest') -Recurse -Force
$srcDl = Join-Path $Repo 'third_party\dll-win64'
Get-ChildItem -LiteralPath $srcDl -File | Where-Object { $_.Name -eq 'drag-lint.exe' -or $_.Name -like 'tree-sitter*.dll' } | Copy-Item -Destination $dl -Force
Copy-Item -LiteralPath (Join-Path $srcDl 'rules') -Destination $dl -Recurse -Force
$pl = Get-RegistryPaths -Repo $L
$today = Get-Date -Format 'yyyy-MM-dd'; $bld = Get-CurrentBuildVersion -Paths $pl
$parents = @(
  [ordered]@{ id = 'lint-rules'; title = 'Lint rules'; group = 'linting'; owner = 'ENGINE'; status = 'shipped'; since = $bld; summary = 'Every lint rule the engine ships, from rules --json'; intro = 'The rule family.'; wikiPage = 'rules'; surfaces = @([ordered]@{ type = 'cli'; verb = 'rules' }); audience = 'both'; family = 'lint-rules'; lastVerified = [ordered]@{ date = $today; by = 'guard'; build = $bld } },
  [ordered]@{ id = 'chart-questions'; title = 'Chart questions'; group = 'diagrams-charts'; owner = 'CHARTS'; status = 'shipped'; since = $bld; summary = 'Every chart question of the Reports submenu and Ask-Report.ps1'; intro = 'The chart family.'; wikiPage = 'Diagrams-and-Charts'; surfaces = @([ordered]@{ type = 'script'; path = 'charts\src\Ask-Report.ps1' }); audience = 'both'; family = 'chart-questions'; lastVerified = [ordered]@{ date = $today; by = 'guard'; build = $bld } })
foreach ($pe in $parents) { [void](Write-FeatureEntry -Entry $pe -Path (Join-Path $pl.Entries "$($pe.id).json") -KeyOrder (Get-EntryKeyOrder -Paths $pl)) }
function RunL { param([string[]]$ArgList) $o = & pwsh -NoProfile -File $cli @ArgList -Repo $L 2>&1 | Out-String; return [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
function JsonRows([string]$Out) { $i = $Out.IndexOf('['); $j = $Out.IndexOf('{'); $k = if ($i -ge 0 -and ($j -lt 0 -or $i -lt $j)) { $i } else { $j }; if ($k -lt 0) { return @() }; return @($Out.Substring($k) | ConvertFrom-Json) }

$r = RunL @('blast-radius', '-MenuPath', 'drag-lint > Reports', '-Json')
$rows = JsonRows $r.Out
Check 'blast-radius on the Reports node lists the chart FAMILY (one row, family file)' (($r.Code -eq 0) -and (@($rows | Where-Object { $_.Id -eq 'chart-questions' -and $_.File -like '*chart-questions.json' }).Count -eq 1)) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
Check 'and, without -IncludeChildren, no chart children' (@($rows | Where-Object { $_.Id -like 'chart.*' }).Count -eq 0)
$r = RunL @('blast-radius', '-MenuPath', 'drag-lint > Reports', '-IncludeChildren', '-Json')
$rows = JsonRows $r.Out
$kids = @($rows | Where-Object { $_.Id -like 'chart.*' })
Check 'blast-radius -IncludeChildren also lists every chart child' (($r.Code -eq 0) -and ($kids.Count -gt 20) -and (@($kids | Where-Object { $_.Id -eq 'chart.who-writes' }).Count -eq 1)) "($($kids.Count) children)"
$r = RunL @('find', '-Text', 'who writes', '-Json')
Check 'find without -IncludeChildren does not see a chart child (control)' ($r.Code -eq 1)
$r = RunL @('find', '-Text', 'who writes', '-IncludeChildren', '-Json')
Check 'find -IncludeChildren hits a chart child' (($r.Code -eq 0) -and ($r.Out -match '"Id":\s*"chart\.who-writes"'))
$r = RunL @('add', '-Id', 'zz-related-ok', '-Title', 'Related ok', '-Group', 'maintenance', '-Owner', 'ENGINE', '-Summary', 'Names a real chart child in related', '-Intro', 'x', '-WikiPage', 'Maintenance', '-Surface', 'cli:info', '-Related', 'chart.who-calls')
Check 'add -Related chart.<real id> is accepted' (($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $pl.Entries 'zz-related-ok.json'))) ($r.Out.Trim() -split "`n" | Select-Object -First 1)
$r = RunL @('update', '-Id', 'zz-related-ok', '-Set', 'related=["chart.what-it-calls"]')
$eR = Read-FeatureEntry -Path (Join-Path $pl.Entries 'zz-related-ok.json')
Check 'update -Set with a ONE-element JSON array stores an array' (($r.Code -eq 0) -and ((@($eR.Entry.related) -join ',') -eq 'chart.what-it-calls')) ($r.Out.Trim() -split "`n" | Select-Object -Skip 1 -First 1)
$r = RunL @('update', '-Id', 'zz-related-ok', '-Set', 'related=["chart.who-cals"]')
Check 'update -Set related=chart.<typo> is refused with nearest candidates' (($r.Code -eq 1) -and ($r.Out -match "related 'chart\.who-cals'") -and ($r.Out -match 'did you mean:[^\r\n]*chart\.who-calls') -and ($r.Out -notmatch 'schema:')) ($r.Out.Trim() -split "`n" | Select-Object -Skip 1 -First 1)
Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY CLI: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY CLI: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-feature-registry-cli-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
