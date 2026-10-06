#Requires -Version 7.3
<#
  run_feature_registry_guard.ps1 -- every live surface has a registry entry
  and every entry points at something that exists; the generated pages are
  current and untouched. Spec section 9.

  A  well-formed (schema, canonical bytes, groups/teams, references, ASCII+CRLF)
  B  live -> registry: every --help verb, subcommand, IDE caption, rule,
     chart question and release exe is registered or exempted WITH a reason
  C  registry -> live: every cli / ide-* / tool-window / mcp surface is live
  D  Home.md, Features.md, Feature-Index.md, Quick-Help.md, the two dl:registry
     blocks and manifest.json are byte-identical to a fresh render
  E  staleness is a [NOTE], never a FAIL (the periodic review consumes it)

  POSITIVE CONTROLS run first and declare the guard BROKEN (exit 1) if any
  fails: an injected entry with a missing page must fail C; an injected verb
  and an injected caption must fail B; a flipped byte must fail D; the chart
  importer's count must equal REPORT_QUESTION_COUNT and the ValidateSet.
  Also: an entry outside seed-backlog.json with no intro must fail A (the
  phase-in does not leak); an ide-context surface missing from its host's
  context menu must fail C; an injected Structure-form context item must fail B.
  IDE captions are matched by LEAF only (spec 18 v1); ide-context surfaces are
  matched against their own host's context menu, not the main menu.

  Parameters:
    -Repo     repo root (default: two levels above this script)
    -WorkDir  scratch folder for the check-D control render (created, then
              removed on exit; default under $env:TEMP, unique per process)
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$WorkDir = "$env:TEMP\drag-lint-feature-registry-guard-$PID")
Set-StrictMode -Version Latest
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== feature registry guard ==' -ForegroundColor Cyan
$mod = Join-Path $Repo 'tools\FeatureRegistry.psm1'
if (-not (Test-Path -LiteralPath $mod)) { Write-Host "GUARD BROKEN: $mod missing" -ForegroundColor Red; exit 1 }
Import-Module $mod -Force
$p = Get-RegistryPaths -Repo $Repo
if (-not (Get-Command Invoke-RegistryCheck -ErrorAction SilentlyContinue).Parameters.ContainsKey('InjectEntries')) { Write-Host 'GUARD BROKEN: Invoke-RegistryCheck has no -InjectEntries (Full level not implemented)' -ForegroundColor Red; exit 1 }
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

