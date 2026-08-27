<#
  run_wiki_blocks.ps1 -- `dl:wiki` concept blocks: the parse, the lookup, the
  drift gate, and the promise that the autodoc rewriter never touches them.

  WHY THIS EXISTS
  ---------------
  The whole feature rests on one inference that was NOT proven when it was
  designed: that a `///` block written above `unit X;` attaches to the unit
  symbol and lands in symbol_docs.raw_block. It was inferred from 3,570
  unit-attached rows in an existing library index -- which is evidence that it
  happened once with some binary, not that it happens now with this one.
  Check 1 pins it, permanently, against whatever engine is being built.

  It matters more than it looks. If unit attachment silently stopped working,
  every unit-level topic in every project would vanish and `wiki --term` would
  answer "no topic matches" -- which is a legitimate answer, indistinguishable
  from the failure. Nothing else in the battery would go red.

  THE PAIRS THAT CARRY IT
  -----------------------
  Every assertion here has a partner that makes it non-vacuous:

    * check 2 finds a topic BY ALIAS; check 3 proves the SAME alias through
      `query --name` still finds nothing. Without check 3, check 2 would pass
      just as well if `wiki` had been built by widening the ordinary symbol
      search -- silently changing what every existing caller gets back.
    * check 4 runs `wiki --check` on a GOOD fixture and requires exit 0 AND a
      non-zero topic count. A gate that examined nothing prints "0 problems"
      and exits 0 too.
    * check 5 runs it on a fixture built to BE wrong and requires exit 1 with
      both planted defects named. Without it, check 4 is satisfied by a --check
      that is incapable of failing.

  THE AUTODOC CHECK IS RUN TWICE ON PURPOSE
  ------------------------------------------
  Check 6 applies `document --unit --apply` two times and compares the dl:wiki
  lines after each. Once is not enough: this repo's own parser comments record
  a deletion bug that only appeared on the SECOND apply, after
  MergeAdjacentSameKind had folded a freshly written facts block into the
  region. A one-pass assertion would have passed straight over it.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_wiki_blocks.ps1
#>
[CmdletBinding()]
param(
  [string] $Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string] $WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-wiki-" + [Guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== dl:wiki concept blocks ==' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path

$goodSrc = (Resolve-Path "$PSScriptRoot\fixtures\wikiblocks").Path
$badSrc  = (Resolve-Path "$PSScriptRoot\fixtures\wikiblocks-bad").Path

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$goodDir = Join-Path $WorkDir 'good'
$badDir  = Join-Path $WorkDir 'bad'
New-Item -ItemType Directory -Force -Path $goodDir, $badDir | Out-Null
# The autodoc pass in check 6 REWRITES its input, so the repo fixture is copied
# rather than indexed in place. A guard that mutates a tracked file leaves the
# working tree dirty and the next run testing something else.
Copy-Item (Join-Path $goodSrc '*.pas') $goodDir
Copy-Item (Join-Path $badSrc  '*.pas') $badDir

$goodDb = Join-Path $WorkDir 'good.sqlite'
$badDb  = Join-Path $WorkDir 'bad.sqlite'
$errFile = Join-Path $WorkDir 'stderr.txt'

# The engine prints "(loaded defaults from ...)" on STDERR; captured separately
# so $ErrorActionPreference = 'Stop' cannot turn that banner into an
# ErrorRecord and corrupt a JSON slice.
function Run([string[]]$A) {
  $out = & $Exe @A 2>$errFile
  $rc  = $LASTEXITCODE
  $err = if (Test-Path -LiteralPath $errFile) { (Get-Content -LiteralPath $errFile -Raw) } else { '' }
  if ($null -eq $err) { $err = '' }
  [pscustomobject]@{ Out = ($out -join "`n"); Err = $err; Code = $rc }
}

