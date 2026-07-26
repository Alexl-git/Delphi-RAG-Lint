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
  <value> + <example> (no <summary>/<returns>/<param>, so NONE of
  ExistingHasAnyTag's narrow disjuncts -- HasSummaryTag/HasReturnsTag/Params/
  HasContent -- fire on their own), and has a caller
  (CallsHasValueAndExample) so Facts.CalledFrom is non-empty and Merged is
  non-empty too -- exercising the repair-vs-fresh DECISION, not the Merged=''
  branch (unlike the committed HasValueTag case in unhandledtags.pas, whose
  marked <returns> tag already sets HasReturnsTag=True on its own,
  independent of this disjunct).

  The fix: drop the disjunct entirely. No committed test required it. This
  routes such a region through the "no prior comment" fresh-insert branch
  instead: the existing lines are left completely alone, and Merged (the
  facts-only remarks block) is inserted as an ADDITIONAL block immediately
  above the declaration -- additive/non-destructive, the correct INTERIM
  behaviour until a future task (Task 3b, tag round-tripping) lets Merged
  represent these tags directly.

  Drives `index` -> `document --qname --apply` and asserts:
    1. action = created (the fresh-insert branch, NOT "extended" -- which
       would mean the destructive delete+insert repair branch ran instead).
    2. edits = 1 (a single insert; NOT 2, which would be a delete+insert pair).
    3. Both hand-written tags (<value>, <example>) survive byte-identical.
    4. A NEW facts block ("Called from:") is also present -- proves the fix
       is genuinely additive (Merged was computed and inserted), not simply
       a no-op that skipped the edit entirely.
    5. The original tags appear BEFORE the new facts block (insert landed
       at the declaration, after the existing lines, not interleaved/above).

  KNOWN, NOT FIXED HERE (flagged, not asserted): this additive state is NOT a
  stable fixed point under a SECOND apply. A second index + apply merges the
  now-adjacent <value>/<example> lines and the freshly-inserted <remarks>
  block into ONE scanned region (TDocCommentScanner.MergeAdjacentSameKind);
  that combined region's Existing.Remarks is now non-empty (from the
  previously-inserted fence), so HasContent becomes True and the region
  routes through the REPAIR branch on the SECOND run -- which deletes the
  whole combined span and re-inserts a Merged that still has no
  representation for <value>/<example>, destroying them one cycle later than
  Regression 1 did. Empirically confirmed during this fix's development
  (second apply: "action":"extended","edits":2, <value>/<example> gone).
  This is the SAME underlying gap the coordinator's own fix rationale already
  named as deferred ("Task 3b will make Merged able to carry these tags, at
  which point the repair path handles them properly") -- not asserted as a
  passing or failing case in THIS test, since committing a red assertion is
  wrong, but recorded here so the gap stays visible rather than silently
  reintroduced or silently hidden.

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
  Check '1. action = created (fresh-insert branch, NOT the destructive repair branch)' `
    ($applyJson -match '"action":"created"') $applyJson
  Check '2. edits = 1 (single insert, not a delete+insert pair)' `
    ($applyJson -match '"edits":1') $applyJson

  $text = [IO.File]::ReadAllText($target)
  Check '3. hand-written <value> survives verbatim' `
    ($text.Contains('/// <value>Hand-written; must survive.</value>'))
  Check '3. hand-written <example> survives verbatim' `
    ($text.Contains('/// <example>Example text.</example>'))
  Check '4. a NEW facts block with Called from: is present' `
    ($text -match '<!-- drag-lint:auto BEGIN -->' -and $text -match 'Called from:.*valuetag_caller\.CallsHasValueAndExample')

  $valueIx  = $text.IndexOf('<value>Hand-written')
  $factsIx  = $text.IndexOf('drag-lint:auto BEGIN')
  Check '5. original tags appear BEFORE the new facts block' `
    (($valueIx -ge 0) -and ($factsIx -ge 0) -and ($valueIx -lt $factsIx))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
