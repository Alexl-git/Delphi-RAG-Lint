<#
  run_doc_p3_markededit.ps1 -- Auto-Document Phase 3, Task 3 (review follow-up,
  Finding 1 -- REVISED after the coordinator's own reversal, round 2):
  a marked tag carrying real post-marker content is preserved (marker
  stripped) for <param> and -- since session 74 -- <summary>. <returns>
  still follows the ORIGINAL Task 3 rule: marked means engine-owned, full
  stop, regardless of what follows the marker.

  ============================================================================
  SESSION 74 (owner ruling, 2026-09-06): <summary> MOVED SIDES. READ THIS
  BEFORE "RESTORING" ASSERTION 1.
  ============================================================================
  The rule below -- "<summary> reverts to marked-means-engine-owned" -- was a
  deliberate, twice-adjudicated decision, and it was WRONG in a way no fixture
  could show. On the real 91-file sweep it deleted 53 words of a developer's
  prose out of DRagLint.Lint.Linter.pas (HarvestExceptions): someone had typed
  into an engine stub without removing its HTML comment, which is precisely the
  shape ruling D-4 calls a HUMAN's text. That was 53 of the 54 authored words
  the sweep still destroyed after session 73's stacked-region fix, and it is
  what kept the sweep blocked.

  The owner decided D-4 wins. The engine may now drop a marked <summary> ONLY
  when it holds no authored words -- i.e. when it is blank, or when the engine
  has something harvested to refill it with. Words it CANNOT replace are the
  human's: keep them, drop the marker.

  WHAT DID NOT CHANGE, and why the reasoning below is still worth reading:
  <returns> keeps the old rule (assertion 3), because the engine always has its
  own mined content to write there -- the "a human edit is not separable from
  the source changing" argument still holds when there IS competing engine
  text. It is only the nothing-to-refill-with case that changed. The narrower
  rule and its regression guard live in run_doc_p3_marked_prose_survives.ps1,
  which also pins that a REFILLABLE marked summary still refreshes (102 of
  those existed in src\ at the time, none with a blank body -- a blanket
  reading would have frozen every one).
  ============================================================================

  History: an earlier round of this fix tried to preserve marked+content for
  ALL THREE tags via an exact-string compare against freshly generated text
  (AFreshFill). The coordinator reversed that ruling on further review: the
  PLAN had already adjudicated <summary>/<returns> deliberately -- a human
  edit inside the markers is NOT separable from "the source comment
  changed" by the plan's own string comparison, so BOTH refresh, and a
  human takes ownership only by REMOVING the marker (Task 9's drift report
  is the documented, future safeguard). The exact-string compare was ALSO
  independently wrong: it is content-keyed ownership by the back door, more
  brittle than the StartsText('Observed:') sniff Task 1 deleted (whitespace
  normalization and legitimate code drift both defeat exact equality, where
  a prefix match would have survived both) -- reproduced and regression-
  tested separately in run_doc_p3_idempotent_edgecases.ps1.

  <param> remains the ONE exception: harvesting is explicitly out of scope
  for it forever, so "engine-owned, dropped" there is PERMANENT,
  unrecoverable loss with no refresh mechanism and no drift report ever able
  to surface it -- a decision the plan never made for summary/returns.

  Fixture fixtures\docp3\markededit.pas:
    * Foo(AValue: Integer): Integer -- ALREADY carries a marked <summary>,
      <param name="AValue">, and <returns>, each with REAL text typed after
      the marker (simulating a developer typing into an existing stub
      without removing the HTML comment).
    * Bar(AValue: Integer): Integer -- UNDOCUMENTED. Used to prove the
      DISTINCT nuance: the engine's own fresh <returns> refill (marker +
      mined 'Observed: ...' suffix) must NOT be misclassified as "a human
      edited this" on the very NEXT run just because it is marked+content --
      it must stay recognized as engine-owned so the marker survives across
      a fresh-to-repair transition, and idempotency holds.

  Drives `index` -> `document --unit --apply` and asserts:
    1. Foo's <summary> SURVIVES with the human's typed sentence, UNMARKED --
       marked, but holding authored words the engine has nothing to refill it
       with, so D-4 governs (session 74; this assertion previously pinned the
       exact opposite -- see the banner above before changing it back).
    2. Foo's <param name="AValue"> SURVIVES with its typed sentence,
       UNMARKED (marker stripped) -- the one narrow exception.
    3. Foo's <returns> is REGENERATED to the engine's own mined Observed
       case, marked -- the human's typed sentence is discarded (same
       deliberate deviation as summary); no separate 'Returns:' fact line
       (the tag itself carries the mined content, same as any other
       engine-owned/refilled returns).
    4. Bar gains a FRESH, MARKED <returns> (engine's own mined-Observed
       refill) -- the normal, unaffected omit-when-empty/refill behavior.
    5. Idempotency: reindex + a second --apply is byte-identical for BOTH
       symbols. In particular, Bar's <returns> marker MUST SURVIVE (not be
       stripped) -- proving the engine's own current output stays
       recognized as engine-owned across the fresh-to-repair transition.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\markededit.pas')).Path

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern. $null if the declaration is not found. Same
# scan-upward idiom the sibling p3 runners use.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = @()
  $j = $idx - 1
  while ($j -ge 0 -and $lines[$j].TrimStart() -match '^///') { $blockLines = ,($lines[$j]) + $blockLines; $j-- }
  return (($blockLines -join "`n") -replace '</?para>', '')
}

