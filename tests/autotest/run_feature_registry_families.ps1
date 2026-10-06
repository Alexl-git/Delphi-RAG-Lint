#Requires -Version 7.3
<#
  run_feature_registry_families.ps1 -- the two family importers produce one
  child per live rule / chart question, agree with their independent second
  sources, and FAIL (throw) on every drift the spec names:
    chart ids in the menu catalog and not the bundler's ValidateSet, or vice versa;
    an override naming a child that no longer exists;
    an emitter script that does not exist, or one on disk no child names.
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
function Expect-Throw([string]$Name, [scriptblock]$Block, [string]$Needle) {
  $msg = ''
  try { & $Block | Out-Null } catch { $msg = $_.Exception.Message }
  Check $Name (($msg -ne '') -and ($msg -like "*$Needle*")) $(if ($msg) { ($msg -split "`n")[0] } else { 'did not throw' })
}
Write-Host '== feature registry: family importers ==' -ForegroundColor Cyan
Import-Module (Join-Path $Repo 'tools\FeatureRegistry.psm1') -Force
$p = Get-RegistryPaths -Repo $Repo
$lrFile = Join-Path $p.Families 'lint-rules.json'
$cqFile = Join-Path $p.Families 'chart-questions.json'
Check 'lint-rules.json present' (Test-Path -LiteralPath $lrFile)
Check 'chart-questions.json present' (Test-Path -LiteralPath $cqFile)
if (-not (Test-Path -LiteralPath $cqFile)) { Write-Host 'FEATURE REGISTRY FAMILIES: FAIL' -ForegroundColor Red; exit 1 }
Check 'family files are ASCII+CRLF' (((Test-AsciiCrlfFile -Path $lrFile) -eq '') -and ((Test-AsciiCrlfFile -Path $cqFile) -eq ''))

