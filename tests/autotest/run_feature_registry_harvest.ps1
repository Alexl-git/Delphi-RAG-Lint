#Requires -Version 7.3
<#
  run_feature_registry_harvest.ps1 -- the live-surface harvest the registry
  compares against is non-empty, agrees with its independent second sources,
  and the caption normaliser handles '&&' and '...' (Review Focus 4).

  The harvest lib is SHARED with run_docs_sync_guard.ps1 (checks 1 and 5 call
  it), so this runner also executes docs-sync as a child and requires PASS: an
  extraction that changed either guard's behaviour fails here, not in review.
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== feature registry: live-surface harvest ==' -ForegroundColor Cyan

$lib = Join-Path $Repo 'tests\autotest\lib\DocsSurfaceHarvest.ps1'
Check 'harvest lib present' (Test-Path -LiteralPath $lib) $lib
if (-not (Test-Path -LiteralPath $lib)) { Write-Host 'FEATURE REGISTRY HARVEST: FAIL' -ForegroundColor Red; exit 1 }
. $lib

# --- lib functions ----------------------------------------------------------
$planted = "Usage:`r`n  drag-lint query [--name X]`r`n  drag-lint zz-planted-verb --x`r`n     continuation line`r`n"
$pv = @(Get-HelpVerbList -HelpText $planted)
Check 'Get-HelpVerbList sees a planted verb line and not a continuation' (($pv -contains 'zz-planted-verb') -and ($pv -contains 'query') -and ($pv.Count -eq 2)) ($pv -join ' ')
# The normaliser also trims a trailing '(' / ')' (pre-extraction behaviour, kept
# byte-identical), so 'Call Graph (Butterfly)...' keys to 'call graph (butterfly'.
Check 'REVIEW FOCUS 4: Get-CaptionKey folds && and ...' ((Get-CaptionKey -S 'Uses && Dependencies') -eq 'uses & dependencies' -and (Get-CaptionKey -S 'Who calls this routine...') -eq 'who calls this routine' -and (Get-CaptionKey -S 'Call Graph (Butterfly)...') -eq 'call graph (butterfly')
Check 'Test-CaptionKeyMatch accepts a doc prefix of a live caption' (Test-CaptionKeyMatch -Key 'call graph' -LiveKeys @('call graph (butterfly)', 'about'))
Check 'Test-CaptionKeyMatch rejects an unrelated key' (-not (Test-CaptionKeyMatch -Key 'zz not a real menu item' -LiveKeys @('call graph (butterfly)', 'about')))
$caps = Get-LiveMenuCaptions -Repo $Repo
Check 'live captions harvested (>= 40)' ($caps.Count -ge 40) "($($caps.Count))"
Check 'a real caption is present' ($caps.Contains('About')) "'About'"
Check 'an invented caption is absent' (-not $caps.Contains('Zz Not A Real Menu Item'))
Check 'a Reports catalog caption is present' ($caps.Contains('Who calls this routine...'))

# --- module Get-LiveSurface -------------------------------------------------
Import-Module (Join-Path $Repo 'tools\FeatureRegistry.psm1') -Force
$p = Get-RegistryPaths -Repo $Repo
$live = Get-LiveSurface -Paths $p
Check '--help verbs > 20' ($live.HelpVerbs.Count -gt 20) "($($live.HelpVerbs.Count))"
Check 'dispatch verbs >= help verbs' ($live.DispatchVerbs.Count -ge $live.HelpVerbs.Count) "dispatch=$($live.DispatchVerbs.Count) help=$($live.HelpVerbs.Count)"
Check 'subcommand map derived' (@($live.SubMap.VerbSubs['query']).Count -gt 3) "query: $(@($live.SubMap.VerbSubs['query']) -join ' ')"
Check 'MCP tools harvested and equal to the dispatch chain' (($live.McpTools.Count -ge 10) -and (($live.McpTools | Sort-Object) -join ',') -eq (($live.McpDispatch | Sort-Object) -join ',')) "tools=$($live.McpTools.Count) dispatch=$($live.McpDispatch.Count)"
Check 'rule catalog total > 0' ([int]$live.RuleCatalog.summary.total -gt 0) "total=$($live.RuleCatalog.summary.total)"
Check 'report questions == REPORT_QUESTION_COUNT == ValidateSet' (($live.ReportQuestions.Count -eq $live.ReportQuestionCount) -and ($live.ChartValidateSet.Count -eq $live.ReportQuestionCount)) "questions=$($live.ReportQuestions.Count) const=$($live.ReportQuestionCount) validateset=$($live.ChartValidateSet.Count)"
Check 'group captions cover every question Kind' (@($live.ReportQuestions | Where-Object { -not $live.GroupCaptions.ContainsKey($_.Kind) }).Count -eq 0)
Check 'emitter files harvested without Emit-Common' (($live.EmitterFiles.Count -ge 20) -and ($live.EmitterFiles -notcontains 'Emit-Common.ps1')) "($($live.EmitterFiles.Count))"
Check 'pack payload exes harvested' (($live.PackExes -contains 'drag-lint.exe') -and ($live.PackExes -contains 'ConvRulesEditor.exe')) ($live.PackExes -join ' ')
$verOut = (& $p.Exe --version 2>$null | Out-String).Trim()
Check 'REVIEW FOCUS 5: product version read from source equals --version stdout' ($verOut -eq ('drag-lint ' + $live.Versions.Product)) "'$verOut' vs source '$($live.Versions.Product)'"
Check 'extractor, resolver and schema versions read' (($live.Versions.Extractor -match '^\d') -and ($live.Versions.Resolver -match '^\d') -and ([int]$live.Versions.Schema -gt 0)) "$($live.Versions.Extractor) / $($live.Versions.Resolver) / $($live.Versions.Schema)"
Check 'About buttons harvested' ($live.AboutButtons.Count -ge 3) "($($live.AboutButtons.Count))"

# --- the shared guard still passes after the extraction ----------------------
$ds = Join-Path $Repo 'tests\autotest\run_docs_sync_guard.ps1'
$out = & pwsh -NoProfile -File $ds 2>&1 | Out-String
Check 'run_docs_sync_guard.ps1 PASSES with the lib' ($LASTEXITCODE -eq 0 -and $out -match 'DOCS SYNC GUARD: PASS') "exit $LASTEXITCODE"
Check 'docs-sync no longer defines its own Get-CaptionKey' (-not ((Get-Content -LiteralPath $ds -Raw) -match '(?m)^function Get-CaptionKey'))
Check 'docs-sync dot-sources the lib' ((Get-Content -LiteralPath $ds -Raw) -match 'DocsSurfaceHarvest\.ps1')

Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY HARVEST: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY HARVEST: PASS' -ForegroundColor Green
exit 0