$MARK = '<!-- drag-lint:auto -->'

$scratch = Join-Path C:\TEMP 'draglint_docp3markededit'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'markededit.pas'
$db     = Join-Path $scratch 'docp3markededit.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --stubs is required so Bar (a fresh create whose only content is a
  # <returns> tag, with no facts fence) is kept -- the facts-only default
  # would otherwise skip it, same as run_doc_p3_strip.ps1's Plain.
  & $exePath document --unit $target --db $db --stubs --apply 2>$null | Out-Null
  Check 'document --unit --apply #1 exits 0' ($LASTEXITCODE -eq 0)

  $lines = [IO.File]::ReadAllLines($target)
  $fooBlock = Get-DocBlockAbove $lines '^function Foo\(AValue: Integer\): Integer;'
  Check 'Foo decl found' ($null -ne $fooBlock)

  # v(SESSION 74) -- REVERSED BY OWNER RULING, deliberately. See this file's
  # header. Was: "Foo's <summary> is GONE, and the typed sentence does not
  # survive anywhere (plan-sanctioned loss)". The plan's sanction did not
  # survive contact with real source: the same arm deleted 53 words out of
  # DRagLint.Lint.Linter.pas on the 91-file sweep. D-4 now governs, and the
  # engine may only drop a marked <summary> that holds no authored words.
  Check '1. Foo <summary> SURVIVES with its typed sentence (D-4: marked + authored = the human''s)' `
    ($null -ne $fooBlock -and ($fooBlock -match '<summary>') -and ($fooBlock -match 'A developer typed this after the marker\.'))
  Check "1. Foo's <summary> is now UNMARKED -- ownership transferred, so the next run cannot re-delete it" `
    ($null -ne $fooBlock -and (-not ($fooBlock -match [regex]::Escape('<summary>' + $MARK))))

  Check '2. Foo <param name="AValue"> SURVIVES with its typed text, unmarked (the one exception)' `
    (($lines | Where-Object { $_.Trim() -eq '/// <param name="AValue">Also typed after the marker.</param>' }).Count -eq 1)

  Check '3. Foo <returns> is REGENERATED to the mined Observed case, marked' `
    ($null -ne $fooBlock -and $fooBlock -match [regex]::Escape('<returns>' + $MARK) + '(?:[^<]*-- )?Observed:\s*AValue\.')
  Check "3. Foo's typed returns sentence does NOT survive (deliberate, plan-sanctioned loss)" `
    (-not ($lines -join "`n").Contains('Also typed here after the marker.'))
  Check '3. no separate Returns: fact line for Foo (mined content is IN the regenerated tag, not duplicated)' `
    ($null -eq $fooBlock -or (-not ($fooBlock -match 'Returns:\s*AValue\b')))

  $barBlock = Get-DocBlockAbove $lines '^function Bar\(AValue: Integer\): Integer;'
  Check 'Bar decl found' ($null -ne $barBlock)
  Check '4. Bar gained a fresh MARKED <returns> (mined Observed refill)' `
    ($null -ne $barBlock -and $barBlock -match [regex]::Escape('<returns>' + $MARK) -and $barBlock -match 'Observed:\s*AValue\.')

  # --- 5. Idempotency: reindex + 2nd apply -> byte-identical; Bar's marker survives ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  # --stubs is required so Bar (a fresh create whose only content is a
  # <returns> tag, with no facts fence) is kept -- the facts-only default
  # would otherwise skip it, same as run_doc_p3_strip.ps1's Plain.
  & $exePath document --unit $target --db $db --stubs --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check '5. idempotent: file byte-identical after reindex + 2nd apply' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  $linesAfter = [IO.File]::ReadAllLines($target)
  $barBlockAfter = Get-DocBlockAbove $linesAfter '^function Bar\(AValue: Integer\): Integer;'
  Check '5. Bar''s <returns> marker SURVIVES the repair pass (still engine-owned, not misclassified as hand-edited)' `
    ($null -ne $barBlockAfter -and $barBlockAfter -match [regex]::Escape('<returns>' + $MARK))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