$live = Get-LiveSurface -Paths $p
$lr = Read-FamilyDefinition -Path $lrFile
$cq = Read-FamilyDefinition -Path $cqFile
$parentLint = [ordered]@{ id = 'lint-rules'; title = 'Lint rules'; group = 'linting'; owner = 'ENGINE'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Every lint rule the engine ships, from rules --json'; wikiPage = 'rules'; surfaces = @([ordered]@{ type = 'cli'; verb = 'rules' }); audience = 'both'; family = 'lint-rules' }
$parentChart = [ordered]@{ id = 'chart-questions'; title = 'Chart questions'; group = 'diagrams-charts'; owner = 'CHARTS'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Every chart question of the Reports submenu and Ask-Report.ps1'; wikiPage = 'Diagrams-and-Charts'; surfaces = @([ordered]@{ type = 'script'; path = 'charts\src\Ask-Report.ps1' }); audience = 'both'; family = 'chart-questions' }

$rules = @(Import-LintRuleFamily -Live $live -Family $lr -Parent $parentLint)
Check 'lint children == summary.total' ($rules.Count -eq [int]$live.RuleCatalog.summary.total) "children=$($rules.Count) total=$($live.RuleCatalog.summary.total)"
# Sort-OrdinalUnique is module-internal, so the expected order is built here.
$sortedIds = [string[]]@($rules | ForEach-Object { $_.id }); [Array]::Sort($sortedIds, [System.StringComparer]::Ordinal)
Check 'lint child ids are rule.<id>, sorted' (($rules[0].id -like 'rule.*') -and (($rules | ForEach-Object { $_.id }) -join ',') -eq ($sortedIds -join ','))
$be = $rules | Where-Object { $_.id -eq 'rule.bare-except' }
Check 'a rule child carries wikiPage rules + anchor + cli lint --rule' (($be.wikiPage -eq 'rules') -and ($be.wikiAnchor -eq 'bare-except') -and ($be.surfaces[0].example -like '*--rule bare-except*'))
Check 'a rule child summary names category and severity' ($be.summary -like '*bug-patterns*' -and $be.summary -like '*info*')

$charts = @(Import-ChartQuestionFamily -Live $live -Family $cq -Parent $parentChart -Paths $p)
Check 'chart children == REPORT_QUESTION_COUNT' ($charts.Count -eq $live.ReportQuestionCount) "children=$($charts.Count) const=$($live.ReportQuestionCount)"
Check 'chart children are in catalog order' ((($charts | ForEach-Object { $_.id }) -join ',') -eq (($live.ReportQuestions | ForEach-Object { 'chart.' + $_.Id }) -join ','))
$rtp = $charts | Where-Object { $_.id -eq 'chart.round-trip' }
Check 'round-trip wikiPage override applied' ($rtp.wikiPage -eq 'Field-Round-Trip-Report')
$ww = $charts | Where-Object { $_.id -eq 'chart.who-writes' }
Check 'who-writes emitter is Emit-MemberAccess (shared, never derived from the id)' ($ww.emitter -eq 'charts\src\Emit-MemberAccess.ps1')
Check 'a chart child has menu + two script surfaces, owner CHARTS, title without ...' (($ww.surfaces.Count -eq 3) -and ($ww.surfaces[0].type -eq 'ide-menu') -and ($ww.surfaces[0].path -eq 'drag-lint > Reports > Who writes this field...') -and ($ww.owner -eq 'CHARTS') -and ($ww.title -eq 'Who writes this field'))
Check 'family default requires applied' (($ww.requires -join ',') -eq 'index,powershell7,graphviz')
Check 'per-child requires override applied (round-trip adds sql-index)' ($rtp.requires -contains 'sql-index')
Check 'chart children carry tests = Test-Emitters.ps1' ($ww.tests -contains 'charts\src\Test-Emitters.ps1')
Check 'subgroup comes from ReportGroupCaption' ($ww.subgroup -eq $live.GroupCaptions['rtkMember'])
$emitterSet = @($charts | ForEach-Object { Split-Path -Leaf $_.emitter } | Sort-Object -Unique)
Check 'emitter SET == Emit-*.ps1 on disk minus Emit-Common (two-way)' (($emitterSet -join ',') -eq ($live.EmitterFiles -join ',')) "named=$($emitterSet.Count) disk=$($live.EmitterFiles.Count)"

# --- every child validates as a child entry ----------------------------------
$ctx = Get-RegistryContext -Paths $p -ExtraIds @(($rules + $charts) | ForEach-Object { $_.id })
$bad = @()
foreach ($c in ($rules + $charts)) { $bad += @(Test-FeatureEntry -Entry $c -Context $ctx -Stem $c.id -Child) }
Check 'every child passes Test-FeatureEntry -Child' ($bad.Count -eq 0) (($bad | Select-Object -First 3) -join ' | ')

# --- drift controls: the importer must THROW ---------------------------------
$liveExtra = $live.PSObject.Copy(); $liveExtra.ChartValidateSet = @($live.ChartValidateSet) + @('zz-planted-question')
Expect-Throw 'a ValidateSet id with no menu item throws, naming it' { Import-ChartQuestionFamily -Live $liveExtra -Family $cq -Parent $parentChart -Paths $p } 'zz-planted-question'
$liveLess = $live.PSObject.Copy(); $liveLess.ChartValidateSet = @($live.ChartValidateSet | Where-Object { $_ -ne 'who-calls' })
Expect-Throw 'a menu item the bundler no longer accepts throws, naming it' { Import-ChartQuestionFamily -Live $liveLess -Family $cq -Parent $parentChart -Paths $p } 'who-calls'
$cqBad = ConvertTo-OrderedObject ($cq | ConvertTo-Json -Depth 10 | ConvertFrom-Json); $cqBad.children['zz-nope'] = [ordered]@{ emitter = 'charts\src\Emit-Deps.ps1' }
Expect-Throw 'an override naming a missing child throws' { Import-ChartQuestionFamily -Live $live -Family $cqBad -Parent $parentChart -Paths $p } 'zz-nope'
$cqBad2 = ConvertTo-OrderedObject ($cq | ConvertTo-Json -Depth 10 | ConvertFrom-Json); $cqBad2.children['deps'].emitter = 'charts\src\Emit-Nope.ps1'
Expect-Throw 'a missing emitter throws' { Import-ChartQuestionFamily -Live $live -Family $cqBad2 -Parent $parentChart -Paths $p } 'Emit-Nope.ps1'
$liveZero = $live.PSObject.Copy(); $liveZero.ReportQuestions = New-Object 'System.Collections.Generic.List[object]'
Expect-Throw 'a zero harvest throws before any comparison' { Import-ChartQuestionFamily -Live $liveZero -Family $cq -Parent $parentChart -Paths $p } '0 question'
# Spec 7: the per-child emitter is OPTIONAL (checked for existence when given).
# who-reads shares Emit-MemberAccess.ps1 with who-writes, so dropping its
# override leaves the emitter SET intact and the import must succeed.
$cqNoEm = ConvertTo-OrderedObject ($cq | ConvertTo-Json -Depth 10 | ConvertFrom-Json); $cqNoEm.children['who-reads'].Remove('emitter')
$noEm = @(); $noEmErr = ''
try { $noEm = @(Import-ChartQuestionFamily -Live $live -Family $cqNoEm -Parent $parentChart -Paths $p) } catch { $noEmErr = $_.Exception.Message }
$wr = @($noEm | Where-Object { $_.id -eq 'chart.who-reads' })
Check 'a child without an emitter override imports (spec 7: optional), no emitter key' (($noEmErr -eq '') -and ($wr.Count -eq 1) -and -not $wr[0].Contains('emitter')) $noEmErr
# ...but dropping the ONLY child naming an emitter is set drift, named.
$cqNoEm2 = ConvertTo-OrderedObject ($cq | ConvertTo-Json -Depth 10 | ConvertFrom-Json); $cqNoEm2.children['deps'].Remove('emitter')
Expect-Throw 'an emitter on disk that no child names throws, naming it' { Import-ChartQuestionFamily -Live $live -Family $cqNoEm2 -Parent $parentChart -Paths $p } 'Emit-Deps.ps1'
# Spec 7: a per-child 'since' override is exempt from the CHANGELOG-heading check
# (most questions predate any mention); the family's own since is not.
$oldSince = ConvertTo-OrderedObject $ww; $oldSince['since'] = '0.1.0'
Check 'a child since that is no CHANGELOG heading is a problem by default' (@(Test-FeatureEntry -Entry $oldSince -Context $ctx -Stem $oldSince.id -Child | Where-Object { $_ -like '*CHANGELOG*' }).Count -eq 1)
Check '...and exempt with -SinceOverride (a per-child override)' (@(Test-FeatureEntry -Entry $oldSince -Context $ctx -Stem $oldSince.id -Child -SinceOverride).Count -eq 0)
$dotted = ConvertTo-OrderedObject $parentLint; $dotted['id'] = 'rule.bare-except'
Check 'a hand entry id with a dot is still rejected (child ids are importer-owned)' (@(Test-FeatureEntry -Entry $dotted -Context $ctx -Stem 'rule.bare-except' | Where-Object { $_ -like '*importers own rule.<id> and chart.<id>*' }).Count -ge 1)

$lrBad = ConvertTo-OrderedObject ($lr | ConvertTo-Json -Depth 10 | ConvertFrom-Json); $lrBad.children['zz-no-such-rule'] = [ordered]@{ aliases = @('x') }
Expect-Throw 'a lint override naming a missing rule throws' { Import-LintRuleFamily -Live $live -Family $lrBad -Parent $parentLint } 'zz-no-such-rule'

# --- Get-RegistryChildren wiring ---------------------------------------------
$kids = Get-RegistryChildren -Live $live -Entries @($parentLint, $parentChart) -Paths $p
Check 'Get-RegistryChildren returns both families' (($kids.Keys -join ',') -eq 'lint-rules,chart-questions')
Expect-Throw 'a family entry without a definition file throws' { Get-RegistryChildren -Live $live -Entries @([ordered]@{ id = 'zz'; family = 'mcp-tools' }) -Paths $p } 'mcp-tools'
Expect-Throw 'a definition whose entry is not registered throws' { Get-RegistryChildren -Live $live -Entries @($parentLint) -Paths $p } 'chart-questions'

Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY FAMILIES: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY FAMILIES: PASS' -ForegroundColor Green
exit 0
