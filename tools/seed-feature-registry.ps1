#Requires -Version 7.3
<#
  seed-feature-registry.ps1 -- ONE-SHOT migration of docs\wiki-featuremap.tsv,
  the hand-written Features.md / Feature-Index.md / Home.md and the live
  surface into features\entries\*.json. Deleted in the commit that lands the
  seed: a seed that stays is a second generator. Spec section 10.
#>
[CmdletBinding()]
param([string]$Repo = (Split-Path -Parent $PSScriptRoot), [string]$Today = (Get-Date -Format 'yyyy-MM-dd'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'FeatureRegistry.psm1') -Force
$p = Get-RegistryPaths -Repo $Repo
. $p.HarvestLib
$live = Get-LiveSurface -Paths $p
$ctx = Get-RegistryContext -Paths $p
$keys = $ctx.KeyOrder
$build = $live.Versions.Product
if ((Get-ChildItem -LiteralPath $p.Entries -Filter '*.json' -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) { throw 'seed: features\entries is not empty; the seed runs once, on an empty registry' }

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
# Sort-OrdinalUnique is module-internal (not exported); a local copy. WRAPPED.
function SortOrdinalUnique([string[]]$Items) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($i in @($Items)) { if ($null -ne $i) { [void]$set.Add([string]$i) } }
  $arr = [string[]]@($set); [Array]::Sort($arr, [System.StringComparer]::Ordinal)
  return ,$arr
}
# Get-EntryList is WRAPPED (one pipeline object); this unrolls it for a pipeline.
function SurfacesOf([System.Collections.IDictionary]$E) { foreach ($s in (Get-EntryList $E 'surfaces')) { $s } }
function ToAscii([string]$S) {
  $s = $S.Replace([string][char]0x2014, '--').Replace([string][char]0x2013, '-').Replace([string][char]0x2018, "'").Replace([string][char]0x2019, "'").Replace([string][char]0x201C, '"').Replace([string][char]0x201D, '"').Replace([string][char]0x2026, '...')
  return (($s.ToCharArray() | Where-Object { [int]$_ -le 127 }) -join '')
}
function ToId([string]$Page) {
  $id = ($Page.ToLowerInvariant() -replace '[^a-z0-9-]', '-') -replace '-+', '-'
  $id = $id.Trim('-'); if ($id.Length -lt 3) { $id = $id + '-page' }
  return $id
}
function StripMd([string]$S) {
  $s = $S -replace '\[([^\]]+)\]\([^)]*\)', '$1'
  $s = $s -replace '[`*_]', ''
  return (($s -replace '\s+', ' ').Trim())
}
function PageSummary([string]$Page, [string]$Title) {
  $f = Join-Path $p.Wiki "$Page.md"
  $para = @()
  if (Test-Path -LiteralPath $f) {
    $inFence = $false
    foreach ($line in (Get-Content -LiteralPath $f)) {
      if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
      if ($inFence) { continue }
      if ($para.Count -eq 0 -and ($line -match '^\s*$' -or $line -match '^(#|>|\||[-*]\s|\d+\.\s|<!--)')) { continue }
      if ($line -match '^\s*$') { break }
      $para += $line
    }
  }
  $text = ToAscii (StripMd ($para -join ' '))
  $sentence = ($text -split '(?<=[.!?])\s+')[0]
  $sentence = ShortenSummary $sentence
  if ($sentence.Length -lt 20) { $sentence = ShortenSummary "$Title -- see the wiki page" }
  return $sentence
}
# A summary carries no trailing period (Quick-Help adds one), so a long
# sentence is cut at the last clause break that fits -- never with '...',
# which would end it in a period. Falls back to the last word boundary.
function ShortenSummary([string]$S) {
  $s = $S.TrimEnd('.', ' ', ',', ';', ':')
  if ($s.Length -le 160) { return $s }
  $head = $s.Substring(0, 160)
  $cut = -1
  foreach ($sep in @(' -- ', '; ', ': ', ', ', ' (')) { $i = $head.LastIndexOf($sep, [StringComparison]::Ordinal); if ($i -gt $cut) { $cut = $i } }
  if ($cut -lt 60) { $cut = $head.LastIndexOf(' ') }
  return $head.Substring(0, $cut).TrimEnd('.', ' ', ',', ';', ':', '(', '-')
}
$changelogSections = New-Object 'System.Collections.Generic.List[object]'
$clText = Get-Content -LiteralPath $p.Changelog -Raw
$clMatches = @([regex]::Matches($clText, '(?m)^## v(\d+\.\d+\.\d+(?:-alpha)?)'))
for ($i = 0; $i -lt $clMatches.Count; $i++) {
  $start = $clMatches[$i].Index; $end = if ($i + 1 -lt $clMatches.Count) { $clMatches[$i + 1].Index } else { $clText.Length }
  $changelogSections.Add([pscustomobject]@{ Version = $clMatches[$i].Groups[1].Value; Body = $clText.Substring($start, $end - $start) })
}
function SinceOf([string[]]$Tokens, [string[]]$Phrases) {
  # oldest section first (the list is newest-first in the file)
  for ($i = $changelogSections.Count - 1; $i -ge 0; $i--) {
    $b = $changelogSections[$i].Body
    foreach ($t in $Tokens) { if ($t -and ($b -match ('(^|[^a-z-])' + [regex]::Escape($t) + '([^a-z-]|$)'))) { return $changelogSections[$i].Version } }
    foreach ($ph in $Phrases) { if ($ph -and $b.ToLowerInvariant().Contains($ph.ToLowerInvariant())) { return $changelogSections[$i].Version } }
  }
  return ''
}
function AddSurface([System.Collections.IDictionary]$E, [System.Collections.IDictionary]$S) {
  $sig = ConvertTo-CanonicalJson -Value $S
  foreach ($x in @($E['surfaces'])) { if ((ConvertTo-CanonicalJson -Value $x) -ceq $sig) { return } }
  $E['surfaces'] = @($E['surfaces']) + @($S)
}
function AddNote([System.Collections.IDictionary]$E, [string]$Note) {
  $cur = [string]$E['notes']
  if ($cur -like "*$Note*") { return }
  $E['notes'] = $(if ($cur) { $cur + '; ' + $Note } else { $Note })
}
function ParseCli([string]$CliVerb) {
  $out = @()
  $v = $CliVerb.Trim()
  if ($v -eq '' -or $v.StartsWith('(')) { return ,$out }
  $v = $v -replace '\s*\([^)]*\)', ''
  foreach ($part in ($v -split '\s*\+\s*')) {
    $toks = @($part.Trim() -split '\s+' | Where-Object { $_ })
    if ($toks.Count -eq 0) { continue }
    $verb = $toks[0]
    if ($live.DispatchVerbs -notcontains $verb) { Write-Host "  [seed] skipped unknown verb token '$verb' in '$CliVerb'" -ForegroundColor DarkGray; continue }
    $s = [ordered]@{ type = 'cli'; verb = $verb }
    if ($toks.Count -gt 1) {
      $sub = $toks[1]
      if ((@($live.SubMap.VerbSubs.Keys) -contains $verb) -and (@($live.SubMap.VerbSubs[$verb]) -contains $sub)) { $s['sub'] = $sub }
      else { $s['example'] = 'drag-lint ' + $part.Trim() }
    }
    $out += $s
  }
  return ,$out
}
function GroupTitleToId([string]$Title) {
  $t = ($Title -replace '\s*\*.*$', '').Trim()
  foreach ($g in $ctx.Groups.Values) { if ([string]$g.title -eq $t) { return [string]$g.id } }
  return ''
}

# ---------------------------------------------------------------------------
# inputs
# ---------------------------------------------------------------------------
$tsvPath = Join-Path $Repo 'docs\wiki-featuremap.tsv'
if (-not (Test-Path -LiteralPath $tsvPath)) { throw "seed: $tsvPath not found (it is gitignored; this seed runs on the box that has it)" }
$tsv = @(Import-Csv -LiteralPath $tsvPath -Delimiter "`t")
if ($tsv.Count -lt 100) { throw "seed: TSV has $($tsv.Count) rows; expected ~126" }
$featuresMd = Get-Content -LiteralPath (Join-Path $p.Wiki 'Features.md') -Raw
$featureIndexMd = Get-Content -LiteralPath (Join-Path $p.Wiki 'Feature-Index.md') -Raw
$homeMd = Get-Content -LiteralPath (Join-Path $p.Wiki 'Home.md') -Raw
$pageGroup = @{}; $verbGroup = @{}
$section = ''
foreach ($line in ($featuresMd -split "`r?`n")) {
  if ($line -match '^## (.+)$') { $section = GroupTitleToId $Matches[1]; continue }
  if (-not $section) { continue }
  foreach ($m in [regex]::Matches($line, '\]\(([A-Za-z0-9-]+)\)')) { if (-not $pageGroup.ContainsKey($m.Groups[1].Value)) { $pageGroup[$m.Groups[1].Value] = $section } }
  foreach ($m in [regex]::Matches($line, '`([a-z][a-z0-9-]*)')) { if (-not $verbGroup.ContainsKey($m.Groups[1].Value)) { $verbGroup[$m.Groups[1].Value] = $section } }
}
$fiRows = @(); $section = ''
foreach ($line in ($featureIndexMd -split "`r?`n")) {
  if ($line -match '^## (.+)$') { $section = $Matches[1].Trim(); continue }
  $m = [regex]::Match($line, '^\* \[([^\]]+)\]\(([A-Za-z0-9-]+)\)(?: -- `([^`]+)`)?')
  if ($m.Success) { $fiRows += [pscustomobject]@{ Title = $m.Groups[1].Value; Page = $m.Groups[2].Value; Cmd = $m.Groups[3].Value; Section = $section } }
}
$dsText = Get-Content -LiteralPath (Join-Path $Repo 'tests\autotest\run_docs_sync_guard.ps1') -Raw
$uop = [regex]::Match($dsText, '(?s)\$UndocumentedOnPurpose\s*=\s*\[ordered\]@\{(.*?)\n\}')
$internalVerbs = [ordered]@{}
foreach ($m in [regex]::Matches($uop.Groups[1].Value, "'([a-z-]+)'\s*=\s*'([^']+)'")) { $internalVerbs[$m.Groups[1].Value] = $m.Groups[2].Value }
if ($internalVerbs.Count -lt 5) { throw "seed: parsed only $($internalVerbs.Count) UndocumentedOnPurpose verbs" }

# ---------------------------------------------------------------------------
# entries, keyed by wiki page
# ---------------------------------------------------------------------------
$entries = [ordered]@{}
function GetEntry([string]$Page, [string]$Title) {
  if ($entries.Contains($Page)) { return $entries[$Page] }
  $e = [ordered]@{ id = (ToId $Page); title = (ToAscii ($Title -replace '\.\.\.$', '' -replace '\s*\(context\)$', '')).Trim(); group = ''; owner = 'ENGINE'; status = 'shipped'; since = ''
                   summary = ''; wikiPage = $Page; surfaces = @(); audience = 'both'; requires = @(); notes = '' }
  if ($e['title'].Length -lt 3) { $e['title'] = $e['title'] + ' (verb)' }
  if ($e['title'].Length -gt 80) { $e['title'] = $e['title'].Substring(0, 77).TrimEnd() + '...' }
  $entries[$Page] = $e
  return $e
}
foreach ($row in $tsv) {
  $e = GetEntry $row.WikiPage $row.Feature
  $mp = [string]$row.MenuPath
  if ($mp -like 'drag-lint > *') { AddSurface $e ([ordered]@{ type = 'ide-menu'; path = (ToAscii $mp) }) }
  elseif ($mp -like 'View > Tool Windows > *') { AddSurface $e ([ordered]@{ type = 'tool-window'; path = $mp }) }
  elseif ($mp -like 'Structure form*') { AddSurface $e ([ordered]@{ type = 'ide-context'; host = 'Structure form'; caption = $e['title'] }) }
  elseif ($mp -like 'Project Manager*') { AddSurface $e ([ordered]@{ type = 'ide-context'; host = 'Project Manager'; caption = $e['title'] }) }
  elseif ($mp -like 'plugin (non-menu):*') { AddNote $e ('issued by the plugin from ' + ($mp -replace '^plugin \(non-menu\):\s*', '')) }
  foreach ($s in (ParseCli ([string]$row.CliVerb))) { AddSurface $e $s }
  if ([string]$row.Index -eq 'required') { $e['requires'] = @('index') }
}
foreach ($r in $fiRows) {
  if ($entries.Contains($r.Page)) { continue }
  # The 'Diagrams and charts' section lists the chart QUESTIONS (ask-* pages,
  # Field-Round-Trip-Report): those are family children, never hand entries.
  if ($r.Section -eq 'Diagrams and charts') { continue }
  $e = GetEntry $r.Page $r.Title
  switch -Regex ($r.Section) {
    '^CLI verbs$'            { foreach ($s in (ParseCli $r.Cmd)) { AddSurface $e $s } }
    '^Right-click menus$'    { AddSurface $e ([ordered]@{ type = 'ide-context'; host = 'Structure form'; caption = $e['title'] }) }
    '^Main menu$'            { AddSurface $e ([ordered]@{ type = 'ide-menu'; path = 'drag-lint > ' + $r.Title }) }
    '^Tool windows$'         { AddSurface $e ([ordered]@{ type = 'tool-window'; path = 'View > Tool Windows > ' + $r.Title }) }
  }
}
# verbs in --help with no surface anywhere (spec 10.3)
$covered = @($entries.Values | ForEach-Object { SurfacesOf $_ } | Where-Object { $_['type'] -eq 'cli' } | ForEach-Object { [string]$_['verb'] } | Sort-Object -Unique)
foreach ($v in $live.HelpVerbs) {
  if ($covered -contains $v) { continue }
  $page = if ($ctx.WikiPages.Contains($v)) { $v } else { 'Features' }
  $e = GetEntry $v $v
  $e['wikiPage'] = $page
  AddSurface $e ([ordered]@{ type = 'cli'; verb = $v })
  if ($page -eq 'Features') { AddNote $e 'seed: needs own page' }
}
# the dispatch-only verbs become internal entries (spec 10.2)
foreach ($v in $internalVerbs.Keys) {
  $e = GetEntry ('internal-' + $v) $v
  $e['id'] = $v; $e['wikiPage'] = 'Maintenance'; $e['status'] = 'internal'; $e['audience'] = 'agent'
  AddSurface $e ([ordered]@{ type = 'cli'; verb = $v })
  AddNote $e ('internal: ' + (ToAscii $internalVerbs[$v]))
}
# ask is planned (spec 10.2)
$ask = GetEntry 'ask-planned' 'ask (engine verb)'
$ask['id'] = 'ask'; $ask['wikiPage'] = 'Diagrams-and-Charts'; $ask['status'] = 'planned'; $ask['group'] = 'diagrams-charts'; $ask['owner'] = 'CHARTS'; $ask['surfaces'] = @()
AddNote $ask 'one engine verb for every chart question; planned, not shipped (Features.md 2026-10-05)'
# the unlinked pages and the hand-written pages that need an entry to be reachable (spec 10.6)
$workflowPages = [ordered]@{
  'Installation'            = @{ title = 'Installation'; group = 'editor-integration'; homeOrder = 20; exe = 'drag-lint.exe' }
  'Maintenance'             = @{ title = 'Maintenance'; group = 'maintenance'; homeOrder = 30 }
  'IDE-Menu-Reference'      = @{ title = 'IDE Menu Reference'; group = 'editor-integration'; homeOrder = 40 }
  'Charts-and-the-IDE'      = @{ title = 'Charts and the IDE'; group = 'diagrams-charts'; homeOrder = 45; owner = 'CHARTS' }
  'Effect-Summary-Legend'   = @{ title = 'Effect Summary Legend'; group = 'documentation' }
  'Wiki-Blocks-Authoring'   = @{ title = 'Wiki blocks authoring'; group = 'documentation' }
  'Circular-Dependency-Report' = @{ title = 'Circular Dependency Report (worked example)'; group = 'graphs-reports' }
}
foreach ($pg in $workflowPages.Keys) {
  $w = $workflowPages[$pg]
  $e = GetEntry $pg $w.title
  $e['group'] = $w.group
  if ($w.ContainsKey('owner')) { $e['owner'] = $w.owner }
  if ($w.ContainsKey('homeOrder')) { $e['homeOrder'] = [int]$w.homeOrder }
  if ($w.ContainsKey('exe')) { AddSurface $e ([ordered]@{ type = 'exe'; name = $w.exe }) }
  AddSurface $e ([ordered]@{ type = 'workflow'; doc = "docs\wiki\$pg.md" })
}
$qd = GetEntry 'query-descendants' 'query descendants'
AddSurface $qd ([ordered]@{ type = 'cli'; verb = 'query'; sub = 'descendants' })
$ab = GetEntry 'About-and-Status' 'About and Status'
$ab['homeOrder'] = 60
foreach ($b in $live.AboutButtons) { AddSurface $ab ([ordered]@{ type = 'ide-about'; caption = $b }) }
$cre = GetEntry 'convrules-editor-page' 'ConvRulesEditor'
$cre['id'] = 'convrules-editor'; $cre['wikiPage'] = 'Features'; $cre['group'] = 'component-conversion'; $cre['owner'] = 'CONVERTER'
AddSurface $cre ([ordered]@{ type = 'exe'; name = 'ConvRulesEditor.exe' }); AddNote $cre 'seed: needs own page (manual: docs\converter\convrules-editor-manual.md)'
# Live captions that are FEATURES but have no TSV row (the 2026-09-07 menu split
# and later): they get surfaces, not a 'structural' exemption. Paths measured
# from RegisterDragLintMenu in src\delphi-plugin\DragLint.Plugin.Editor.pas.
$cpf = GetEntry 'Quick-Fix-Convert-Public-Field-to-Property-at-Cursor' 'Quick-Fix: Convert Public Field to Property at Cursor'
$cpf['surfaces'] = @([ordered]@{ type = 'ide-menu'; path = 'drag-lint > Convert Public Field to Property at Cursor' })
$cpf['group'] = 'refactoring'
AddNote $cpf 'seed: moved from Uses & Dependencies to the root menu on 2026-09-07; the page title still says Quick-Fix'
$drp = GetEntry 'deps-report' 'deps-report'
AddSurface $drp ([ordered]@{ type = 'ide-menu'; path = 'drag-lint > Uses & Dependencies > Dependency Report (third-party rollup)...' })
$udt = GetEntry 'uses-deps-tab-page' 'Uses & Deps Tab'
$udt['id'] = 'uses-deps-tab'; $udt['wikiPage'] = 'Features'; $udt['group'] = 'refactoring'
$udt['summary'] = 'Open the Uses & Deps tab to review uses-clause fixes and apply them'
AddSurface $udt ([ordered]@{ type = 'ide-menu'; path = 'drag-lint > Uses & Dependencies > Uses & Deps Tab -- review & apply fixes...' })
AddNote $udt 'seed: needs own page'
$cdp = GetEntry 'compile-dependents-page' 'Compile Dependents'
$cdp['id'] = 'compile-dependents'; $cdp['wikiPage'] = 'Features'; $cdp['group'] = 'compiler'
$cdp['summary'] = 'Check the units that depend on the one being edited now, instead of waiting for the automatic quiet-period pass (lint-tree tier 3)'
AddSurface $cdp ([ordered]@{ type = 'ide-menu'; path = 'drag-lint > Compile Dependents' })
AddNote $cdp 'seed: needs own page'
# families (spec 10.5)
# The TSV's 'rules' verb row already created an entry keyed by page 'rules'; it
# BECOMES the family entry (the verb is the family's cli surface).
$lr = GetEntry 'rules' 'Lint rules'; $lr['id'] = 'lint-rules'; $lr['title'] = 'Lint rules'; $lr['group'] = 'linting'; $lr['family'] = 'lint-rules'; $lr['surfaces'] = @([ordered]@{ type = 'cli'; verb = 'rules' })
$lr['summary'] = 'Every lint rule the engine ships, imported from rules --json'
$cq = GetEntry 'Diagrams-and-Charts' 'Chart questions'; $cq['id'] = 'chart-questions'; $cq['title'] = 'Chart questions'; $cq['group'] = 'diagrams-charts'; $cq['owner'] = 'CHARTS'; $cq['family'] = 'chart-questions'; $cq['homeOrder'] = 44
$cq['surfaces'] = @([ordered]@{ type = 'script'; path = 'charts\src\Ask-Report.ps1' }, [ordered]@{ type = 'script'; path = 'charts\src\New-DiagramArtifact.ps1' })
$cq['summary'] = 'Every chart question of the Reports submenu and Ask-Report.ps1, imported from REPORT_QUESTIONS'
$cq['requires'] = @('index', 'powershell7', 'graphviz')

# ---------------------------------------------------------------------------
# group, owner, since, summary
# ---------------------------------------------------------------------------
# Pages Features.md never links and whose first verb names no section: the
# seed's own table, so the review does not have to re-place 30 obvious items.
# Anything not listed still falls to 'maintenance' + 'seed: group guessed'.
$groupHints = @{
  'Go-to-Definition' = 'search-navigation'; 'Show-Completion' = 'search-navigation'; 'Show-Signature-Help' = 'search-navigation'
  'Find-Usages' = 'search-navigation'; 'Show-Structure' = 'search-navigation'; 'Go-to-Declaration' = 'search-navigation'
  'Go-to-Implementation' = 'search-navigation'; 'usages' = 'search-navigation'; 'Find-Usages-context' = 'search-navigation'
  'drag-lint-Panel-dockable' = 'editor-integration'; 'drag-lint-Graph-dockable' = 'editor-integration'; 'drag-lint' = 'editor-integration'
  'drag-lint-Graph' = 'editor-integration'; 'drag-lint-Options' = 'editor-integration'; 'lsp' = 'editor-integration'; 'ide-release' = 'editor-integration'
  'Quick-Fix-Add-Unit-for-Undeclared-at-Cursor-Ctrl-Alt-U' = 'refactoring'; 'Quick-Fix-Add-Unit-for-Inline-Hint-H2443-at-Cursor' = 'refactoring'
  'Compile-Diagnose' = 'compiler'; 'Recover-Buffer-Compile-Files' = 'compiler'; 'project-facts' = 'compiler'
  'Run-Diagnostics-didSave' = 'linting'; 'Run-AST-Checks' = 'linting'
  'Export-Graph-DOT' = 'graphs-reports'; 'doc-forget' = 'documentation'; 'purge-locals' = 'indexing'
}
foreach ($k in $groupHints.get_Keys()) { if ($entries.Contains($k) -and -not $entries[$k]['group']) { $entries[$k]['group'] = $groupHints[$k] } }
# The verbs with no page of their own: a real summary instead of a pointer
# (Features.md's row text where it had one; --help's otherwise).
$featureSummaries = @{
  'doc-forget'       = 'Reap or rename the project tags on inbound documentation facts; a dry run unless told to apply'
  'project-facts'    = 'Report what the build does: defines that are on and what sets each, imports, output paths and packages'
  'exceptions-sync'  = 'Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites'
  'glyph-vacuum'     = 'Measure every streamed glyph or picture under a tree before writing a glyph rule'
  'register-project' = 'Add a new project to the manifest so index --all and the IDE can see it'
  'shutdown'         = 'Ask running lsp engines to close their indexes and stand down, so an index can be rebuilt without killing them'
  'convrules-editor-page' = 'Visual rulebook editor for the component-conversion rules'
}
foreach ($k in $featureSummaries.get_Keys()) { if ($entries.Contains($k)) { $entries[$k]['summary'] = $featureSummaries[$k] } }
# Home's 'Start here' rows: the hand-written 'For' text becomes the entry's
# summary (the generated table renders the summary), so the hand wording of
# that table survives too. Diagrams-and-Charts keeps the family summary above.
foreach ($m in [regex]::Matches($homeMd, '(?m)^\| \*\*\[[^\]]+\]\(([A-Za-z0-9-]+)\)\*\* \| (.+?) \|\s*$')) {
  $pg = $m.Groups[1].Value
  if ($pg -in @('Features', 'Feature-Index', 'Diagrams-and-Charts') -or -not $entries.Contains($pg)) { continue }
  $entries[$pg]['summary'] = ShortenSummary (ToAscii (StripMd $m.Groups[2].Value))
}
foreach ($pg in @($entries.Keys)) {
  $e = $entries[$pg]
  $verbs = @(SurfacesOf $e | Where-Object { $_['type'] -eq 'cli' } | ForEach-Object { [string]$_['verb'] })
  if (-not $e['group']) {
    if ($pageGroup.ContainsKey([string]$e['wikiPage']) -and [string]$e['wikiPage'] -ne 'Features') { $e['group'] = $pageGroup[[string]$e['wikiPage']] }
    elseif ($verbs.Count -and $verbGroup.ContainsKey($verbs[0])) { $e['group'] = $verbGroup[$verbs[0]] }
    elseif ($verbs.Count -and ($verbs[0] -like 'convert-*' -or $verbs[0] -in @('glyph-vacuum', 'proptree'))) { $e['group'] = 'component-conversion' }
    elseif ($verbs.Count -and $verbs[0] -eq 'ask') { $e['group'] = 'diagrams-charts' }
    else { $e['group'] = 'maintenance'; AddNote $e 'seed: group guessed' }
  }
  if ($verbs.Count -and ($verbs[0] -like 'convert-*' -or $verbs[0] -in @('glyph-vacuum', 'proptree'))) { $e['owner'] = 'CONVERTER' }
  if (($verbs -contains 'forms-csv') -or ([string]$e['wikiPage'] -eq 'Generate-Test-Helper-CSV')) { $e['owner'] = 'CHARTS' }
  if (-not $e['since']) {
    $phrases = @(SurfacesOf $e | Where-Object { $_['type'] -in @('ide-menu', 'ide-context', 'ide-about', 'tool-window', 'script', 'exe') } | ForEach-Object { $x = $_; switch ($x['type']) { 'ide-menu' { (($x['path'] -split '\s+>\s+')[-1] -replace '\.\.\.$', '') } 'tool-window' { (($x['path'] -split '\s+>\s+')[-1]) } 'script' { Split-Path -Leaf ([string]$x['path']) } 'exe' { [string]$x['name'] } default { [string]$x['caption'] } } })
    $since = if ([string]$e['status'] -eq 'planned') { '' } else { SinceOf $verbs $phrases }
    if ([string]$e['status'] -ne 'planned') {
      if ($since) { $e['since'] = $since } else { $e['since'] = '0.0.0'; AddNote $e 'seed: since unknown' }
    }
  }
  if (-not $e['summary']) {
    $e['summary'] = if ([string]$e['wikiPage'] -eq 'Features') { "$($e['title']) -- described on the Features page until it has a page of its own" } else { PageSummary ([string]$e['wikiPage']) ([string]$e['title']) }
  }
  if ([string]$e['status'] -eq 'planned') { $e.Remove('since') }
}

# ---------------------------------------------------------------------------
# captions with no row (spec 10.4): structural captions -> exemptions.json
# ---------------------------------------------------------------------------
$coveredKeys = @()
foreach ($e in $entries.Values) {
  foreach ($s in (Get-EntryList $e 'surfaces')) {
    switch ([string]$s['type']) {
      'ide-menu'    { $coveredKeys += Get-CaptionKey -S (($s['path'] -split '\s+>\s+')[-1]) }
      'tool-window' { $coveredKeys += Get-CaptionKey -S (($s['path'] -split '\s+>\s+')[-1]) }
      'ide-context' { $coveredKeys += Get-CaptionKey -S ([string]$s['caption']) }
      'ide-about'   { $coveredKeys += Get-CaptionKey -S ([string]$s['caption']) }
    }
  }
}
foreach ($q in $live.ReportQuestions) { $coveredKeys += Get-CaptionKey -S $q.Caption }
$coveredKeys = @($coveredKeys | Where-Object { $_ } | Sort-Object -Unique)
$ex = ConvertTo-OrderedObject ((Get-Content -LiteralPath $p.Exemptions -Raw) | ConvertFrom-Json -AsHashtable)
$structural = @()
foreach ($cap in ($live.Captions | Sort-Object)) {
  $k = Get-CaptionKey -S $cap
  if (-not $k) { continue }
  if (Test-CaptionKeyMatch -Key $k -LiveKeys $coveredKeys) { continue }
  $ex['captions'][$cap] = 'structural: submenu container, section header, report group header or dialog caption -- seeded 2026-10-05, no feature of its own; delete this line when it gains one'
  $structural += $cap
}
[IO.File]::WriteAllText($p.Exemptions, (ConvertTo-CanonicalJson -Value $ex), [Text.Encoding]::ASCII)
Write-Host "  [seed] $($structural.Count) structural caption(s) exempted: $($structural -join ' | ')" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# write entries + backlog
# ---------------------------------------------------------------------------
$backlog = [ordered]@{ ENGINE = @(); CONVERTER = @(); CHARTS = @() }
$written = 0
foreach ($e in $entries.Values) {
  $e.Remove('intro')
  $file = Join-Path $p.Entries ($e['id'] + '.json')
  if (Test-Path -LiteralPath $file) { throw "seed: id collision -- $($e['id']) ($($e['wikiPage']))" }
  [void](Write-FeatureEntry -Entry $e -Path $file -KeyOrder $keys); $written++
  $backlog[[string]$e['owner']] = @($backlog[[string]$e['owner']]) + @([string]$e['id'])
}
foreach ($t in @($backlog.Keys)) { $backlog[$t] = (SortOrdinalUnique ([string[]]@($backlog[$t]))) }
[IO.File]::WriteAllText($p.SeedBacklog, (ConvertTo-CanonicalJson -Value ([ordered]@{ deadline = 'before the R2 installer release (owner decision 15.2)'; teams = $backlog })), [Text.Encoding]::ASCII)
Write-Host "  [seed] wrote $written entries; backlog ENGINE=$($backlog['ENGINE'].Count) CONVERTER=$($backlog['CONVERTER'].Count) CHARTS=$($backlog['CHARTS'].Count)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# templates from today's prose (spec 10.7)
# ---------------------------------------------------------------------------
# Controller ruling: ALL of today's hand prose survives. The generator owns the
# status line, the 'Start here' table and 'Links'; everything else -- the lead
# paragraph above 'Start here' AND the hand sections below the table (the
# one-paragraph model, the two commands, the day-one trap) -- moves into the
# template, in page order.
$homeParts = $homeMd -split '(?m)^(?=## )'
$homeIntro = ($homeParts[0] -split "`r?`n" | Where-Object { $_ -notmatch '^\*\*Status: alpha\*\*' -and $_ -notmatch '^schema version; the CLI surface is not yet frozen\.' }) -join "`r`n"
foreach ($hp in ($homeParts | Select-Object -Skip 1)) {
  if ($hp -match '^## (Start here|Links)\s*$' -or $hp -match '^## (Start here|Links)\r?\n') { continue }
  $homeIntro = $homeIntro.TrimEnd() + "`r`n`r`n" + $hp.TrimEnd()
}
[IO.File]::WriteAllText((Join-Path $p.Templates 'Home.intro.md'), (ToAscii ($homeIntro.TrimEnd() + "`r`n")), [Text.Encoding]::ASCII)
$featIntro = ($featuresMd -split '(?m)^---\s*$')[0]
# The hand page also carried narrative prose INSIDE its sections that no
# registry field holds (suppression markers, the coupling rules, formatting vs
# dl:ok hashes, how a chart question is asked). Carried into the template under
# its own heading rather than dropped; the owning team moves each note to the
# page that owns it.
function SectionOf([string]$Md, [string]$H2) {
  $m = [regex]::Match($Md, '(?ms)^## ' + [regex]::Escape($H2) + '[^\r\n]*\r?\n(.*?)(?=^## |^---\s*$|\z)')
  return $(if ($m.Success) { $m.Groups[1].Value } else { '' })
}
$lintSec = SectionOf $featuresMd 'Linting'
$diagSec = SectionOf $featuresMd 'Diagrams and charts'
$carried = @()
foreach ($rx in @('(?s)\*\*Newest -- .*?(?=\r?\n\s*\r?\nScopes:)', '(?s)Formatting: .*?(?=\r?\n\s*\r?\nSuppression:)', '(?s)Suppression:.*')) {
  $m = [regex]::Match($lintSec, $rx); if (-not $m.Success) { throw "seed: Features.md Linting prose block not found: $rx" }; $carried += $m.Value.Trim()
}
$dm = [regex]::Match($diagSec, '(?s)^\s*(.*?)(?=\r?\n\s*\r?\n\| Feature)'); if (-not $dm.Success) { throw 'seed: Features.md Diagrams prose not found' }
$featIntro = $featIntro.TrimEnd() + "`r`n`r`n## Notes carried over from the hand-written page`r`n`r`n" +
  "These were prose on the hand-written Features page and have no registry field. Each belongs on the page that owns its topic; move it there and delete it here.`r`n`r`n" +
  "### Linting`r`n`r`n" + ($carried -join "`r`n`r`n") + "`r`n`r`n### Diagrams and charts`r`n`r`n" + $dm.Groups[1].Value.Trim()
$featIntro = ($featIntro -split "`r?`n") -join "`r`n"
[IO.File]::WriteAllText((Join-Path $p.Templates 'Features.intro.md'), (ToAscii ($featIntro.TrimEnd() + "`r`n")), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $p.Templates 'Quick-Help.intro.md'), "# Quick Help`r`n`r`nOne line per feature, grouped as on [Features](Features), with the short help and the words people search for. Every line links the feature's own page; this page is generated from the feature registry and never edited by hand.`r`n", [Text.Encoding]::ASCII)

