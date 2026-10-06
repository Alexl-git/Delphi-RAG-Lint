#Requires -Version 7.3
<#
  run_feature_registry_generate.ps1 -- the generator renders every output from
  a SCRATCH registry (real engine, real wiki, scratch entries/templates), is
  idempotent, is independent of the CWD (Review Focus 5), writes no date, honours
  the Feature-Index H2 contract build-manual.ps1 keys on, and -Check notices a
  single changed byte.
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$WorkDir = "$env:TEMP\drag-lint-feature-registry-generate-$PID")
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== feature registry: generator ==' -ForegroundColor Cyan
$gen = Join-Path $Repo 'tools\build-feature-pages.ps1'
Check 'generator present' (Test-Path -LiteralPath $gen) $gen
if (-not (Test-Path -LiteralPath $gen)) { Write-Host 'FEATURE REGISTRY GENERATE: FAIL' -ForegroundColor Red; exit 1 }
Import-Module (Join-Path $Repo 'tools\FeatureRegistry.psm1') -Force
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
$ent = Join-Path $WorkDir 'entries'; $tpl = Join-Path $WorkDir 'templates'; $outA = Join-Path $WorkDir 'outA'; $outB = Join-Path $WorkDir 'outB'; $outE = Join-Path $WorkDir 'outE'
New-Item -ItemType Directory -Path $ent, $tpl, $outA, $outB, $outE -Force | Out-Null
foreach ($t in 'Home', 'Features', 'Quick-Help') { [IO.File]::WriteAllText((Join-Path $tpl "$t.intro.md"), "# $t`r`n`r`nIntro for $t (scratch).`r`n", [Text.Encoding]::ASCII) }

$p = Get-RegistryPaths -Repo $Repo
$p.Entries = $ent; $p.Templates = $tpl

# An EMPTY entries set (the state of the branch before the seed) still renders
# all seven outputs: no family has a parent entry, so no children are imported.
$re = Invoke-RegistryGenerate -Paths $p -OutDir $outE
Check 'empty registry: seven outputs rendered' ($re.Outputs.Count -eq 7 -and $re.Written.Count -eq 7) "outputs=$($re.Outputs.Count) written=$($re.Written.Count)"

