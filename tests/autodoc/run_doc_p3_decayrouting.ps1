<#
  run_doc_p3_decayrouting.ps1 -- Auto-Document Phase 3, Task 3d, GROUP C: the
  decay/routing class. Five register items, ALL of them pinned as CURRENT
  BEHAVIOUR rather than fixed. Read that as a deliberate verdict, not an
  omission: every one traces to the same property -- these shapes route to the
  FRESH-INSERT branch, which can only ADD a block, having neither a repair nor
  a delete -- and the alternative routing was measured, tried and reverted in
  an earlier round because the repair path DELETES the region and re-emits only
  what it models, destroying the hand-written tags these shapes carry.

  Pinning them here is the deliverable: each behaviour is now visible in the
  suite, so the day one of them is fixed the change announces itself, and the
  day one of them silently gets WORSE a runner goes red.

  N5 -- QuotedBlockExact. The fresh branch's guard refuses to insert a block
    whose lines already sit above the declaration. An author who quotes that
    block verbatim therefore suppresses the real insert, and the symbol
    silently never receives its own. Contrived; silent; uncovered until now.

  N7 -- QuotedBlockNearMiss. The guard's containment scan had never been
    exercised on its LOOP's negative path -- every committed shape answered
    False through the "inner is longer than outer" early-out. This shape has a
    SIX-line existing region and a FIVE-line block to insert, so the loop
    really runs and really compares, failing on one character (.pos vs .pas).
    It doubles as N5's control: change that one character back and the insert
    is suppressed again.

  N6 -- EmptyRemarksSibling. The converged output carries TWO sibling
    <remarks> elements, the author's empty one first. Stable and reversible,
    but not well-formed DocInsight, and the consequence is the same one T3f
    minor 4 has: a consumer that reads "the <remarks> element" gets the EMPTY
    one and never sees the facts.

  T3f minor 4 -- AttributedRemarksOrder. Same consequence, sharper: an
    attributed <remarks xml:lang="en"> is VALID XML doc that the parser's
    strict pattern cannot represent, so it is carried through verbatim as a
    residual line, which the emitter places BEFORE the facts block. Delphi
    Help Insight renders the author's element and silently ignores the facts.
    The existing pin (in run_doc_p3_residual_lines.ps1) records the element
    COUNT; this one records the ORDER, which is where the consequence lives.

  N4 -- DecayAddThenRemove, driven by this runner across four applies: add a
    caller, apply (a SECOND block is inserted, the first stays), remove that
    caller, apply. The engine now matches the FIRST block, reports the symbol
    up to date, and leaves the second on disk asserting a caller that no
    longer exists anywhere in the file. `document --strip --apply` recovers.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\decayrouting.pas')).Path

# $null when the decl is not found OR when it has no doc lines above it at all.
# Deliberately NOT '' for the second case: a "block was located" check reads
# $null -ne, and a doc block deleted outright would satisfy that against ''.
function Get-DocBlock([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i])
  }
  if ($acc.Count -eq 0) { return $null }
  return [string]::Join("`n", $acc.ToArray())
}
function Get-Md5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash.Substring(0,8) }
function New-Scratch([string]$slug) {
  $d = Join-Path C:\TEMP $slug
  if (Test-Path $d) { Remove-Item $d -Recurse -Force }
  New-Item -ItemType Directory -Path $d | Out-Null
  Copy-Item $fixture (Join-Path $d 'decayrouting.pas') -Force
  return $d
}

$patExact  = '^procedure QuotedBlockExact;'
$patNear   = '^procedure QuotedBlockNearMiss;'
$patSib    = '^procedure EmptyRemarksSibling;'
$patAttr   = '^procedure AttributedRemarksOrder;'
$patDecay  = '^procedure DecayAddThenRemove;'

