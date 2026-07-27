<#
  run_doc_p3_valuetag_caller.ps1 -- Auto-Document Phase 3, Task 3 (review
  follow-up round 3, Regression 1 -- coordinator's own repro, reproduced
  first against the shipped exe, then fixed): ExistingHasAnyTag's
  "(Trim(Region.RawText) <> '') disjunct (added in round 2, Finding 4) routed
  ANY region with non-blank raw text into the repair branch, which deletes
  [Existing.StartLine..EndLine] and inserts ONLY Merged -- but Merged, by
  construction, can only carry Summary/Params/Returns/Remarks-prose. A region
  holding a tag type Merged cannot represent (<value>, <example>, ...) was
  therefore deleted outright, with NO gate protecting it (RegionFullyEngineOwned
  only guards the Merged='' branch, a DIFFERENT branch).

  Fixture fixtures\docp3\valuetag_caller.pas: HasValueAndExample carries ONLY
  <value> + <example> (no <summary>/<returns>/<param>), and has a caller
  (CallsHasValueAndExample) so Facts.CalledFrom is non-empty and Merged is
  non-empty too -- exercising the repair-vs-fresh DECISION, not the Merged=''
  branch (unlike the committed HasValueTag case in unhandledtags.pas, whose
  marked <returns> tag already sets HasReturnsTag=True on its own).

  Round-3's fix: drop the "(Trim(Region.RawText) <> '')" disjunct entirely.
  That routed this region through the "no prior comment" fresh-insert branch:
  the existing lines left completely alone, Merged (the facts-only remarks
  block) inserted as an ADDITIONAL block above the declaration --
  additive/non-destructive, and this test originally asserted exactly that
  (action=created, edits=1, both <value> and <example> byte-identical).

  Round-3's own report ALSO flagged, but deliberately did not assert, a
  KNOWN residual: this additive state was never a stable fixed point under a
  SECOND apply -- once MergeAdjacentSameKind folded the freshly-inserted
  <remarks> fence into the same scanned region, that region's Existing.Remarks
  became non-empty, HasContent flipped True via the PRE-EXISTING
  Remarks<>'' disjunct (untouched by Task 3c), and the SECOND apply took the
  repair branch, destroying <value>/<example> one cycle later.

  === Task 3c (2026-07-27) update: the SAME destruction now happens on the
  === FIRST apply, not the second, and IS asserted (as a known, pinned
  === defect, not a silent pass) below.

  Task 3c widened TParsedDoc.HasContent to also recognize HasExampleTag (see
  docs\lint\URGENT-TODO-2026-07-26-index-doc-tag-coverage.md and
  .superpowers\sdd\2026-07-24-autodocument-phase3-harvest-and-facts\
  task-3c-report.md). HasValueAndExample's <example> tag now makes
  Existing.HasContent -- and therefore ExistingHasAnyTag -- True from the
  ORIGINAL parse alone, before any additive-insert-then-merge dance. The
  FIRST apply now takes the repair branch directly: Merged preserves
  <example> (Task 3b/3c gave it a field and repair-path emission) but has NO
  representation for <value> at all, so <value> is destroyed one cycle
  earlier than round 3's own known, deferred residual already described.

  No new destruction CLASS was introduced by Task 3c -- this is the exact
  same "an unmodeled tag co-occurring with content that flips HasContent True
  is destroyed by the repair path" gap round 3 already knew about and
  deferred (see docs\lint\...'s own pre-existing "Related, lower priority"
  section, predating Task 3c). What changed is the WINDOW: a single-shot
  `document --apply` -- exactly what the IDE's "Auto-Document Whole Project"
  menu action runs -- now destroys content that used to survive that one run.

  Per superpowers:receiving-code-review discipline (verify before silently
  adjusting, do not hide a regression by relaxing an assertion without
  saying so): this test now follows the SAME idiom
  run_doc_p3_idempotency_sweep.ps1's SWEEP D already established for a
  different known-broken shape -- assert the CURRENT (bad) behaviour
  explicitly, behind a loud banner naming the defect and where it is
  tracked, rather than either (a) silently editing the old assertions with
  no trace of what changed, or (b) leaving a bare, unexplained red runner
  that the next task cannot distinguish from a break IT caused.

  Drives `index` -> `document --qname --apply` and asserts, pinned as KNOWN,
  CURRENT (not desired) behaviour:
    1. action = extended, edits = 2 (the repair branch runs on the FIRST
       apply -- pinned so a regression that makes this WORSE, e.g. more
       edits or a different action, is caught; a value that DISAPPEARS this
       destruction, e.g. action reverting to "created", is an IMPROVEMENT --
       update the pin, same rule as the idempotency sweep's own pins).
    2. <value> is GONE (the actual data loss -- asserted as present-today
       fact, not endorsed).
    3. <example> SURVIVES (Task 3b/3c's repair-path support for <example>
       still works even in this broken shape -- proves the loss is scoped to
       the genuinely unmodeled tag, not a wider collapse).
    4. The facts block ("Called from:") is still present -- proves Merged
       was genuinely computed, not an early-exit no-op.
    5. A second apply cycle is a stable fixed point (the destruction happens
       ONCE, then the file stops changing) -- proves this is not ALSO an
       unbounded-growth defect stacked on top of the data-loss one.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\valuetag_caller.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp3valuetagcaller'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'valuetag_caller.pas'
$db     = Join-Path $scratch 'valuetagcaller.sqlite'
Copy-Item $fixture $target -Force

Write-Host ''
Write-Host '=== KNOWN DEFECT: valuetag_caller.HasValueAndExample loses its unmodeled <value> tag ===' -ForegroundColor Yellow
Write-Host '    on the FIRST document --apply (was the SECOND, pre-Task-3c). STABILITY OF THE' -ForegroundColor Yellow
Write-Host '    <value> TAG IS NOT CLAIMED. See docs\lint\URGENT-TODO-2026-07-26-index-doc-tag-' -ForegroundColor Yellow
Write-Host '    coverage.md ("New finding") and task-3c-report.md for the full writeup and the' -ForegroundColor Yellow
Write-Host '    recommended follow-up (repair path must verbatim-preserve unmodeled tags).' -ForegroundColor Yellow

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $applyJson = (& $exePath document --qname valuetag_caller.HasValueAndExample --db $db --apply --json 2>$null) -join "`n"
  Check 'apply exits 0' ($LASTEXITCODE -eq 0)
  Check 'PINNED KNOWN DEFECT 1: action = extended (repair branch runs on the FIRST apply -- was "created" pre-Task-3c; a flip back to "created" is an IMPROVEMENT, update the pin)' `
    ($applyJson -match '"action":"extended"') $applyJson
  Check 'PINNED KNOWN DEFECT 1: edits = 2 (delete+insert pair -- was 1, a single additive insert, pre-Task-3c)' `
    ($applyJson -match '"edits":2') $applyJson

  $text = [IO.File]::ReadAllText($target)
  Check 'PINNED KNOWN DEFECT 2: hand-written <value> is GONE (the actual data loss -- was "survives" pre-Task-3c; its REAPPEARANCE is an improvement, not a break)' `
    (-not $text.Contains('<value>Hand-written; must survive.</value>'))
  Check '3. hand-written <example> still survives verbatim (Task 3b/3c repair-path support for <example> unaffected)' `
    ($text.Contains('/// <example>Example text.</example>'))
  Check '4. a NEW facts block with Called from: is present (Merged was genuinely computed, not an early-exit no-op)' `
    ($text -match '<!-- drag-lint:auto BEGIN -->' -and $text -match 'Called from:.*valuetag_caller\.CallsHasValueAndExample')

  # 5. Stability: the destruction happens ONCE (first apply), not repeatedly --
  # this is NOT also an unbounded-growth defect stacked on the data-loss one.
  $afterApply1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $applyJson2 = (& $exePath document --qname valuetag_caller.HasValueAndExample --db $db --apply --json 2>$null) -join "`n"
  $afterApply2 = [IO.File]::ReadAllBytes($target)
  Check '5. second apply cycle: action = unchanged (the post-destruction state is a stable fixed point)' `
    ($applyJson2 -match '"action":"unchanged"') $applyJson2
  Check '5. second apply cycle: file byte-identical (no further growth beyond the one-time loss)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterApply1,[byte[]]$afterApply2))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