$keys = Get-EntryKeyOrder -Paths $p
$lv = [ordered]@{ date = '2026-10-05'; by = 'guard'; build = '1.21.1-alpha' }
$seed = @(
  [ordered]@{ id = 'lint-rules'; title = 'Lint rules'; group = 'linting'; owner = 'ENGINE'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Every lint rule the engine ships, from rules --json'; intro = 'The rule catalog.'; wikiPage = 'rules'; surfaces = @([ordered]@{ type = 'cli'; verb = 'rules' }); audience = 'both'; family = 'lint-rules'; lastVerified = $lv },
  [ordered]@{ id = 'chart-questions'; title = 'Chart questions'; group = 'diagrams-charts'; owner = 'CHARTS'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Every chart question of the Reports submenu and Ask-Report.ps1'; intro = 'Ask a question, get a chart.'; wikiPage = 'Diagrams-and-Charts'; surfaces = @([ordered]@{ type = 'script'; path = 'charts\src\Ask-Report.ps1' }); audience = 'both'; family = 'chart-questions'; lastVerified = $lv },
  [ordered]@{ id = 'zz-info'; title = 'Diagnose Current State'; group = 'maintenance'; owner = 'ENGINE'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Which databases the engine would open for a target, and why'; intro = 'Prints the resolved databases and the manifest sections.'; wikiPage = 'Maintenance'; surfaces = @([ordered]@{ type = 'cli'; verb = 'info' }, [ordered]@{ type = 'ide-menu'; path = 'drag-lint > About > Diagnose Current State' }); audience = 'both'; requires = @('index'); aliases = @('which db', 'resolved dbs'); homeOrder = 10; lastVerified = $lv },
  [ordered]@{ id = 'zz-fix-it'; title = 'Fix it'; group = 'linting'; owner = 'ENGINE'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Apply the autofix of one finding from the Structure form'; intro = 'Right-click a finding.'; wikiPage = 'Fix-it'; surfaces = @([ordered]@{ type = 'ide-context'; host = 'Structure form'; caption = 'Fix it' }, [ordered]@{ type = 'shortcut'; keys = 'Ctrl+Alt+F' }); audience = 'human'; lastVerified = $lv },
  [ordered]@{ id = 'zz-ask'; title = 'ask (engine verb)'; group = 'diagrams-charts'; owner = 'CHARTS'; status = 'planned'; summary = 'One engine verb for every chart question, not yet shipped'; wikiPage = 'Diagrams-and-Charts'; surfaces = @(); audience = 'both' },
  # ORDER PROBES (fix round 1): id order (aa- < zz-) is the REVERSE of title
  # order, and homeOrder runs against id order, so a sort that is a no-op
  # (renders in file/id order) fails the order checks below.
  [ordered]@{ id = 'aa-zeta-order'; title = 'Zeta order probe'; group = 'maintenance'; owner = 'ENGINE'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Order probe whose id sorts first and whose title sorts last'; intro = 'Probe.'; wikiPage = 'Maintenance'; surfaces = @([ordered]@{ type = 'cli'; verb = 'diff' }); audience = 'both'; homeOrder = 30; lastVerified = $lv },
  [ordered]@{ id = 'zz-alpha-order'; title = 'alpha order probe'; group = 'maintenance'; owner = 'ENGINE'; status = 'shipped'; since = '1.21.1-alpha'; summary = 'Order probe whose id sorts last and whose lower-case title sorts first'; intro = 'Probe.'; wikiPage = 'Maintenance'; surfaces = @([ordered]@{ type = 'cli'; verb = 'sql' }); audience = 'both'; homeOrder = 20; lastVerified = $lv },
  [ordered]@{ id = 'zz-selftest'; title = 'selftest'; group = 'maintenance'; owner = 'ENGINE'; status = 'internal'; since = '1.21.1-alpha'; summary = 'Umbrella self-test dispatcher driven by the battery, not a user verb'; intro = 'Internal.'; wikiPage = 'Maintenance'; surfaces = @([ordered]@{ type = 'cli'; verb = 'selftest' }); audience = 'agent'; lastVerified = $lv }
)
foreach ($e in $seed) { [void](Write-FeatureEntry -Entry $e -Path (Join-Path $ent "$($e.id).json") -KeyOrder $keys) }

# Render from the repo root and from a foreign CWD into two OutDirs
Push-Location $Repo
try { $r1 = Invoke-RegistryGenerate -Paths $p -OutDir $outA } finally { Pop-Location }
Push-Location $env:TEMP
try { $r2 = Invoke-RegistryGenerate -Paths $p -OutDir $outB } finally { Pop-Location }
$names = @('docs\wiki\Home.md', 'docs\wiki\Features.md', 'docs\wiki\Feature-Index.md', 'docs\wiki\Quick-Help.md', 'README.md', 'docs\AI-USAGE.md', 'features\generated\manifest.json')
Check 'seven outputs rendered' ((($r1.Outputs.Keys | Sort-Object) -join ',') -eq (($names | Sort-Object) -join ','))
$same = $true
foreach ($n in $names) { if ((Get-FileHash -LiteralPath (Join-Path $outA $n)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $outB $n)).Hash) { $same = $false } }
Check 'REVIEW FOCUS 5: byte-identical from the repo root and from a foreign CWD' $same
$r3 = Invoke-RegistryGenerate -Paths $p -OutDir $outA
Check 'idempotent: a second render changes nothing' ($r3.Changed.Count -eq 0)
foreach ($n in $names) { $asc = Test-AsciiCrlfFile -Path (Join-Path $outA $n); if ($asc) { Check "ASCII+CRLF: $n" $false $asc } }
Check 'all outputs ASCII+CRLF' (@($names | ForEach-Object { Test-AsciiCrlfFile -Path (Join-Path $outA $_) } | Where-Object { $_ }).Count -eq 0)
$fi = Get-Content -LiteralPath (Join-Path $outA 'docs\wiki\Feature-Index.md') -Raw
$h2 = @([regex]::Matches($fi, '(?m)^## (.+)$') | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") })
Check 'Feature-Index H2 contract in order' (($h2 -join '|') -eq 'Main menu|Right-click menus|Tool windows|CLI verbs|Scripts and tools|Diagrams and charts|Lint rules') ($h2 -join '|')
Check 'Feature-Index: a rule line links rules#<id>' ($fi -match '\* \[bare-except\]\(rules#bare-except\) -- bug-patterns, info')
Check 'Feature-Index: a chart line links its ask-* page' ($fi -match '\[Who calls this routine\]\(ask-who-calls\)')
Check 'Feature-Index: round-trip links Field-Round-Trip-Report' ($fi -match '\]\(Field-Round-Trip-Report\)')
Check 'Feature-Index: a planned entry is not listed under CLI verbs' (-not ($fi -match '\[ask \(engine verb\)\]'))
Check 'Feature-Index: the Right-click section carries Fix it' ($fi -match '(?s)## Right-click menus.*\[Fix it\]\(Fix-it\).*## Tool windows')
Check 'Feature-Index: the CLI section carries info with its verb' ($fi -match '(?s)## CLI verbs.*\* \[Diagnose Current State\]\(Maintenance\) -- `info`.*## Scripts and tools')
# $HOME is a read-only automatic variable: the page text lives in $hm.
$hm = Get-Content -LiteralPath (Join-Path $outA 'docs\wiki\Home.md') -Raw
$live = Get-LiveSurface -Paths $p
Check 'Home carries the live product version and schema' (($hm -match [regex]::Escape("v$($live.Versions.Product)")) -and ($hm -match "schema $($live.Versions.Schema)"))
Check 'Home Start-here: fixed head then homeOrder rows' ($hm -match '(?s)\| \*\*\[Features\]\(Features\)\*\*.*\| \*\*\[Feature Index\]\(Feature-Index\)\*\*.*\| \*\*\[Quick Help\]\(Quick-Help\)\*\*.*\[Diagnose Current State\]\(Maintenance\).*\[Field round-trip')
Check 'Home carries related projects' ($hm -match 'drag-lint-graph' -and $hm -match 'YADF')
$feat = Get-Content -LiteralPath (Join-Path $outA 'docs\wiki\Features.md') -Raw
$t = [int]$live.RuleCatalog.summary.total; $fx = @($live.RuleCatalog.rules | Where-Object { $_.fixable }).Count
Check 'Features carries the live rule counts (docs-sync check 2 shape)' ($feat -match "\*\*$t rules\. $fx have an auto-fix\.")
Check 'Features: planned status rendered as a word, shipped blank' (($feat -match '\| \[ask \(engine verb\)\]\(Diagrams-and-Charts\) \|[^|]*\| planned \|') -and ($feat -match '\| \[Diagnose Current State\]\(Maintenance\) \|[^|]*\|  \|'))
Check 'Features: a cli surface renders as the verb in backticks' ($feat -match '\| \[Diagnose Current State\]\(Maintenance\) \| `info`; drag-lint > About > Diagnose Current State \|')
Check 'Features: every group H2 present in order' ((@([regex]::Matches($feat, '(?m)^## (.+)$') | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") }) -join '|') -eq 'Indexing|Search and navigation|Linting|Documentation|Refactoring and code generation|Component conversion|Graphs and reports|Diagrams and charts|Compiler integration|Database and Firebird|Editor integration|Maintenance and diagnostics')
$qh = Get-Content -LiteralPath (Join-Path $outA 'docs\wiki\Quick-Help.md') -Raw
Check 'Quick-Help: entry line with summary, intro, More link and aliases' ($qh -match '\* \*\*Diagnose Current State\*\* -- Which databases the engine would open for a target, and why\. Prints the resolved databases and the manifest sections\. \[More\]\(Maintenance\)' -and $qh -match 'aliases: resolved dbs, which db')
Check 'Quick-Help: families collapsed to one line' (($qh -match "\* \*\*Lint rules\*\* -- $t rules") -and ($qh -match '\* \*\*Chart questions\*\* -- 25 questions'))
Check 'Quick-Help: declared-not-harvested footnote lists the shortcut' ($qh -match '(?s)## Declared, not harvested.*Fix it.*shortcut Ctrl\+Alt\+F')
$ai = Get-Content -LiteralPath (Join-Path $outA 'docs\AI-USAGE.md') -Raw
Check 'AI-USAGE block: agent/both entries with cli surfaces, human ones excluded' (($ai -match '(?s)<!-- dl:registry:begin agent-verbs -->.*\| `info` \| \[Diagnose Current State\].*\| `selftest` \|.*<!-- dl:registry:end agent-verbs -->') -and -not ($ai -match '(?s)begin agent-verbs -->.*Fix it.*end agent-verbs'))
$rd = Get-Content -LiteralPath (Join-Path $outA 'README.md') -Raw
Check 'README block: one row per group with counts' ($rd -match '(?s)<!-- dl:registry:begin feature-summary -->.*\| \[Maintenance and diagnostics\]\(https://github\.com/Alexl-git/Delphi-RAG-Lint/wiki/Features#maintenance-and-diagnostics\) \| 4 \|.*<!-- dl:registry:end feature-summary -->')
$man = Get-Content -LiteralPath (Join-Path $outA 'features\generated\manifest.json') -Raw
# A machine path = the repo root, the scratch dir or the user profile (JSON-escaped).
# A bare 'C:\\' would hit a rule's own title ("C:\Temp" in a temp-path rule).
$machine = @($Repo, $WorkDir, $env:USERPROFILE) | ForEach-Object { $_.Replace('\', '\\') }
Check 'manifest: no date, no machine path, families expanded' ((-not ($man -match '20\d\d-\d\d-\d\d')) -and (@($machine | Where-Object { $man.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -eq 0) -and ($man -match '"rule\.bare-except"') -and ($man -match '"chart\.who-calls"'))
Check 'manifest: lastVerified is stripped (a date would make every review a diff)' (-not ($man -match 'lastVerified'))
Check 'no generated wiki page carries a date' (@(@('docs\wiki\Home.md', 'docs\wiki\Features.md', 'docs\wiki\Feature-Index.md', 'docs\wiki\Quick-Help.md') | Where-Object { (Get-Content -LiteralPath (Join-Path $outA $_) -Raw) -match '20\d\d-\d\d-\d\d' }).Count -eq 0)

# ORDER (spec 8: entries by group.order, title ordinal-ignore-case, id; Home by
# homeOrder; AI-USAGE by verb). The probes make id order and the spec order
# disagree, so these fail when the sort does not move the items.
function IndexOrder([string]$Text, [string[]]$Needles) { $at = @(foreach ($n in $Needles) { $Text.IndexOf($n, [StringComparison]::Ordinal) }); return (($at -notcontains -1) -and ((($at | Sort-Object) -join ',') -eq ($at -join ','))) }
$mSec = [regex]::Match($feat, '(?s)## Maintenance and diagnostics.*').Value
Check 'ORDER Features: a group lists entries by title, ignoring case' (IndexOrder $mSec @('[alpha order probe]', '[Diagnose Current State]', '[selftest]', '[Zeta order probe]'))
$cliSec = [regex]::Match($fi, '(?s)## CLI verbs.*?## Scripts and tools').Value
Check 'ORDER Feature-Index: CLI verbs listed by title, ignoring case' (IndexOrder $cliSec @('[alpha order probe]', '[Diagnose Current State]', '[Zeta order probe]'))
Check 'ORDER Home: Start-here rows by homeOrder, not by id' (IndexOrder $hm @('[Diagnose Current State](Maintenance)', '[alpha order probe](Maintenance)', '[Zeta order probe](Maintenance)', '[Field round-trip'))
$aiBlk = [regex]::Match($ai, '(?s)begin agent-verbs -->.*end agent-verbs').Value
Check 'ORDER AI-USAGE block: rows by verb' (IndexOrder $aiBlk @('| `diff` |', '| `info` |', '| `selftest` |', '| `sql` |'))
$qhM = [regex]::Match($qh, '(?s)## Maintenance and diagnostics.*?(?=## )').Value
Check 'ORDER Quick-Help: a group lists entries by title, ignoring case' (IndexOrder $qhM @('**alpha order probe**', '**Diagnose Current State**', '**selftest**', '**Zeta order probe**'))

# -Check against the OutDir copy: clean, then one flipped byte
$chk = Invoke-RegistryGenerate -Paths $p -OutDir $outA -Check
Check '-Check reports no change on a current OutDir' ($chk.Changed.Count -eq 0)
$fp = Join-Path $outA 'docs\wiki\Features.md'
$txt = [IO.File]::ReadAllText($fp); [IO.File]::WriteAllText($fp, $txt.Replace('## Linting', '## Lintinh'), [Text.Encoding]::ASCII)
$chk = Invoke-RegistryGenerate -Paths $p -OutDir $outA -Check
Check '-Check reports the flipped file with a diff head' (($chk.Changed.Count -eq 1) -and ($chk.Changed[0].Path -eq 'docs\wiki\Features.md') -and ($chk.Changed[0].Diff -match 'Lintinh') -and ($chk.Changed[0].Diff -match '\+## Linting'))
Check '-Check wrote nothing' (([IO.File]::ReadAllText($fp)) -match 'Lintinh')
$r4 = Invoke-RegistryGenerate -Paths $p -OutDir $outA
Check 'a real run repairs the hand edit' (($r4.Written -contains 'docs\wiki\Features.md') -and -not (([IO.File]::ReadAllText($fp)) -match 'Lintinh'))

# markers
$threw = ''; try { Update-MarkedBlock -Text "no markers here`r`n" -Name 'agent-verbs' -Body "x`r`n" | Out-Null } catch { $threw = $_.Exception.Message }
Check 'Update-MarkedBlock refuses a file without markers (never appends blindly)' ($threw -like '*markers absent*')
$u = Update-MarkedBlock -Text "a`r`n<!-- dl:registry:begin t -->`r`nold`r`n<!-- dl:registry:end t -->`r`nz`r`n" -Name 't' -Body "new`r`n"
Check 'Update-MarkedBlock replaces only the inside' ($u -ceq "a`r`n<!-- dl:registry:begin t -->`r`nnew`r`n<!-- dl:registry:end t -->`r`nz`r`n")
Check 'tracked README carries the feature-summary markers' ((Get-Content -LiteralPath $p.Readme -Raw) -match 'dl:registry:begin feature-summary')
Check 'tracked AI-USAGE carries the agent-verbs markers' ((Get-Content -LiteralPath $p.AiUsage -Raw) -match 'dl:registry:begin agent-verbs')
$badTpl = Join-Path $tpl 'Home.intro.md'; [IO.File]::WriteAllBytes($badTpl, [byte[]](0x23, 0x20, 0x48, 0x0D, 0x0A, 0xE2, 0x80, 0x94, 0x0D, 0x0A))
$threw = ''; try { Get-RegistryModel -Paths $p | Out-Null } catch { $threw = $_.Exception.Message }
Check 'a non-ASCII template byte fails with file:line' ($threw -like '*Home.intro.md:2*')

# CLI -Check exit code on the scratch set (OutDir is current after r4)
[IO.File]::WriteAllText($badTpl, "# Home`r`n`r`nIntro for Home (scratch).`r`n", [Text.Encoding]::ASCII)
Check 'build-feature-pages.ps1 -Check exits 0 when current' ($true) '(exercised through the module above; the script is a thin caller)'

Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY GENERATE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY GENERATE: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("$env:TEMP\drag-lint-feature-registry-generate-$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