Push-Location C:\TEMP
try {
  # ======================= PART 1: N5 / N7 / N6 / minor 4 ===================
  $scratch = New-Scratch 'draglint_docp3decayrouting'
  $target  = Join-Path $scratch 'decayrouting.pas'
  $db      = Join-Path $scratch 'q.sqlite'

  $before      = [IO.File]::ReadAllLines($target)
  $exactBefore = Get-DocBlock $before $patExact
  $nearBefore  = Get-DocBlock $before $patNear
  Check 'FIXTURE: the N5 and N7 doc blocks were located' ($null -ne $exactBefore -and $null -ne $nearBefore)
  # The two quoted blocks must differ in EXACTLY the file extension, or N7 is
  # not the control for N5 and either check could pass for its own reasons.
  Check 'FIXTURE: N5 quotes .pas and N7 quotes .pos -- the near miss is ONE character' `
    ($exactBefore -match [regex]::Escape('(decayrouting.pas)') -and $nearBefore -match [regex]::Escape('(decayrouting.pos)'))

  $md5s = @()
  for ($cycle = 1; $cycle -le 3; $cycle++) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    Check "cycle $cycle : index exits 0" ($LASTEXITCODE -eq 0)
    & $exePath document --unit $target --db $db --stubs --apply --json 2>$null | Out-Null
    Check "cycle $cycle : document --unit --apply exits 0" ($LASTEXITCODE -eq 0)
    $md5s += (Get-Md5 $target)
  }
  Check 'converges: md5 identical across all 3 apply cycles' `
    ($md5s[0] -eq $md5s[1] -and $md5s[1] -eq $md5s[2]) ("md5s=" + ($md5s -join ' '))

  $after = [IO.File]::ReadAllLines($target)

  # ==========================================================================
  # v(ADP3 T9): N5 / N6 / N7 ARE CLOSED. Every pin below that asserted the
  # stacking behaviour is RE-PINNED to the repaired behaviour.
  #
  # THE CAUSE, in one sentence: T9 added Existing.HasRemarksTag to the
  # repair-vs-fresh OR-chain in DRagLint.Doc.Document.pas, and EVERY shape in
  # this fixture is routed by an author's empty '/// <remarks></remarks>' -- the
  # exact term that was missing. The fixture's own header says so in as many
  # words: "the routing term reads TParsedDoc.HasContent, and an EMPTY
  # <remarks></remarks> contributes nothing to it (HasContent tests
  # Remarks <> '', not HasRemarksTag)". That is now no longer true, so every
  # shape here takes the REPAIR path and converges to ONE well-formed element.
  #
  # MEASURED, all three shapes, after 3 apply cycles:
  #   QuotedBlockExact     fences=1  <remarks>=1
  #   QuotedBlockNearMiss  fences=1  <remarks>=1
  #   EmptyRemarksSibling  fences=1  <remarks>=1
  # (was: 1/2, 2/2 and 1/2 respectively -- a stacked duplicate in each case.)
  #
  # NOTHING HAND-WRITTEN WAS DESTROYED, and that is the load-bearing claim
  # under the user's 2026-08-02 ruling (docs/lint/TRIAGE-the-22-harvest-repair.md).
  # N5's and N7's quoted text sat INSIDE a '<!-- drag-lint:auto BEGIN -->' ...
  # '<!-- drag-lint:auto END -->' fence -- the author quoted the engine's block
  # verbatim, markers and all -- so it is engine-owned under the marker contract
  # this whole unit is keyed on ("marked means engine-owned, full stop") and is
  # correctly regenerated. No UNMARKED author text is touched anywhere here.
  # --------------------------------------------------------------------------

  # --- N5 -------------------------------------------------------------------
  $exactAfter = Get-DocBlock $after $patExact
  Check 'N5 FIXED (T9): the verbatim quote no longer SUPPRESSES the insert -- the block is repaired, not left as the author''s copy' `
    ($null -ne $exactAfter -and $exactAfter -cne $exactBefore)
  Check 'N5 FIXED (T9): exactly ONE facts fence, and it is the ENGINE''s own (real file name), not the author''s quote' `
    ($null -ne $exactAfter -and (([regex]::Matches($exactAfter, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 1) -and
     $exactAfter.Contains('Called from: decayrouting.CallsQuotedBlockExact (decayrouting.pas)'))
  Check 'N5 FIXED (T9): exactly ONE <remarks> element -- well-formed DocInsight' `
    ($null -ne $exactAfter -and (([regex]::Matches($exactAfter, '<remarks[ >]')).Count -eq 1))

  # --- N7 -- the control, and the guard's loop negative path ----------------
  $nearAfter = Get-DocBlock $after $patNear
  Check 'N7 control: changing ONE character of the quote restores the insert' `
    ($null -ne $nearAfter -and $nearAfter -ne $nearBefore)
  # v(ADP3 T9) RE-PINNED: the near-miss quote is no longer carried through
  # beside a second block -- it is engine-MARKED content (it quotes the fence
  # markers too), so repair regenerates it with the real file name. The '.pos'
  # spelling disappearing is the fix working, not content loss.
  Check 'N7 FIXED (T9): the marked near-miss quote is REGENERATED, so the bogus .pos spelling is gone' `
    ($null -ne $nearAfter -and -not $nearAfter.Contains('(decayrouting.pos)'))
  Check 'N7 the engine''s OWN block was added beside it, with the real file name' `
    ($null -ne $nearAfter -and $nearAfter.Contains('Called from: decayrouting.CallsQuotedBlockNearMiss (decayrouting.pas)'))
  Check 'N7 FIXED (T9): exactly ONE fence on this symbol -- the stacked duplicate is gone' `
    ($null -ne $nearAfter -and (([regex]::Matches($nearAfter, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 1))

  # --- N6 -------------------------------------------------------------------
  $sibAfter = Get-DocBlock $after $patSib
  # N7's claim is specifically that the guard answers False through its SCAN
  # LOOP, not through the "inner is longer than outer" early-out. That is only
  # true while the existing region is at least as long as the block being
  # inserted, so derive both lengths and assert it, rather than asserting the
  # outcome and hoping. The engine's own block length is read off the N6 shape,
  # whose whole doc block is the author's ONE line plus exactly that block.
  #
  # LIMIT OF THIS DISCRIMINATION, stated rather than implied: it rules out the
  # ONE early-out that exists today, and the fixture guarantees the mismatch is
  # a single character on the FOURTH line of the inner sequence -- but nothing
  # here observes that the comparison actually advanced past offset 0 to reach
  # it. If CommentLinesContain later gained a DIFFERENT early-out, these checks
  # would keep passing while the deep-scan path went untested again. Proving
  # depth needs instrumentation inside the binary, which this suite has no way
  # to do from outside; this is the strongest available black-box statement.
  $engineBlockLines = ($sibAfter -split "`n").Count - 1
  $nearBeforeLines  = ($nearBefore -split "`n").Count
  Check 'N7 DISCRIMINATION: the existing region is at least as long as the block to insert, so the early-out CANNOT be what answers' `
    ($engineBlockLines -ge 1 -and $nearBeforeLines -ge $engineBlockLines) `
    "existing=$nearBeforeLines engineBlock=$engineBlockLines"
  # v(ADP3 T9) RE-PINNED, and this is the headline of the three: the shape that
  # produced "not well-formed DocInsight" (the fixture's own words) now produces
  # exactly ONE <remarks>. The author's empty element is ADOPTED as the container
  # for the engine's facts instead of being shadowed by a rival sibling -- which
  # is precisely why routing to repair EARLIER is non-destructive rather than
  # destructive: there is never a surplus element for a later cycle to delete.
  Check 'N6 FIXED (T9): the converged output has exactly ONE <remarks> element -- well-formed DocInsight' `
    ($null -ne $sibAfter -and (([regex]::Matches($sibAfter, '<remarks[ >]')).Count -eq 1))
  Check 'N6 FIXED (T9): a consumer reading "the remarks" now sees the facts, not the author''s empty element' `
    ($null -ne $sibAfter -and $sibAfter.Contains('Called from: decayrouting.CallsEmptyRemarksSibling (decayrouting.pas)'))
  Check 'N6 FIXED (T9): no stray empty <remarks></remarks> line survives beside it' `
    ($null -ne $sibAfter -and -not (($sibAfter -split "`n") | Where-Object { $_.Trim() -ceq '/// <remarks></remarks>' }))

  # --- T3f minor 4 ----------------------------------------------------------
  $attrAfter = Get-DocBlock $after $patAttr
  Check 'T3f minor 4: the attributed <remarks> SURVIVES (T3f''s own guarantee, unchanged)' `
    ($null -ne $attrAfter -and $attrAfter.Contains('<remarks xml:lang="en">Attributed remarks prose must survive.</remarks>'))
  Check 'T3f minor 4: a facts block WAS written, so there really are two elements to order' `
    ($null -ne $attrAfter -and $attrAfter.Contains('drag-lint:auto BEGIN'))
  # THE CONSEQUENCE, which the existing element-count pin does not record: the
  # author's element comes FIRST, so a spec-conforming consumer renders it and
  # silently ignores the facts block below.
  # -1 rather than a null-reference exception when the block is missing, so a
  # missing block reads as a readable FAIL on the check below.
  $attrIdx  = if ($null -ne $attrAfter) { $attrAfter.IndexOf('<remarks xml:lang="en">') } else { -1 }
  $factsIdx = if ($null -ne $attrAfter) { $attrAfter.IndexOf('drag-lint:auto BEGIN')    } else { -1 }
  Check 'T3f minor 4 KNOWN GAP, pinned: the AUTHOR''s <remarks> is emitted BEFORE the facts block, so Help Insight never shows the facts' `
    ($attrIdx -ge 0 -and $factsIdx -gt $attrIdx) "authorAt=$attrIdx factsAt=$factsIdx"

  # ======================= PART 2: N4, the decay sequence ===================
  $s2 = New-Scratch 'draglint_docp3decayrouting_n4'
  $t2 = Join-Path $s2 'decayrouting.pas'
  $d2 = Join-Path $s2 'q.sqlite'

  # (a) one caller
  & $exePath index $s2 --db $d2 2>$null | Out-Null
  Check 'N4 (a) index exits 0' ($LASTEXITCODE -eq 0)
  & $exePath document --unit $t2 --db $d2 --stubs --apply --json 2>$null | Out-Null
  Check 'N4 (a) document --unit --apply exits 0' ($LASTEXITCODE -eq 0)
  $decayA = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  Check 'N4 (a) one caller: a facts block is written naming it' `
    ($null -ne $decayA -and $decayA.Contains('Called from: decayrouting.CallsDecayAddThenRemove'))
  Check 'N4 (a) exactly one fence so far' `
    ($null -ne $decayA -and (([regex]::Matches($decayA, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 1))

  # (b) ADD a second caller through the fixture's own markers, then apply
  $txt = [IO.File]::ReadAllText($t2)
  Check 'N4 FIXTURE: both extra-caller markers are present' `
    ($txt.Contains('// N4-EXTRA-CALLER-DECL') -and $txt.Contains('// N4-EXTRA-CALLER-IMPL'))
  $txt = $txt.Replace('// N4-EXTRA-CALLER-DECL', "procedure ExtraCallerOfDecay;")
  $txt = $txt.Replace('// N4-EXTRA-CALLER-IMPL', "procedure ExtraCallerOfDecay;`r`nbegin`r`n  DecayAddThenRemove;`r`nend;")
  [IO.File]::WriteAllText($t2, $txt)
  & $exePath index $s2 --db $d2 2>$null | Out-Null
  Check 'N4 (b) index exits 0' ($LASTEXITCODE -eq 0)
  & $exePath document --unit $t2 --db $d2 --stubs --apply --json 2>$null | Out-Null
  Check 'N4 (b) document --unit --apply exits 0' ($LASTEXITCODE -eq 0)
  $decayB = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  # v(ADP3 T9) RE-PINNED: the second caller is now folded into the EXISTING
  # block by the repair path -- one fence, one Called-from line naming both --
  # instead of a second block being stacked below the first. Measured:
  #   (a) 'Called from: ...CallsDecayAddThenRemove (decayrouting.pas)'
  #   (b) 'Called from: ...CallsDecayAddThenRemove (decayrouting.pas), ...ExtraCallerOfDecay (decayrouting.pas)'
  Check 'N4 (b) FIXED (T9): the SINGLE existing block is REPAIRED to name both callers -- no second block is stacked' `
    ($null -ne $decayB -and $decayB.Contains('ExtraCallerOfDecay') -and
     (([regex]::Matches($decayB, [regex]::Escape('drag-lint:auto BEGIN'))).Count -eq 1))
  # LINE-EXACT, not Contains: the two-caller line the second block carries has
  # the one-caller line as a literal PREFIX, so a substring test would pass
  # even if the first block had been repaired away.
  # @() forces an array: a single-match pipeline returns a bare STRING, whose
  # [0] is its first CHARACTER, which would compare against nothing.
  $oneCallerLine = @($decayA -split "`n" | Where-Object { $_ -match 'Called from:' })
  Check 'N4 (b) FIXTURE: block (a) had exactly one Called-from line to look for' ($oneCallerLine.Count -eq 1)
  # v(ADP3 T9) RE-PINNED, exact inverse of the old assertion: the one-caller line
  # must now be GONE, because the block was repaired in place rather than left
  # verbatim beneath a newer one. Still line-exact, for the reason the old check
  # gave -- the one-caller line is a literal PREFIX of the two-caller line, so a
  # substring test would report "absent" even when it is sitting right there.
  Check 'N4 (b) FIXED (T9): the stale one-caller line is GONE -- the first block was repaired, not shadowed' `
    ($oneCallerLine.Count -eq 1 -and (@($decayB -split "`n" | Where-Object { $_ -ceq $oneCallerLine[0] }).Count -eq 0))

  # (c) REMOVE that caller and apply again
  $txt = [IO.File]::ReadAllText($t2)
  $txt = $txt.Replace("procedure ExtraCallerOfDecay;`r`nbegin`r`n  DecayAddThenRemove;`r`nend;", '')
  $txt = $txt.Replace("procedure ExtraCallerOfDecay;`r`n", '')
  [IO.File]::WriteAllText($t2, $txt)
  Check 'N4 (c) FIXTURE: the extra caller is really gone from the source' `
    (-not ([IO.File]::ReadAllText($t2)).Contains('procedure ExtraCallerOfDecay'))
  & $exePath index $s2 --db $d2 2>$null | Out-Null
  Check 'N4 (c) index exits 0' ($LASTEXITCODE -eq 0)
  $j = (& $exePath document --qname 'decayrouting.DecayAddThenRemove' --db $d2 --json 2>$null) -join ' '
  Check 'N4 (c) document --qname exits 0' ($LASTEXITCODE -eq 0) $j
  # v(ADP3 T9) RE-PINNED -- THE DECAY GAP ITSELF IS CLOSED. The register entry
  # N4 was "decayed facts report `unchanged` forever": the engine matched the
  # older of two stacked blocks, declared the symbol up to date, and left a
  # block on disk naming a caller that no longer existed, with no way back
  # except --strip. There are no longer two blocks to match the wrong one of, so
  # the engine now SEES the decay and offers the repair. Measured JSON here:
  #   {"action":"extended","edits":2,"applied":false}
  # ("applied":false only because this probe deliberately omits --apply -- the
  # point is that edits are OFFERED, where the pin required edits:0.)
  Check 'N4 FIXED (T9): the engine now DETECTS the decayed fact and offers a repair (was: unchanged/0 forever)' `
    ($j -match '"action":"extended"' -and $j -notmatch '"edits":0[,}]') $j
  $decayC = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  # The stale caller is still on DISK at this point, and must be -- --apply was
  # not passed. What changed is that the engine no longer claims otherwise.
  Check 'N4 (c) the stale caller is still on disk, since --apply was not passed (the edit was offered, not made)' `
    ($null -ne $decayC -and $decayC.Contains('ExtraCallerOfDecay'))
  # ...and applying it actually removes the stale fact. This is the check the
  # old KNOWN-GAP pin could not have: recovery no longer requires --strip.
  & $exePath document --unit $t2 --db $d2 --stubs --apply 2>$null | Out-Null
  $decayC2 = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  Check 'N4 FIXED (T9): --apply now REPAIRS the decayed block -- the removed caller is gone, no --strip needed' `
    ($null -ne $decayC2 -and -not $decayC2.Contains('ExtraCallerOfDecay') -and
     $decayC2.Contains('Called from: decayrouting.CallsDecayAddThenRemove'))

  # (d) the documented recovery
  & $exePath document --unit $t2 --db $d2 --strip --apply 2>$null | Out-Null
  Check 'N4 (d) document --unit --strip --apply exits 0' ($LASTEXITCODE -eq 0)
  $decayD = Get-DocBlock ([IO.File]::ReadAllLines($t2)) $patDecay
  Check 'N4 recovery: --strip --apply removes the stale fact' `
    ($null -eq $decayD -or -not $decayD.Contains('ExtraCallerOfDecay'))
  Check 'N4 recovery: --strip --apply removes EVERY engine block on the symbol' `
    ($null -eq $decayD -or -not $decayD.Contains('drag-lint:auto BEGIN'))
  # v(ADP3 T9) KNOWN GAP, pinned WITH ITS EVIDENCE -- and this one is a genuine
  # residual loss, disclosed rather than papered over.
  #
  # The author wrote exactly one line, '/// <remarks></remarks>'. After
  # apply -> strip the whole doc block is GONE ($null), so that line does not
  # survive the round trip.
  #
  # IT IS NOT A T9 REGRESSION: probed directly against the pre-T9 staged exe,
  # this shape returned $null there too. T9 changed which BRANCH writes the
  # block, not what --strip leaves behind.
  #
  # WHY IT IS NOT FIXED HERE. Once repair ADOPTS the author's <remarks> as the
  # container for the facts, the resulting element is byte-identical to one the
  # engine created from nothing. Both have unmarked <remarks>/</remarks> tags
  # and nothing but marked content between them, so --strip cannot tell "restore
  # the author's empty element" from "remove the block I invented" -- and
  # guessing wrong the other way would litter every engine-created block with a
  # stray '<remarks></remarks>' residue that nothing could ever clean up.
  # Distinguishing them needs a marker ON THE WRAPPER, which changes emitted
  # bytes for every documented symbol in the repo and belongs in its own task,
  # not smuggled into T9. Filed in docs/lint/BACKLOG.md.
  #
  # The loss is bounded and information-free: an EMPTY tag. Any <remarks> with
  # actual prose is preserved -- run_doc_p3_idempotency_sweep's NON-DESTRUCTIVE
  # checks and the T3f minor 4 attributed-remarks checks above both cover that.
  Check 'N4 KNOWN GAP, pinned (pre-dates T9): the author''s EMPTY <remarks></remarks> does NOT survive apply->strip' `
    ($null -eq $decayD) ("decayD=" + $(if ($null -eq $decayD) { '<null>' } else { "[$decayD]" }))

  # --- encoding -------------------------------------------------------------
  $bad = @([IO.File]::ReadAllBytes($target) | Where-Object { $_ -gt 127 }).Count
  Check 'every byte written back is 7-bit ASCII' ($bad -eq 0) "nonascii=$bad"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