# ---- controls first ----------------------------------------------------------
Write-Host '-- controls' -ForegroundColor Cyan
$live = Get-LiveSurface -Paths $p
$script:broken = $false
function Control([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  [CTRL] $Name" -ForegroundColor DarkGray } else { Write-Host "  [GUARD BROKEN] $Name $Detail" -ForegroundColor Red; $script:broken = $true }
}
$ghostEntry = [ordered]@{ id = 'zz-ghost-page'; title = 'Ghost page entry'; group = 'maintenance'; owner = 'ENGINE'; status = 'shipped'; since = $live.Versions.Product
  summary = 'Injected by the guard to prove check C can fail'; intro = 'Control.'; wikiPage = 'Zz-No-Such-Page'; surfaces = @([ordered]@{ type = 'cli'; verb = 'info' }); audience = 'both'
  lastVerified = [ordered]@{ date = (Get-Date -Format 'yyyy-MM-dd'); by = 'guard'; build = $live.Versions.Product } }
# Not in seed-backlog.json, so the full standard applies: no intro, no lastVerified must fail A.
$noIntroEntry = [ordered]@{ id = 'zz-no-intro'; title = 'No intro entry'; group = 'maintenance'; owner = 'ENGINE'; status = 'shipped'; since = $live.Versions.Product
  summary = 'Injected by the guard to prove the backlog tolerance does not leak'; wikiPage = 'Home'; surfaces = @([ordered]@{ type = 'cli'; verb = 'info' }); audience = 'both' }
# An ide-context surface is checked against ITS host's menu, not the main menu.
$ghostContext = [ordered]@{ id = 'zz-ghost-context'; title = 'Ghost context entry'; group = 'maintenance'; owner = 'ENGINE'; status = 'shipped'; since = $live.Versions.Product
  summary = 'Injected by the guard to prove the context-menu check can fail'; intro = 'Control.'; wikiPage = 'Home'; surfaces = @([ordered]@{ type = 'ide-context'; host = 'Structure form'; caption = 'Zz Ghost Context Item' }); audience = 'both'
  lastVerified = [ordered]@{ date = (Get-Date -Format 'yyyy-MM-dd'); by = 'guard'; build = $live.Versions.Product } }
$guid = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$ctl = Invoke-RegistryCheck -Paths $p -Level Full -Live $live -SkipGenerated -InjectEntries @($ghostEntry, $noIntroEntry, $ghostContext) -InjectHelpVerbs @("zz-not-a-verb-$guid") -InjectCaptions @('Zz Not A Real Menu Item') -InjectContextCaptions @('Zz Not A Context Item')
Control 'an entry whose wikiPage does not exist is reported (C/A)' (@($ctl.Failures | Where-Object { $_ -like '*Zz-No-Such-Page*' }).Count -gt 0)
Control 'an entry outside the seed backlog with no intro is reported (A)' (@($ctl.Failures | Where-Object { $_ -like 'A: zz-no-intro.json: intro is required*' }).Count -gt 0)
Control 'an ide-context surface absent from its host menu is reported (C)' (@($ctl.Failures | Where-Object { $_ -like 'C: zz-ghost-context: ide-context*Zz Ghost Context Item*' }).Count -gt 0)
Control 'an unregistered context-menu item is reported (B)' (@($ctl.Failures | Where-Object { $_ -like 'B: *Zz Not A Context Item*' }).Count -gt 0)
Control 'an unregistered --help verb is reported with a skeleton (B)' (@($ctl.Failures | Where-Object { $_ -like "B: *zz-not-a-verb-$guid*" -and $_ -like '*"id":*' }).Count -gt 0)
Control 'an unregistered caption is reported (B)' (@($ctl.Failures | Where-Object { $_ -like 'B: *Zz Not A Real Menu Item*' }).Count -gt 0)
[void](Invoke-RegistryGenerate -Paths $p -OutDir $WorkDir)
$fp = Join-Path $WorkDir 'docs\wiki\Quick-Help.md'
$before = [IO.File]::ReadAllText($fp)
$after = $before.Replace('## Declared, not harvested', '## Declared, not harvestec')
Control 'the D control found its flip anchor in the rendered Quick-Help.md' ($after -cne $before)
[IO.File]::WriteAllText($fp, $after, [Text.Encoding]::ASCII)
$flip = Invoke-RegistryGenerate -Paths $p -OutDir $WorkDir -Check
Control 'a flipped byte in a generated page is reported (D)' (($flip.Changed.Count -eq 1) -and ($flip.Changed[0].Path -eq 'docs\wiki\Quick-Help.md'))
$ctx = Get-RegistryContext -Paths $p
$kids = Get-RegistryChildren -Live $live -Entries @($ctx.Entries | ForEach-Object { $_.Entry }) -Paths $p
Control 'chart importer count == REPORT_QUESTION_COUNT == ValidateSet' (($kids.Contains('chart-questions')) -and (@($kids['chart-questions']).Count -eq $live.ReportQuestionCount) -and ($live.ChartValidateSet.Count -eq $live.ReportQuestionCount)) "children=$(@($kids['chart-questions']).Count) const=$($live.ReportQuestionCount) validateset=$($live.ChartValidateSet.Count)"
Control 'lint importer count == summary.total' (($kids.Contains('lint-rules')) -and (@($kids['lint-rules']).Count -eq [int]$live.RuleCatalog.summary.total))
if ($script:broken) { Write-Host 'FEATURE REGISTRY GUARD: GUARD BROKEN -- a control failed; no real check was reported as passed' -ForegroundColor Red; exit 1 }

# ---- the real run ------------------------------------------------------------
Write-Host '-- checks' -ForegroundColor Cyan
$res = Invoke-RegistryCheck -Paths $p -Level Full -Live $live
foreach ($n in $res.Notes) { Write-Host "  [NOTE] $n" -ForegroundColor DarkGray }
Check 'thresholds: entries >= 50, verbs > 20, captions >= 40, rules > 0, questions == constant' (($res.Stats['entries'] -ge 50) -and ($live.HelpVerbs.Count -gt 20) -and ($live.Captions.Count -ge 40) -and ([int]$live.RuleCatalog.summary.total -gt 0) -and ($live.ReportQuestions.Count -eq $live.ReportQuestionCount)) "entries=$($res.Stats['entries']) verbs=$($live.HelpVerbs.Count) captions=$($live.Captions.Count) rules=$($live.RuleCatalog.summary.total)"
foreach ($letter in 'A', 'B', 'C', 'D') {
  $f = @($res.Failures | Where-Object { $_.StartsWith("$letter`: ") })
  $name = switch ($letter) { 'A' { 'A well-formed' } 'B' { 'B live -> registry (nothing unregistered)' } 'C' { 'C registry -> live (nothing dangling)' } 'D' { 'D generated outputs current and untouched' } }
  Check $name ($f.Count -eq 0) "($($f.Count) failure(s))"
  foreach ($x in $f) { Write-Host ("        " + ($x -replace "`n", "`n        ")) -ForegroundColor Red }
}
$other = @($res.Failures | Where-Object { $_ -notmatch '^[ABCD]: ' })
Check 'no uncategorised failure' ($other.Count -eq 0) ($other -join ' | ')

Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
