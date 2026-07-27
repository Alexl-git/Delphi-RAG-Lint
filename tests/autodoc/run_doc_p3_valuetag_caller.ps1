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

  === Task 3c (2026-07-27) made the SAME destruction happen on the FIRST
  === apply rather than the second, and this runner was converted to a
  === pinned-known-defect test that asserted the loss explicitly.
  === Task 3f (2026-07-27) FIXED it. The pin below is flipped: it now
  === asserts the FIX, and the known-defect banner is gone.

  Task 3c widened TParsedDoc.HasContent to also recognize HasExampleTag (see
  docs\lint\URGENT-TODO-2026-07-26-index-doc-tag-coverage.md and
  .superpowers\sdd\2026-07-24-autodocument-phase3-harvest-and-facts\
  task-3c-report.md). HasValueAndExample's <example> tag makes
  Existing.HasContent -- and therefore ExistingHasAnyTag -- True from the
  ORIGINAL parse alone, before any additive-insert-then-merge dance, so the
  FIRST apply takes the repair branch directly. That is still true and is
  still pinned below; what changed in Task 3f is that the repair branch no
  longer destroys what it cannot model.

  Task 3f (loss class L1) added verbatim residual-line carry-through to
  TDocRegions.MergeComment: SplitResidualLines partitions the existing region
  into the lines the engine can fully account for and the ones it cannot, the
  accounted ones drive the emitter as before, and the rest are re-emitted
  verbatim -- original indentation intact -- after every modeled tag and
  before the facts <remarks> block. <value> has no TParsedDoc field, nothing
  else on its line is modeled either, so its whole line is carried through
  untouched.

  Drives `index` -> `document --qname --apply` and asserts:
    1. action = extended, edits = 2 (the repair branch runs on the FIRST
       apply -- pinned so a branch flip in either direction is visible, same
       rule as the idempotency sweep's own pins. This is now the CORRECT
       branch: repair no longer implies destruction).
    2. <value> SURVIVES verbatim, on its own line, exactly once -- the Task 3f
       fix. Was pinned as "is GONE" between Task 3c and Task 3f.
    3. <example> SURVIVES (Task 3b/3c's repair-path support for <example>
       still works -- proves the carry-through did not take over emission of
       a tag the engine genuinely models).
    4. The facts block ("Called from:") is still present -- proves Merged
       was genuinely computed, not an early-exit no-op.
    5. A second apply cycle is a stable fixed point -- the carry-through is
       re-derived identically every run, so it converges rather than
       re-appending.

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

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $applyJson = (& $exePath document --qname valuetag_caller.HasValueAndExample --db $db --apply --json 2>$null) -join "`n"
  Check 'apply exits 0' ($LASTEXITCODE -eq 0)
  Check '1. action = extended (the repair branch runs on the FIRST apply -- pinned so a branch flip in EITHER direction is visible)' `
    ($applyJson -match '"action":"extended"') $applyJson
  Check '1. edits = 2 (delete+insert pair -- was 1, a single additive insert, pre-Task-3c)' `
    ($applyJson -match '"edits":2') $applyJson

  $text = [IO.File]::ReadAllText($target)
  # v(ADP3 T3f): FLIPPED. Between Task 3c and Task 3f this asserted that the
  # <value> tag was GONE, behind a known-defect banner. Task 3f's verbatim
  # residual-line carry-through preserves it, so the pin now asserts the fix.
  Check '2. hand-written <value> survives VERBATIM on its own line (v(ADP3 T3f) residual carry-through; was pinned as "is GONE" between Task 3c and Task 3f)' `
    ($text.Contains("`n/// <value>Hand-written; must survive.</value>"))
  Check '2. ...and EXACTLY once (carried through, never duplicated -- the failure mode a naive verbatim re-emit has)' `
    (([regex]::Matches($text, [regex]::Escape('<value>Hand-written; must survive.</value>'))).Count -eq 1)
  Check '3. hand-written <example> still survives verbatim (Task 3b/3c repair-path support for <example> unaffected)' `
    ($text.Contains('/// <example>Example text.</example>'))
  Check '4. a NEW facts block with Called from: is present (Merged was genuinely computed, not an early-exit no-op)' `
    ($text -match '<!-- drag-lint:auto BEGIN -->' -and $text -match 'Called from:.*valuetag_caller\.CallsHasValueAndExample')

  # 5. Stability: the carry-through is re-derived from the region on every run,
  # so cycle 2 reproduces cycle 1's output exactly instead of re-appending.
  $afterApply1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $applyJson2 = (& $exePath document --qname valuetag_caller.HasValueAndExample --db $db --apply --json 2>$null) -join "`n"
  $afterApply2 = [IO.File]::ReadAllBytes($target)
  Check '5. second apply cycle: action = unchanged (a stable fixed point)' `
    ($applyJson2 -match '"action":"unchanged"') $applyJson2
  Check '5. second apply cycle: file byte-identical (the carried-through line is not re-appended)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterApply1,[byte[]]$afterApply2))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