$r = Run @('index', $goodDir, '--db', $goodDb)
if ($r.Code -ne 0) { Write-Host "FATAL: indexing the good fixture failed`n$($r.Out)`n$($r.Err)" -ForegroundColor Red; exit 1 }
$r = Run @('index', $badDir, '--db', $badDb)
if ($r.Code -ne 0) { Write-Host "FATAL: indexing the bad fixture failed`n$($r.Out)`n$($r.Err)" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# CHECK 1 -- BOTH PLACEMENTS PARSE. This is the inference the design rests on.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 1: a block above `unit X;` attaches, and so does one on a type' -ForegroundColor Cyan

$list = Run @('wiki', '--list', '--db', $goodDb, '--json')
$topics = $null
try { $topics = $list.Out | ConvertFrom-Json } catch { }
Check 'wiki --list exits 0' ($list.Code -eq 0) "exit $($list.Code) / $($list.Err.Trim())"
Check 'and emits valid JSON on stdout' ($null -ne $topics) $list.Out

$unitTopic = @($topics | Where-Object { $_.name -eq 'Zorbimatic Dispatch' })
$typeTopic = @($topics | Where-Object { $_.name -eq 'Zorb Payload' })
Check 'the UNIT-LEVEL block was found' ($unitTopic.Count -eq 1) "got $($unitTopic.Count)"
Check 'the TYPE-ATTACHED block was found' ($typeTopic.Count -eq 1) "got $($typeTopic.Count)"

if ($unitTopic.Count -ne 1 -or $typeTopic.Count -ne 1) {
  Write-Host 'FATAL: the fixture did not parse; every check below would be vacuous.' -ForegroundColor Red
  Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}

Check 'the unit block is owned by the UNIT symbol, not a type' `
  ($unitTopic[0].owner_kind -eq 'unit') "owner_kind=$($unitTopic[0].owner_kind)"
Check 'the type block is owned by the CLASS' `
  ($typeTopic[0].owner_kind -eq 'class') "owner_kind=$($typeTopic[0].owner_kind)"

# The line must be the dl:wiki HEADER's own line, not the comment's first line
# -- that is what a hover indicator would navigate to.
$goodFile = Join-Path $goodDir 'uWikiGood.pas'
$srcLines = Get-Content -LiteralPath $goodFile
$hdrLine  = 1 + [Array]::FindIndex([string[]]$srcLines, [Predicate[string]]{ param($l) $l -match 'dl:wiki Zorbimatic Dispatch' })
Check 'the reported line is the dl:wiki HEADER line' `
  ($unitTopic[0].line -eq $hdrLine) "reported $($unitTopic[0].line), header is at $hdrLine"

Check 'aliases survived the parse' `
  (@($unitTopic[0].aliases).Count -eq 3) "got $(@($unitTopic[0].aliases).Count)"
Check 'the body kept BOTH of its lines' `
  ($unitTopic[0].body -match 'A second body line') $unitTopic[0].body
Check 'the closing </remarks> did NOT leak into the body' `
  ($unitTopic[0].body -notmatch '</remarks>') $unitTopic[0].body

# ---------------------------------------------------------------------------
# CHECK 2/3 -- lookup by ALIAS, and the existing name search left alone
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 2/3: found by alias, and `query --name` unchanged' -ForegroundColor Cyan

$byAlias = Run @('wiki', '--term', 'that dispatch thing', '--db', $goodDb)
Check 'an ALIAS finds the topic' `
  (($byAlias.Code -eq 0) -and ($byAlias.Out -match 'Zorbimatic Dispatch')) "exit $($byAlias.Code)"

# Both directions: the user types more than the alias says.
$loose = Run @('wiki', '--term', 'the zorbimatic scheduler', '--db', $goodDb)
Check 'a phrase CONTAINING an alias also finds it (matching runs both ways)' `
  (($loose.Code -eq 0) -and ($loose.Out -match 'Zorbimatic Dispatch')) "exit $($loose.Code)"

$viaName = Run @('query', '--name', 'the zorbimatic', '--db', $goodDb)
Check 'the SAME alias through `query --name` still finds NOTHING' `
  ($viaName.Out -notmatch 'Zorbimatic Dispatch') `
  'if this fails, wiki was built by widening the symbol search and every existing caller changed'

$noMatch = Run @('wiki', '--term', 'a phrase nobody wrote down', '--db', $goodDb)
Check 'an unmatched term exits 1, so a caller can branch on it' ($noMatch.Code -eq 1) "exit $($noMatch.Code)"
Check 'and it SAYS how many topics it searched' ($noMatch.Out -match '\d+ topic\(s\) were searched') $noMatch.Out

# ---------------------------------------------------------------------------
# CHECK 4 -- the gate passes on good input, and says what it examined
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 4: --check on a clean fixture' -ForegroundColor Cyan

$okCheck = Run @('wiki', '--check', '--db', $goodDb)
Check 'a clean fixture exits 0' ($okCheck.Code -eq 0) "exit $($okCheck.Code) / $($okCheck.Out)"
$checked = if ($okCheck.Out -match '(\d+) topic\(s\) checked') { [int]$Matches[1] } else { -1 }
Check 'and it reports a NON-ZERO topic count' ($checked -ge 2) `
  "checked=$checked -- a gate that examined nothing also prints 0 problems"

# SeeCode written the way the code spells it (Class.Member, not Unit.Class.Member)
# must resolve, or the gate would report correct authoring as drift.
$term = Run @('wiki', '--term', 'zorb dispatch', '--db', $goodDb)
Check 'a class-qualified SeeCode entry resolves to a file:line' `
  ($term.Out -match 'TZorbPayload\.Deliver\s+->\s+\S+:\d+') $term.Out
Check 'and nothing in the clean fixture is MISSING' ($term.Out -notmatch 'MISSING') $term.Out

# ---------------------------------------------------------------------------
# CHECK 5 -- NEGATIVE CONTROL: the gate can actually fail
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 5: --check on a fixture built to be wrong' -ForegroundColor Cyan

$badCheck = Run @('wiki', '--check', '--db', $badDb)
Check 'a broken fixture exits 1' ($badCheck.Code -eq 1) "exit $($badCheck.Code)"
Check 'it NAMES the unresolvable SeeCode entry' `
  ($badCheck.Out -match 'TNoSuchSymbolAnywhere') $badCheck.Out
Check 'it also catches the alias colliding with another topic name' `
  ($badCheck.Out -match 'alias "Brollop Cycle" collides') $badCheck.Out
Check 'and the entry that DOES resolve is not reported' `
  ($badCheck.Out -notmatch 'SeeCode "TBrollopStage"') $badCheck.Out

$badJson = Run @('wiki', '--check', '--db', $badDb, '--json')
$bj = $null
try { $bj = $badJson.Out | ConvertFrom-Json } catch { }
Check 'the JSON form reports ok=false' (($null -ne $bj) -and ($bj.ok -eq $false)) $badJson.Out
Check 'and carries both problems' (($null -ne $bj) -and (@($bj.problems).Count -eq 2)) `
  "got $(if ($null -ne $bj) { @($bj.problems).Count } else { '<none>' })"

# ---------------------------------------------------------------------------
# CHECK 6 -- the autodoc rewriter must not touch a dl:wiki line. TWICE.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 6: document --unit --apply, run twice, preserves every dl:wiki line' -ForegroundColor Cyan

function Get-WikiLines([string]$Path) {
  @(Get-Content -LiteralPath $Path | Where-Object {
      $_ -match 'dl:wiki|Aliases:|SeeCode:|A unit-level block|A type-attached block'
    })
}

$before = Get-WikiLines $goodFile
Check 'the fixture has dl:wiki lines to preserve' ($before.Count -ge 6) "got $($before.Count)"

$wholeBefore = [IO.File]::ReadAllText($goodFile)

$d1 = Run @('document', '--unit', $goodFile, '--apply', '--no-backup', '--db', $goodDb)
Check 'first document --apply exits 0' ($d1.Code -eq 0) "exit $($d1.Code) / $($d1.Err.Trim())"
$after1 = Get-WikiLines $goodFile
Check 'pass 1: every dl:wiki line is byte-identical' `
  (($after1 -join "`n") -eq ($before -join "`n")) `
  ("before=$($before.Count) after=$($after1.Count)")

# POSITIVE CONTROL FOR THIS ENTIRE CHECK. "The rewriter preserved the wiki
# lines" is trivially true of a rewriter that wrote nothing at all, and a
# future change that makes `document` a no-op on this fixture would turn the
# assertion above green for the wrong reason. So: prove it actually wrote.
$wholeAfter = [IO.File]::ReadAllText($goodFile)
Check 'CONTROL: the rewriter really did modify the file' `
  ($wholeAfter -ne $wholeBefore) 'if this fails, the preservation checks are vacuous'
# And prove the write landed in the RISKY place -- the same <remarks> that
# carries a topic, not some unrelated declaration. That adjacency is what
# MergeAdjacentSameKind folds together, and folding is what the historical
# deletion bug needed.
Check 'CONTROL: an auto fence landed inside a wiki-carrying <remarks>' `
  ($wholeAfter -match '(?s)dl:wiki Zorb Payload.{0,600}drag-lint:auto BEGIN') `
  'the preservation check only means something if engine content sits beside the topic'

# Re-index: pass 2 must see the file as the rewriter left it, which is the
# state the historical deletion bug needed.
Run @('index', $goodDir, '--db', $goodDb) | Out-Null
$d2 = Run @('document', '--unit', $goodFile, '--apply', '--no-backup', '--db', $goodDb)
Check 'second document --apply exits 0' ($d2.Code -eq 0) "exit $($d2.Code) / $($d2.Err.Trim())"
$after2 = Get-WikiLines $goodFile
Check 'pass 2: still byte-identical (the pass a one-shot check would miss)' `
  (($after2 -join "`n") -eq ($before -join "`n")) `
  ("before=$($before.Count) after=$($after2.Count)")

# CRLF must survive too -- a rewriter that normalised line endings would break
# every one of these files against run_encoding_guard.ps1.
$bytes = [IO.File]::ReadAllBytes($goodFile)
$lf = 0; $crlf = 0
for ($i = 0; $i -lt $bytes.Length; $i++) {
  if ($bytes[$i] -eq 10) { $lf++; if ($i -gt 0 -and $bytes[$i-1] -eq 13) { $crlf++ } }
}
Check 'the rewritten file is still CRLF throughout' (($lf -gt 0) -and ($lf -eq $crlf)) "lf=$lf crlf=$crlf"
Check 'and still 7-bit ASCII' (-not ($bytes | Where-Object { $_ -gt 127 })) ''

# And the topics still parse out of the rewritten file.
Run @('index', $goodDir, '--db', $goodDb) | Out-Null
$post = Run @('wiki', '--check', '--db', $goodDb)
Check 'after two rewrites --check still passes' ($post.Code -eq 0) "exit $($post.Code) / $($post.Out)"
$postChecked = if ($post.Out -match '(\d+) topic\(s\) checked') { [int]$Matches[1] } else { -1 }
Check 'and still sees the same number of topics' ($postChecked -eq $checked) "was $checked, now $postChecked"

# The engine's own facts now sit inside the same <remarks> as a topic. They
# must not become part of the concept body -- a "Used by:" line is generated
# provenance, not something a human wrote about the concept.
$postList = Run @('wiki', '--list', '--db', $goodDb, '--json')
$pt = $null
try { $pt = $postList.Out | ConvertFrom-Json } catch { }
$payload = @($pt | Where-Object { $_.name -eq 'Zorb Payload' })
Check 'the topic survived two rewrites' ($payload.Count -eq 1) "got $($payload.Count)"
if ($payload.Count -eq 1) {
  Check 'and the generated facts did NOT leak into its body' `
    (($payload[0].body -notmatch 'Used by:') -and ($payload[0].body -notmatch 'drag-lint:auto')) `
    $payload[0].body
}

# ---------------------------------------------------------------------------
# CHECK 7 -- usage errors
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 7: mode selection' -ForegroundColor Cyan

$noMode = Run @('wiki', '--db', $goodDb)
Check 'no mode is a usage error (exit 2)' ($noMode.Code -eq 2) "exit $($noMode.Code)"
$twoModes = Run @('wiki', '--list', '--check', '--db', $goodDb)
Check 'two modes at once is a usage error (exit 2)' ($twoModes.Code -eq 2) "exit $($twoModes.Code)"

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Failed) { Write-Host 'WIKI BLOCKS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'WIKI BLOCKS GUARD: PASS' -ForegroundColor Green
exit 0