# ---------------------------------------------------------------------------
# validate, generate, assert set inclusion (spec 10.8)
# ---------------------------------------------------------------------------
# Ordinal (case-exact) sets: the GitHub wiki serves only the exact stem, and
# Sort-Object -Unique / -contains would fold 'Rules' into 'rules'.
$handTargets = SortOrdinalUnique ([string[]]@([regex]::Matches(($featuresMd + $featureIndexMd), '\]\(([A-Za-z0-9-]+)\)') | ForEach-Object { $_.Groups[1].Value }))
$res = Invoke-RegistryCheck -Paths $p -Level WellFormed
if ($res.Failures.Count) { foreach ($f in $res.Failures) { Write-Host "  [FAIL] $f" -ForegroundColor Red }; Write-Host 'SEED: FAIL -- the seeded entries are not well-formed' -ForegroundColor Red; exit 1 }
$gen = Invoke-RegistryGenerate -Paths $p
Write-Host "  [seed] generated: $($gen.Written -join ', ')"
$genText = ''
foreach ($n in 'Home.md', 'Features.md', 'Feature-Index.md', 'Quick-Help.md') { $genText += Get-Content -LiteralPath (Join-Path $p.Wiki $n) -Raw }
$genTargets = SortOrdinalUnique ([string[]]@([regex]::Matches($genText, '\]\(([A-Za-z0-9-]+)(?:#[^)]*)?\)') | ForEach-Object { $_.Groups[1].Value }))
$missing = @($handTargets | Where-Object { $genTargets -cnotcontains $_ })
if ($missing.Count) { Write-Host "SEED: FAIL -- pages linked by the hand index but unreachable from the generated pages: $($missing -join ' ')" -ForegroundColor Red; exit 1 }
$guessed = @($entries.Values | Where-Object { [string]$_['notes'] -like '*seed:*' } | ForEach-Object { $_['id'] })
Write-Host "  [seed] $($guessed.Count) entries carry a 'seed:' note for the review: $($guessed -join ' ')" -ForegroundColor DarkGray
$homeNow = Get-Content -LiteralPath (Join-Path $p.Wiki 'Home.md') -Raw
if (-not $homeNow.Contains("current release v$build;")) { Write-Host "SEED: FAIL -- generated Home.md does not read v$build" -ForegroundColor Red; exit 1 }
Write-Host "SEED: PASS -- $written entries (ENGINE=$($backlog['ENGINE'].Count) CONVERTER=$($backlog['CONVERTER'].Count) CHARTS=$($backlog['CHARTS'].Count)), $($handTargets.Count) hand link targets all reachable; Home.md reads v$build" -ForegroundColor Green
exit 0
