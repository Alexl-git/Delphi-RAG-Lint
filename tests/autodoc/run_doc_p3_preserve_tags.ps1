<#
  run_doc_p3_preserve_tags.ps1 -- Auto-Document Phase 3, Task 3b: preserve
  hand-written <exception>/<example>/<since>/<deprecated/>/<seealso> tags
  through TDocRegions.MergeComment's repair path.

  Background (pre-existing, predates the whole autodoc feature -- traced to
  24efbb9, the commit that first wrote a real MergeComment; NOT a Phase 3
  regression): the repair path re-emitted only <summary>/<param>/<returns>
  and hand-written <remarks> prose. Every OTHER hand-written tag it parsed
  (Exceptions/ExampleText/SeeAlso/SinceText/Deprecated on TParsedDoc) was
  silently DROPPED the moment the repair path ran for ANY reason -- see
  task-3b-brief.md's confirmed evidence. Phase 3's headline promise is that
  hand-written documentation wins, and Task 3 raised the blast radius from
  "comment replaced by a stub" to "comment deleted", so this closes the gap.

  Fixture fixtures\docp3\preserve_tags.pas:
    * AllTags(AValue): ALL FIVE tags plus <summary>/<param>/<returns>, with a
      caller (CallsAllTags) so Facts.CalledFrom is non-empty and Merged is
      forced non-empty (the destructive branch fires from <summary> alone,
      independent of the caller -- but a caller makes this the realistic,
      facts-bearing shape the brief's own confirmed evidence and "why this
      task is load-bearing" section use). Tags are written in the SAME fixed
      order MergeComment's repair path emits them in, so document --strip
      --apply can recover the ORIGINAL bytes exactly (see the fixture's own
      header comment).
    * ExceptionOnlyHasCaller: ONLY <exception>, WITH a caller
      (CallsExceptionOnly) so Facts.CalledFrom is non-empty and Merged is
      forced non-empty by the facts ALONE -- this reaches the UNGUARDED
      delete+insert repair branch directly, unlike a fact-free <exception>-
      only comment (already left untouched today by Task 3's
      RegionFullyEngineOwned guard -- see run_doc_p3_unhandledtags.ps1's
      HasException case, empirically confirmed unaffected pre-fix while
      developing this test). A fact-free version of this case would pass
      whether or not this fix exists, so it would not be load-bearing.
    * NoExoticTags: a plain hand-written <summary>, none of the five tags.
      The hand-written summary alone already routes this through the repair
      path (ExistingHasAnyTag is True from HasSummaryTag), proving the
      repair path fabricates none of the five even when it genuinely runs.
    * BareDeprecatedOnly: ONLY <deprecated/>, WITH a caller -- the Dispatch-
      sniff isolation case (Task 3b brief's "second known trap"). AllTags/
      ExceptionOnlyHasCaller/NoExoticTags ALL also carry <summary> or
      <exception>, both already in HasXmlTags' sniff before this task, so
      none of them actually exercise the sniff fix on their own. A comment
      whose ONLY tag is <deprecated/> is the genuinely isolating case:
      pre-fix, Dispatch mis-routes it to ParseOneline (the literal text
      becomes a bogus "summary"), a DIFFERENT failure mode from the tag
      simply being dropped (it gets nonsensically re-wrapped instead).
    * TSeeAlsoHost.DoA: hand-written <since>/<seealso> COEXISTING with the
      opt-in auto-generated <since>/<seealso> RenderFactsBlock emits INSIDE
      the AUTO_BEGIN..AUTO_END fence -- the parser's regexes do not respect
      the fence boundary (Task 3b brief's Trap 1), so a naive preserve-loop
      would re-emit the fence-internal auto lines a SECOND time outside the
      fence, and since RenderFactsBlock regenerates the same auto lines
      inside the fence every run regardless, the duplicate would grow
      without bound on every subsequent --apply. DoB/DoC are DoA's resolved
      callees AND its siblings (--seealso related-set); DoA's declaration
      line, once git-committed, gives --since a real commit date.

  PART 1 (scratch1, no git): --qname-scoped applies (AllTags,
  ExceptionOnlyHasCaller, NoExoticTags, BareDeprecatedOnly individually --
  so TSeeAlsoHost/the caller procedures are NEVER targeted and stay
  byte-for-byte untouched, which is what lets the round-trip check in step
  5 be a plain whole-file byte compare rather than a span-scoped one).
    1. Apply each of the four once; assert every hand-written tag on each
       survives verbatim, no exotic tag is fabricated on NoExoticTags, and
       each symbol's own facts block (a real "Called from:" line) is also
       present -- proving a REAL merge ran, not a no-op that left the region
       untouched (which is what happens for a fact-free <exception>-only
       comment today, see above). BareDeprecatedOnly additionally asserts
       the tag reads back as a CLEAN, standalone <deprecated/> line, never
       nonsensically wrapped inside a fabricated <summary>.
    2. Every emitted /// line is 7-bit ASCII.
    3. Idempotency (the "why this task is load-bearing" 2-cycle proof):
       reindex, re-apply all four again -- each reports "unchanged"/0 edits,
       the whole file is byte-identical to after the first round, and every
       hand-written tag still reads back correctly. A single-apply-cycle
       test would have passed against Task 3's OWN mitigation (an additive
       insert that merges into a destructive repair exactly one cycle later
       for tag types RegionFullyEngineOwned's guard alone protects) and
       proven nothing about a genuine repair-path fix.
    4. Strip round-trip: `document --strip --apply` returns the file to its
       pre-apply bytes, all hand-written tags (on all four symbols) intact
       -- Task 2's round-trip guarantee was never exercised against these
       tag types before this task. A second --strip --apply is a no-op.

  PART 2 (scratch2, git-enabled): the Trap 1 conflation-avoidance proof.
  `document --qname ... --seealso --since --apply` TWICE (with a reindex
  between) on TSeeAlsoHost.DoA: asserts the hand-written <since>/<seealso>
  and the auto-generated <since>/<seealso> (inside the fence) all appear
  exactly once each after the FIRST apply, and the file is BYTE-IDENTICAL
  after the SECOND apply -- if the preserve-loop naively re-emitted whatever
  the parser handed it (which also matches fence-internal auto lines, since
  the regex does not respect the fence boundary), the hand-written-looking
  count would double on the second cycle. This is the acceptance test for
  the whole task, per the brief.

  PART 3 (scratch1, continued -- coordinator review round 1 findings):
    * NestedTagsInSummary (Critical 1): an inline <see cref>/<exception cref>
      NESTED inside <summary> prose must survive as part of the summary's
      own verbatim text, WITHOUT ALSO being extracted and re-emitted as a
      standalone <seealso>/<exception> sibling. THREE apply cycles (with a
      reindex between each), asserting byte-identity from cycle 2 on --
      growth, not disappearance, was this defect's failure mode, so a
      single- or double-apply test proves nothing here (a naive
      implementation is byte-IDENTICAL to a correct one after cycle 1; only
      cycle 2 onward diverges). Reproduces the shape found on this repo's
      own src/report/DRagLint.Convert.Rules.pas (TConversionRule's <summary>
      carries an inline <see cref="Kind"/>) -- separately verified directly
      against that real file (not asserted here; a test fixture should not
      depend on unrelated production source staying byte-identical forever).
    * GappedDeprecatedMessage (Important 2 + gapped shape): the MESSAGE on a
      hand-written <deprecated>message</deprecated> must survive, not
      collapse to a bare <deprecated/>; comment is separated from its
      declaration by a blank line (every other symbol in this fixture abuts
      its declaration).
    * BareSeeOnly (Critical 1, second symptom): a bare, standalone
      <see cref="X"/> must round-trip as <see>, never silently rewritten to
      <seealso> (RxSee's own alternation conflates both spellings into one
      array; blindly re-emitting every entry as <seealso> would destroy the
      author's <see> and fabricate a <seealso> they never wrote).
    * ProseMentionsSeeAlso / ProseMentionsSeed / ProseMentionsDeprecatedSoon
      (Important 3): plain prose merely resembling a tag (a bare <seealso>
      with no cref, "<seed>", "<deprecatedSoon>") must dispatch as plain
      prose and survive UNTRUNCATED -- pre-fix-round-1, Dispatch's bare
      '<see'/'<deprecated' prefixes over-matched all three, mis-routing to
      ParseXmlDoc, whose untagged-prefix-becomes-summary fallback truncated
      each at its first '<'.
    * EmptyExampleSurvives (Minor 1): a deliberately empty
      <example></example> (a human's blank slot) must survive, not be
      dropped -- the old gate (ExampleText <> '') could not tell "absent"
      apart from "present but empty"; HasExampleTag (mirroring
      HasSummaryTag) does.

  PART 4 (scratch1, continued -- coordinator review round 2, NEW IMPORTANT):
  a comment Dispatch routes to XML parsing (it LOOKS tag-shaped) can still
  resolve to NO recognized tag at all when the shape is malformed in a way
  neither the sniff nor the underlying regex tolerates -- pre-fix, this made
  MergeComment emit NOTHING, silently DELETING the entire hand-written ///
  line the moment a facts block later merged adjacent to it (needs a SECOND
  apply cycle to surface: MergeAdjacentSameKind is what first folds the
  freshly-inserted facts block into the same scanned region). Two further
  cases here (AllCapsDeprecatedTag, TabSeparatedSeeAlso) are genuinely
  RECOGNIZED once the sniff itself is derived from the same regex objects
  the parser matches against (IsMatch, not a hand-maintained Pos()
  approximation) -- see DRagLint.Parser.DocComments.pas' EnsureSniffRegexes.
    * SpaceBeforeCloseDeprecated / UnclosedDeprecated / ExceptionNoCrefAttr /
      UnclosedExampleTag: each is a lone malformed tag with nothing else in
      the comment -- NO tag is recognized at all, so the general fallback
      (treat the raw text as prose instead of an empty summary) takes over;
      each survives, wrapped in a fabricated <summary> holding the ORIGINAL
      literal (malformed) text, stable from cycle 1.
    * AllCapsDeprecatedTag: Pos() is case-sensitive, every regex in this unit
      carries roIgnoreCase -- the old sniff mismatched on this axis. Now
      genuinely recognized: round-trips as a real <deprecated>...</deprecated>
      (canonical lowercase spelling), NOT wrapped in a fabricated <summary>.
    * SeeAlsoNoCrefWithSummary: the malformed <seealso> sits ALONGSIDE a
      real, well-formed <summary> -- the summary (and the comment as a
      whole) is NOT deleted. v(ADP3 T3f): the malformed seealso fragment is
      captured by nothing (RxSee requires cref= too), so the emitter accounts
      for nothing on that line and Task 3f's residual carry-through now hands
      the WHOLE line back verbatim. This used to be a pinned, accepted
      "unmodeled tag" gap (loss class L1); the pin below is flipped and now
      asserts the round-trip.
    * TabSeparatedSeeAlso: a TAB (not a space) before cref= -- RxSee's own
      '\s+' already tolerated this; the OLD sniff's literal single-space
      '<seealso ' did not. SeeAlso presence alone does not satisfy
      Document.pas' ExistingHasAnyTag (same narrow OR-chain BareSeeOnly
      already exercises), so cycle 1 takes the fresh/additive path and
      leaves the original (tab-bearing) line untouched; cycle 2 is where
      MergeAdjacentSameKind folds the facts block in and the repair path
      normalizes the tab to a canonical single space -- proven safe (never
      DELETED) across the exact two-cycle mechanism the defect itself needs.
    Each row applies 3 cycles (reindex between each): cycle 1 proves no
    IMMEDIATE full deletion; cycle 2 proves the case survives the
    additive-then-merge mechanism (where the pre-fix defect actually fired);
    cycle 3 proves a stable fixed point (byte-identical to cycle 2).

  PART 5 (scratch1, continued -- coordinator review round 3): Critical 1's
  duplication is confirmed genuinely closed (4 cycles, 11 nesting
  combinations plus three real repo files, md5-identical from cycle 2 --
  verified separately, not re-asserted here). Three findings remained:
    * NEW IMPORTANT: <since> read its body from a STRIPPED parse
      (StandaloneSince.SinceText), so nested content was silently deleted,
      and '<since><deprecated>2.0-beta</deprecated></since>' deleted the
      ENTIRE comment (both tags' own stripped-self-exclusion erased the
      OTHER, so both failed their presence gate simultaneously). Fixed with
      a real HasSinceTag presence flag (mirroring HasSummaryTag/
      HasReturnsTag/HasExampleTag): gate on StandaloneSince.HasSinceTag,
      emit AExisting.SinceText. SinceWithNestedException/
      SinceWithNestedExample/SinceWithNestedDeprecated cover the reviewer's
      own three reproductions, each stable byte-for-byte from cycle 1.
    * STRUCTURAL 1: PRESERVED_VERBATIM_CONTAINERS was read at exactly ONE
      site (BuildStandaloneFor) -- no emitter for summary/param/returns/
      remarks consulted a filtered view at all, so a tag nested inside one
      of the four "rich-body" containers (exception/example/deprecated)
      still fabricated a standalone summary/param/returns/remarks sibling
      the author never wrote. Fixed by giving all four emission sites the
      same "presence from a Standalone view, content from AExisting" split
      the four round-2 fields already had (param correlates by NAME, same
      pattern as exception's cref correlation; summary/returns/remarks have
      no natural key, so they read AExisting for content -- see
      MergeComment's own remarks for why, and for a DISCLOSED residual this
      surfaced: DeprecatedWithNestedReturns/ExampleWithNestedRemarks below
      were correct and stable on cycle 1, but a DEEPER, cycle-2+ issue
      remained for these unkeyed fields specifically when
      MergeAdjacentSameKind causes a genuine auto-inserted tag to fold into
      the same region as a nested-elsewhere look-alike.
      v(ADP3 T3h) CLOSED that residual (register N2): content for the unkeyed
      singular tags now comes from the occurrence its own presence gate is
      True ABOUT, located through a length-preserving mask. All four rows are
      therefore stable byte-for-byte from cycle 1 through cycle 3 now, and
      the two formerly-residual ones additionally assert the strip
      round-trip -- the property the defect actually broke.
    * STRUCTURAL 2: the sniff regexes were duplicated string literals (a
      SEPARATE, sniff-only cache with pattern strings copied from
      ParseXmlDoc's own locals), and only 4 of the parser's 10 tag regexes
      had been converted to shared/hoisted objects at all -- the other six
      (summary/param/returns/remarks/exception/example) still sniffed via a
      case-sensitive Pos() prefix. Fixed by hoisting ALL TEN of ParseXmlDoc's
      own regex locals into ONE file-scope, lazily-built set that BOTH
      ParseXmlDoc's actual matching and Dispatch's sniff read from -- one
      declaration of each pattern, not two, and it also removes the
      nine-TRegEx-per-call construction cost ParseXmlDoc used to pay on
      every doc comment routed to it. No new fixture rows of its own (this
      is exercised implicitly by every OTHER row in this file parsing
      correctly); verified by revert-to-RED (see the task report).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\preserve_tags.pas')).Path

# Returns the contiguous run of ///-prefixed lines immediately above the FIRST
# line matching $declPattern. $null if the declaration is not found. Same
# scan-upward idiom run_doc_seealso.ps1/run_doc_since.ps1 use -- scoped to ONE
# declaration's own block so a check cannot bleed into a DIFFERENT decl's doc
# comment elsewhere in the file. Review round 1 (gapped-shape coverage):
# tolerates ONE leading blank line before the scan starts, matching
# FindDocRegionAbove's own AllowGap=1 default, so a GAPPED comment (blank
# line between it and the declaration -- GappedDeprecatedMessage) is found
# the same way an abutting one is; a no-op for every abutting case (the line
# immediately above the decl is already a /// line there, so the blank-skip
# never triggers).
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $i = $idx - 1
  if (($i -ge 0) -and ($lines[$i].Trim() -eq '')) { $i-- }
  $blockLines = New-Object System.Collections.Generic.List[string]
  for (; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $lines[$i])
  }
  return [string]::Join("`n", $blockLines.ToArray())
}

Push-Location C:\TEMP
try {
  # =====================================================================
  # PART 1: --qname-scoped applies, idempotency, strip round-trip
  # =====================================================================
  $scratch = Join-Path C:\TEMP 'draglint_docp3preservetags'
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $target = Join-Path $scratch 'preserve_tags.pas'
  $db     = Join-Path $scratch 'preservetags.sqlite'
  Copy-Item $fixture $target -Force

  $before = [IO.File]::ReadAllBytes($target)

  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # Reindexes before applying: each --qname apply rewrites the file and shifts
  # line numbers for every symbol BELOW the one just touched, so the index
  # must be refreshed before the NEXT --qname call reads it -- otherwise that
  # call resolves a STALE line number, does not find the region that has
  # actually moved, and silently takes the "no prior comment" fresh-insert
  # path instead of the repair path this test means to exercise. This is the
  # same "reindex after any change" discipline the whole tool asks of a human
  # caller, applied here between successive scoped applies to the same file.
  function Apply-One([string]$qname) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    return (& $exePath document --qname $qname --db $db --apply --json 2>$null) -join "`n"
  }

  # --- cycle 1 ---
  $jAll = Apply-One 'preserve_tags.AllTags'
  Check 'AllTags apply #1 exits 0' ($LASTEXITCODE -eq 0) $jAll
  Check 'AllTags apply #1: action=extended (a real facts block was added)' ($jAll -match '"action":"extended"') $jAll

  $jExc = Apply-One 'preserve_tags.ExceptionOnlyHasCaller'
  Check 'ExceptionOnlyHasCaller apply #1 exits 0' ($LASTEXITCODE -eq 0) $jExc
  Check 'ExceptionOnlyHasCaller apply #1: action=extended (the UNGUARDED repair branch ran, not a guard-protected no-op)' `
    ($jExc -match '"action":"extended"') $jExc

  $jNo = Apply-One 'preserve_tags.NoExoticTags'
  Check 'NoExoticTags apply #1 exits 0' ($LASTEXITCODE -eq 0) $jNo
  Check 'NoExoticTags apply #1: action=unchanged (nothing hand-written to change, nothing fabricated)' `
    ($jNo -match '"action":"unchanged"') $jNo

  $jDep = Apply-One 'preserve_tags.BareDeprecatedOnly'
  Check 'BareDeprecatedOnly apply #1 exits 0' ($LASTEXITCODE -eq 0) $jDep
  Check 'BareDeprecatedOnly apply #1: action=extended (dispatch-sniff isolation case, genuinely merged)' `
    ($jDep -match '"action":"extended"') $jDep

  $lines1 = [IO.File]::ReadAllLines($target)

  # --- AllTags: all five tags + summary/param/returns survive, plus a real facts block ---
  $allTagsBlock = Get-DocBlockAbove $lines1 '^function AllTags\(AValue: Integer\): Integer;'
  Check 'AllTags decl + doc-comment found' ($null -ne $allTagsBlock -and $allTagsBlock -ne '')
  Check 'AllTags: <summary> survives' ($allTagsBlock -match [regex]::Escape('<summary>Doubles AValue; hand-written summary must survive.</summary>'))
  Check 'AllTags: <deprecated/> survives' ($allTagsBlock -match [regex]::Escape('<deprecated/>'))
  Check 'AllTags: <param> survives' ($allTagsBlock -match [regex]::Escape('<param name="AValue">Hand-written param desc; must survive.</param>'))
  Check 'AllTags: <returns> survives' ($allTagsBlock -match [regex]::Escape('<returns>The doubled value.</returns>'))
  Check 'AllTags: <exception> survives' ($allTagsBlock -match [regex]::Escape('<exception cref="EFoo">Raised when AValue is negative.</exception>'))
  Check 'AllTags: <example> survives' ($allTagsBlock -match [regex]::Escape('<example>AllTags(21) returns 42.</example>'))
  Check 'AllTags: <seealso> survives' ($allTagsBlock -match [regex]::Escape('<seealso cref="Other.RelatedThing"/>'))
  Check 'AllTags: <since> survives' ($allTagsBlock -match [regex]::Escape('<since>1.2</since>'))
  Check 'AllTags: a real facts block was added (Called from: CallsAllTags)' `
    ($allTagsBlock -match '<!-- drag-lint:auto BEGIN -->' -and $allTagsBlock -match 'Called from:.*CallsAllTags')

  # --- ExceptionOnlyHasCaller: exception survives, alongside a real facts block ---
  $excBlock = Get-DocBlockAbove $lines1 '^procedure ExceptionOnlyHasCaller;'
  Check 'ExceptionOnlyHasCaller decl + doc-comment found' ($null -ne $excBlock -and $excBlock -ne '')
  Check 'ExceptionOnlyHasCaller: <exception> survives' ($excBlock -match [regex]::Escape('<exception cref="EBar">Raised on bad input.</exception>'))
  Check 'ExceptionOnlyHasCaller: a real facts block was added (Called from: CallsExceptionOnly)' `
    ($excBlock -match '<!-- drag-lint:auto BEGIN -->' -and $excBlock -match 'Called from:.*CallsExceptionOnly')

  # --- NoExoticTags: summary survives, none of the five tags appear (no fabrication) ---
  $noExoticBlock = Get-DocBlockAbove $lines1 '^procedure NoExoticTags;'
  Check 'NoExoticTags decl + doc-comment found' ($null -ne $noExoticBlock -and $noExoticBlock -ne '')
  Check 'NoExoticTags: <summary> survives' ($noExoticBlock -match [regex]::Escape('<summary>Plain summary; no exotic tags here.</summary>'))
  Check 'NoExoticTags: no <exception> fabricated'  ($null -eq $noExoticBlock -or (-not ($noExoticBlock -match '<exception')))
  Check 'NoExoticTags: no <example> fabricated'    ($null -eq $noExoticBlock -or (-not ($noExoticBlock -match '<example>')))
  Check 'NoExoticTags: no <since> fabricated'      ($null -eq $noExoticBlock -or (-not ($noExoticBlock -match '<since>')))
  Check 'NoExoticTags: no <deprecated/> fabricated' ($null -eq $noExoticBlock -or (-not ($noExoticBlock -match '<deprecated')))
  Check 'NoExoticTags: no <seealso> fabricated'    ($null -eq $noExoticBlock -or (-not ($noExoticBlock -match '<seealso')))

  # --- BareDeprecatedOnly: dispatch-sniff isolation (Task 3b's "second known
  # trap"). Pre-fix, Dispatch mis-routes a bare '<deprecated/>'-only comment
  # to ParseOneline, so the literal text becomes a bogus "summary" and a
  # repair pass re-wraps it as '<summary><deprecated/></summary>' -- assert
  # BOTH that the clean, standalone tag is present AND that no such
  # fabricated <summary> wrapper exists (the two together isolate the sniff
  # fix specifically, since every OTHER symbol above also carries <summary>
  # or <exception>, which were already in the sniff before this task).
  $bareDepBlock = Get-DocBlockAbove $lines1 '^procedure BareDeprecatedOnly;'
  Check 'BareDeprecatedOnly decl + doc-comment found' ($null -ne $bareDepBlock -and $bareDepBlock -ne '')
  Check 'BareDeprecatedOnly: clean, standalone <deprecated/> survives' `
    ($bareDepBlock -match [regex]::Escape('/// <deprecated/>'))
  Check 'BareDeprecatedOnly: NOT nonsensically wrapped in a fabricated <summary> (dispatch sniff genuinely fixed)' `
    ($null -eq $bareDepBlock -or (-not ($bareDepBlock -match '<summary>')))
  Check 'BareDeprecatedOnly: a real facts block was added (Called from: CallsBareDeprecatedOnly)' `
    ($bareDepBlock -match '<!-- drag-lint:auto BEGIN -->' -and $bareDepBlock -match 'Called from:.*CallsBareDeprecatedOnly')

  # --- Every emitted /// line is 7-bit ASCII ---
  $docLines1 = $lines1 | Where-Object { $_.TrimStart() -match '^///' }
  $nonAscii1 = $docLines1 | Where-Object { $_ -match '[^\x00-\x7F]' }
  Check 'every /// line is 7-bit ASCII (cycle 1)' ($nonAscii1.Count -eq 0)

  $afterApply1 = [IO.File]::ReadAllBytes($target)

  # --- cycle 2: reindex + re-apply all three -- the load-bearing 2-cycle proof ---
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 're-index exits 0' ($LASTEXITCODE -eq 0)

  $jAll2 = Apply-One 'preserve_tags.AllTags'
  Check 'AllTags apply #2: action=unchanged (stable fixed point)' ($jAll2 -match '"action":"unchanged"') $jAll2
  $jExc2 = Apply-One 'preserve_tags.ExceptionOnlyHasCaller'
  Check 'ExceptionOnlyHasCaller apply #2: action=unchanged (stable fixed point -- tags survive a SECOND cycle, not just the first)' `
    ($jExc2 -match '"action":"unchanged"') $jExc2
  $jNo2 = Apply-One 'preserve_tags.NoExoticTags'
  Check 'NoExoticTags apply #2: action=unchanged' ($jNo2 -match '"action":"unchanged"') $jNo2
  $jDep2 = Apply-One 'preserve_tags.BareDeprecatedOnly'
  Check 'BareDeprecatedOnly apply #2: action=unchanged (stable fixed point)' ($jDep2 -match '"action":"unchanged"') $jDep2

  $afterApply2 = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: whole file byte-identical after the 2nd apply cycle' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterApply1,[byte[]]$afterApply2))

  $lines2 = [IO.File]::ReadAllLines($target)
  $allTagsBlock2 = Get-DocBlockAbove $lines2 '^function AllTags\(AValue: Integer\): Integer;'
  Check 'AllTags: all five tags still present after a SECOND apply cycle' (
    ($allTagsBlock2 -match [regex]::Escape('<exception cref="EFoo">Raised when AValue is negative.</exception>')) -and
    ($allTagsBlock2 -match [regex]::Escape('<example>AllTags(21) returns 42.</example>')) -and
    ($allTagsBlock2 -match [regex]::Escape('<seealso cref="Other.RelatedThing"/>')) -and
    ($allTagsBlock2 -match [regex]::Escape('<since>1.2</since>')) -and
    ($allTagsBlock2 -match [regex]::Escape('<deprecated/>'))
  )
  $excBlock2 = Get-DocBlockAbove $lines2 '^procedure ExceptionOnlyHasCaller;'
  Check 'ExceptionOnlyHasCaller: <exception> still present after a SECOND apply cycle' `
    ($excBlock2 -match [regex]::Escape('<exception cref="EBar">Raised on bad input.</exception>'))
  $bareDepBlock2 = Get-DocBlockAbove $lines2 '^procedure BareDeprecatedOnly;'
  Check 'BareDeprecatedOnly: clean <deprecated/> still present, still unwrapped, after a SECOND apply cycle' `
    ($bareDepBlock2 -match [regex]::Escape('/// <deprecated/>') -and (-not ($bareDepBlock2 -match '<summary>')))

  # =====================================================================
  # PART 1, continued: strip round-trip
  # =====================================================================
  & $exePath document --unit $target --db $db --strip --apply 2>$null | Out-Null
  Check 'strip --apply exits 0' ($LASTEXITCODE -eq 0)

  $afterStrip = [IO.File]::ReadAllBytes($target)
  Check 'ROUND-TRIP: whole file byte-identical to the pre-apply fixture' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$afterStrip))

  $finalText = [IO.File]::ReadAllText($target)
  Check 'post-strip: AllTags'' hand-written tags all survive' (
    $finalText.Contains('/// <summary>Doubles AValue; hand-written summary must survive.</summary>') -and
    $finalText.Contains('/// <deprecated/>') -and
    $finalText.Contains('/// <param name="AValue">Hand-written param desc; must survive.</param>') -and
    $finalText.Contains('/// <returns>The doubled value.</returns>') -and
    $finalText.Contains('/// <exception cref="EFoo">Raised when AValue is negative.</exception>') -and
    $finalText.Contains('/// <example>AllTags(21) returns 42.</example>') -and
    $finalText.Contains('/// <seealso cref="Other.RelatedThing"/>') -and
    $finalText.Contains('/// <since>1.2</since>')
  )
  Check 'post-strip: ExceptionOnlyHasCaller''s <exception> survives' `
    ($finalText.Contains('/// <exception cref="EBar">Raised on bad input.</exception>'))
  Check 'post-strip: NoExoticTags'' <summary> survives' `
    ($finalText.Contains('/// <summary>Plain summary; no exotic tags here.</summary>'))
  $lines3 = [IO.File]::ReadAllLines($target)
  $bareDepBlock3 = Get-DocBlockAbove $lines3 '^procedure BareDeprecatedOnly;'
  Check 'post-strip: BareDeprecatedOnly''s clean, standalone <deprecated/> survives' `
    ($bareDepBlock3 -match [regex]::Escape('/// <deprecated/>') -and (-not ($bareDepBlock3 -match '<summary>')))
  Check 'post-strip: no drag-lint:auto marker survives anywhere' `
    (-not ($finalText -match 'drag-lint:auto'))

  & $exePath document --unit $target --db $db --strip --apply 2>$null | Out-Null
  Check 'second strip --apply exits 0' ($LASTEXITCODE -eq 0)
  $afterStrip2 = [IO.File]::ReadAllBytes($target)
  Check 'second strip --apply is a no-op (byte-identical)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterStrip,[byte[]]$afterStrip2))

  # =====================================================================
  # PART 2: Trap 1 -- hand-written vs auto-generated <since>/<seealso>
  # must not conflate (git-enabled scratch, --seealso --since opt-ins)
  # =====================================================================
  $scratch2 = Join-Path C:\TEMP 'draglint_docp3preservetags_seealsosince'
  if (Test-Path $scratch2) { Remove-Item $scratch2 -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch2 | Out-Null
  $target2 = Join-Path $scratch2 'preserve_tags.pas'
  $db2     = Join-Path $scratch2 'preservetags2.sqlite'
  Copy-Item $fixture $target2 -Force

  Push-Location $scratch2
  try {
    & git init -q 2>$null | Out-Null
    & git add preserve_tags.pas 2>$null | Out-Null
    & git -c user.name='drag-lint test' -c user.email='test@drag-lint.local' `
        -c commit.gpgsign=false commit -q -m 'fixture' `
        --date='2021-06-01T09:00:00' 2>$null | Out-Null
  } finally { Pop-Location }

  & $exePath index $scratch2 --db $db2 2>$null | Out-Null
  Check 'scratch2: index exits 0' ($LASTEXITCODE -eq 0)

  function Apply-DoA {
    return (& $exePath document --qname preserve_tags.TSeeAlsoHost.DoA --db $db2 --seealso --since --base-dir $scratch2 --apply --json 2>$null) -join "`n"
  }

  $jDoA1 = Apply-DoA
  Check 'DoA apply #1 (--seealso --since) exits 0' ($LASTEXITCODE -eq 0) $jDoA1

  $doaLines1 = [IO.File]::ReadAllLines($target2)
  $doaBlock1 = Get-DocBlockAbove $doaLines1 '^\s*procedure DoA;'
  Check 'DoA decl + doc-comment found (cycle 1)' ($null -ne $doaBlock1 -and $doaBlock1 -ne '')
  Check 'DoA: hand-written <since>1.0-hand</since> survives (cycle 1)' ($doaBlock1 -match [regex]::Escape('<since>1.0-hand</since>'))
  Check 'DoA: hand-written <seealso cref="Unrelated.HandWritten"/> survives (cycle 1)' `
    ($doaBlock1 -match [regex]::Escape('<seealso cref="Unrelated.HandWritten"/>'))
  Check 'DoA: auto <since> (git-derived, DIFFERENT from the hand value) present inside the fence (cycle 1)' `
    ($doaBlock1 -match [regex]::Escape('<since>2021-06-01</since>'))
  Check 'DoA: auto <seealso cref=...DoB"/> present inside the fence (cycle 1)' `
    ($doaBlock1 -match [regex]::Escape('<seealso cref="preserve_tags.TSeeAlsoHost.DoB"/>'))
  Check 'DoA: auto <seealso cref=...DoC"/> present inside the fence (cycle 1)' `
    ($doaBlock1 -match [regex]::Escape('<seealso cref="preserve_tags.TSeeAlsoHost.DoC"/>'))

  # Exactly-once counts, cycle 1 (baseline before the growth risk is even exercised).
  $handSinceCount1  = ([regex]::Matches($doaBlock1, [regex]::Escape('<since>1.0-hand</since>'))).Count
  $handSeeAlsoCount1 = ([regex]::Matches($doaBlock1, [regex]::Escape('<seealso cref="Unrelated.HandWritten"/>'))).Count
  Check 'DoA: hand-written <since> appears exactly once (cycle 1)' ($handSinceCount1 -eq 1)
  Check 'DoA: hand-written <seealso> appears exactly once (cycle 1)' ($handSeeAlsoCount1 -eq 1)

  $afterDoA1 = [IO.File]::ReadAllBytes($target2)

  & $exePath index $scratch2 --db $db2 2>$null | Out-Null
  Check 'scratch2: re-index exits 0' ($LASTEXITCODE -eq 0)

  $jDoA2 = Apply-DoA
  Check 'DoA apply #2 (--seealso --since) exits 0' ($LASTEXITCODE -eq 0) $jDoA2

  $afterDoA2 = [IO.File]::ReadAllBytes($target2)
  Check 'TRAP 1: whole file byte-identical after a SECOND --seealso --since apply (no growth/duplication)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterDoA1,[byte[]]$afterDoA2))

  $doaLines2 = [IO.File]::ReadAllLines($target2)
  $doaBlock2 = Get-DocBlockAbove $doaLines2 '^\s*procedure DoA;'
  $handSinceCount2   = ([regex]::Matches($doaBlock2, [regex]::Escape('<since>1.0-hand</since>'))).Count
  $handSeeAlsoCount2 = ([regex]::Matches($doaBlock2, [regex]::Escape('<seealso cref="Unrelated.HandWritten"/>'))).Count
  $autoSinceCount2   = ([regex]::Matches($doaBlock2, [regex]::Escape('<since>2021-06-01</since>'))).Count
  $autoSeeAlsoDoBCount2 = ([regex]::Matches($doaBlock2, [regex]::Escape('<seealso cref="preserve_tags.TSeeAlsoHost.DoB"/>'))).Count
  Check 'TRAP 1: hand-written <since> still appears exactly once (cycle 2, did not double)' ($handSinceCount2 -eq 1)
  Check 'TRAP 1: hand-written <seealso> still appears exactly once (cycle 2, did not double)' ($handSeeAlsoCount2 -eq 1)
  Check 'TRAP 1: auto <since> still appears exactly once (cycle 2, did not double)' ($autoSinceCount2 -eq 1)
  Check 'TRAP 1: auto <seealso cref=...DoB"/> still appears exactly once (cycle 2, did not double)' ($autoSeeAlsoDoBCount2 -eq 1)

  # =====================================================================
  # PART 3: coordinator review round 1 findings (Critical 1, Important 2/3)
  # Continues on scratch1/$target -- PART 1's strip round-trip already
  # proved the file is back to $before (pristine) bytes, so these NEW
  # symbols (never targeted by PART 1's --qname calls) are still untouched.
  # Reindex first: the strip operations above changed the file without
  # reindexing, so the DB's line numbers are stale relative to the
  # now-pristine file.
  # =====================================================================
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'PART 3: re-index exits 0' ($LASTEXITCODE -eq 0)

  # Review round 2: applies $QName three times (Apply-One reindexes before
  # each), asserting the full nested content survives verbatim after cycle 1
  # AND is still there, unmangled, with no standalone duplicate fabricated,
  # after cycles 2 and 3 -- the round-2 defect (nesting inside <exception>/
  # <example>/<deprecated>, not just <summary>) needed a 3rd cycle to show
  # unbounded growth for some shapes, so a 1- or 2-cycle check alone would
  # not have caught it (same reasoning as NestedTagsInSummary's own 3-cycle
  # check above).
  function Test-ThreeCycleNesting([string]$QName, [string]$DeclPattern, [string]$ExpectedLine, [string]$Label) {
    $j1 = Apply-One $QName
    Check "$Label apply #1 exits 0" ($LASTEXITCODE -eq 0) $j1
    $b1 = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) $DeclPattern
    Check "$Label`: full nested content survives verbatim, unmangled (cycle 1)" `
      ($b1 -match [regex]::Escape($ExpectedLine)) $b1
    $after1 = [IO.File]::ReadAllBytes($target)

    $j2 = Apply-One $QName
    $after2 = [IO.File]::ReadAllBytes($target)
    Check "$Label`: byte-identical after a 2nd apply cycle" `
      ([System.Linq.Enumerable]::SequenceEqual([byte[]]$after1,[byte[]]$after2)) $j2

    $j3 = Apply-One $QName
    $after3 = [IO.File]::ReadAllBytes($target)
    Check "$Label`: byte-identical after a 3rd apply cycle (unbounded growth needed 3+ cycles to surface for some nesting shapes)" `
      ([System.Linq.Enumerable]::SequenceEqual([byte[]]$after2,[byte[]]$after3)) $j3

    $b3 = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) $DeclPattern
    Check "$Label`: full nested content STILL survives verbatim, unmangled, after 3 cycles" `
      ($b3 -match [regex]::Escape($ExpectedLine)) $b3
  }

  # --- NestedTagsInSummary: Critical 1, THREE apply cycles ---
  $jNest1 = Apply-One 'preserve_tags.NestedTagsInSummary'
  Check 'NestedTagsInSummary apply #1 exits 0' ($LASTEXITCODE -eq 0) $jNest1

  $nestLines1 = [IO.File]::ReadAllLines($target)
  $nestBlock1 = Get-DocBlockAbove $nestLines1 '^procedure NestedTagsInSummary;'
  Check 'NestedTagsInSummary decl + doc-comment found (cycle 1)' ($null -ne $nestBlock1 -and $nestBlock1 -ne '')
  Check 'NestedTagsInSummary: <summary> line 1 (with its inline <see>) survives verbatim (cycle 1)' `
    ($nestBlock1 -match [regex]::Escape('<summary>Uses <see cref="Other.RelatedThing"/> for related lookups and'))
  Check 'NestedTagsInSummary: <summary> line 2 (with its inline <exception>) survives verbatim (cycle 1)' `
    ($nestBlock1 -match [regex]::Escape('can raise <exception cref="ENested">a nested, inline description</exception>'))
  Check 'CRITICAL 1: NO standalone <seealso> fabricated from the inline <see> (cycle 1)' `
    (-not ($nestBlock1 -match '<seealso'))
  $nestExcCount1 = ([regex]::Matches($nestBlock1, [regex]::Escape('<exception cref="ENested">'))).Count
  Check 'CRITICAL 1: <exception cref="ENested"> appears exactly once -- inside the summary only, no standalone duplicate (cycle 1)' `
    ($nestExcCount1 -eq 1)

  $afterNest1 = [IO.File]::ReadAllBytes($target)

  & $exePath index $scratch --db $db 2>$null | Out-Null
  $jNest2 = Apply-One 'preserve_tags.NestedTagsInSummary'
  Check 'NestedTagsInSummary apply #2 exits 0' ($LASTEXITCODE -eq 0) $jNest2
  $afterNest2 = [IO.File]::ReadAllBytes($target)
  Check 'CRITICAL 1: NestedTagsInSummary byte-identical after a 2nd apply cycle' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterNest1,[byte[]]$afterNest2))

  & $exePath index $scratch --db $db 2>$null | Out-Null
  $jNest3 = Apply-One 'preserve_tags.NestedTagsInSummary'
  Check 'NestedTagsInSummary apply #3 exits 0' ($LASTEXITCODE -eq 0) $jNest3
  $afterNest3 = [IO.File]::ReadAllBytes($target)
  Check 'CRITICAL 1: NestedTagsInSummary byte-identical after a 3rd apply cycle (growth -- not disappearance -- was the failure mode here, so idempotency across 3 cycles IS the regression test)' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterNest2,[byte[]]$afterNest3))

  $nestLines3 = [IO.File]::ReadAllLines($target)
  $nestBlock3 = Get-DocBlockAbove $nestLines3 '^procedure NestedTagsInSummary;'
  $nestExcCount3 = ([regex]::Matches($nestBlock3, [regex]::Escape('<exception cref="ENested">'))).Count
  Check 'CRITICAL 1: <exception cref="ENested"> STILL appears exactly once after 3 cycles (did not grow to 2 or 3)' ($nestExcCount3 -eq 1)
  Check 'CRITICAL 1: still no standalone <seealso> fabricated after 3 cycles' (-not ($nestBlock3 -match '<seealso'))

  # --- Review round 2: nesting inside <deprecated>/<exception>/<example> themselves (Critical 1 STILL-OPEN gap) ---
  Test-ThreeCycleNesting 'preserve_tags.NestedInDeprecated' '^procedure NestedInDeprecated;' `
    '<deprecated>Use <see cref="Other.RelatedThing"/> instead of this old thing.</deprecated>' `
    'CRITICAL 1 (round 2): <see> nested inside <deprecated>'

  Test-ThreeCycleNesting 'preserve_tags.NestedSinceInException' '^procedure NestedSinceInException;' `
    '<exception cref="EOuter">Added in <since>2.0</since> and still raised today.</exception>' `
    'CRITICAL 1 (round 2): <since> nested inside <exception>'

  Test-ThreeCycleNesting 'preserve_tags.NestedExceptionInExample' '^procedure NestedExceptionInExample;' `
    '<example>Sample usage. <exception cref="EInExample">boom</exception> can happen.</example>' `
    'CRITICAL 1 (round 2): <exception> nested inside <example>'

  # --- GappedDeprecatedMessage: Important 2 (message preserved) + gapped shape ---
  $jGap1 = Apply-One 'preserve_tags.GappedDeprecatedMessage'
  Check 'GappedDeprecatedMessage apply #1 exits 0' ($LASTEXITCODE -eq 0) $jGap1
  $gapLines1 = [IO.File]::ReadAllLines($target)
  $gapBlock1 = Get-DocBlockAbove $gapLines1 '^procedure GappedDeprecatedMessage;'
  Check 'GappedDeprecatedMessage decl + gapped doc-comment found' ($null -ne $gapBlock1 -and $gapBlock1 -ne '')
  Check 'IMPORTANT 2: <deprecated>message</deprecated> survives with its MESSAGE intact (not collapsed to a bare tag)' `
    ($gapBlock1 -match [regex]::Escape('<deprecated>Use Rev instead; this will be removed in 2.0.</deprecated>'))

  $afterGap1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $jGap2 = Apply-One 'preserve_tags.GappedDeprecatedMessage'
  Check 'GappedDeprecatedMessage apply #2: action=unchanged (stable fixed point)' ($jGap2 -match '"action":"unchanged"') $jGap2
  $afterGap2 = [IO.File]::ReadAllBytes($target)
  Check 'GappedDeprecatedMessage byte-identical after a 2nd apply cycle' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterGap1,[byte[]]$afterGap2))

  # --- BareSeeOnly: Critical 1, second symptom (<see> must not become <seealso>) ---
  # NOTE: cycle 1 alone does NOT exercise the fix -- BareSeeOnly's ONLY tag is
  # a bare <see> (SeeAlso is not in HasContent's OR-chain), so
  # ExistingHasAnyTag is False and apply #1 takes the FRESH/additive-insert
  # path (daCreated): the ORIGINAL <see> line is never touched, so asserting
  # against it here would be vacuous (true whether or not this fix exists).
  # The additive block lands adjacent to it (no blank line), so the NEXT
  # scan's MergeAdjacentSameKind merges them into one region -- apply #2 is
  # where the repair path (and this fix) is actually exercised; assertions
  # are made against ITS output.
  $jSee1 = Apply-One 'preserve_tags.BareSeeOnly'
  Check 'BareSeeOnly apply #1 exits 0' ($LASTEXITCODE -eq 0) $jSee1

  $afterSee1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $jSee2 = Apply-One 'preserve_tags.BareSeeOnly'
  Check 'BareSeeOnly apply #2: action=unchanged (stable fixed point -- WOULD be "extended" if <see> had been rewritten to <seealso>)' `
    ($jSee2 -match '"action":"unchanged"') $jSee2
  $afterSee2 = [IO.File]::ReadAllBytes($target)
  Check 'BareSeeOnly byte-identical after a 2nd apply cycle' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterSee1,[byte[]]$afterSee2))

  $seeLines2 = [IO.File]::ReadAllLines($target)
  $seeBlock2 = Get-DocBlockAbove $seeLines2 '^procedure BareSeeOnly;'
  Check 'BareSeeOnly decl + doc-comment found (cycle 2, repair path)' ($null -ne $seeBlock2 -and $seeBlock2 -ne '')
  Check 'CRITICAL 1 (2nd symptom): bare <see cref> round-trips as <see>, verbatim, once the repair path actually runs (cycle 2)' `
    ($seeBlock2 -match [regex]::Escape('<see cref="Other.RelatedThing"/>'))
  Check 'CRITICAL 1 (2nd symptom): <see> is NOT silently rewritten to <seealso> (cycle 2)' `
    (-not ($seeBlock2 -match '<seealso'))

  # --- Prose-control cases: Important 3 (Dispatch sniff must not over-match) ---
  $jProseSeeAlso = Apply-One 'preserve_tags.ProseMentionsSeeAlso'
  Check 'ProseMentionsSeeAlso apply #1 exits 0' ($LASTEXITCODE -eq 0) $jProseSeeAlso
  $proseSeeAlsoLines = [IO.File]::ReadAllLines($target)
  $proseSeeAlsoBlock = Get-DocBlockAbove $proseSeeAlsoLines '^procedure ProseMentionsSeeAlso;'
  Check 'IMPORTANT 3: "...mentions <seealso> without any cref..." survives UNTRUNCATED' `
    ($proseSeeAlsoBlock -match [regex]::Escape('Plain prose that mentions <seealso> without any cref, plus trailing words.')) $proseSeeAlsoBlock

  $jProseSeed = Apply-One 'preserve_tags.ProseMentionsSeed'
  Check 'ProseMentionsSeed apply #1 exits 0' ($LASTEXITCODE -eq 0) $jProseSeed
  $proseSeedLines = [IO.File]::ReadAllLines($target)
  $proseSeedBlock = Get-DocBlockAbove $proseSeedLines '^procedure ProseMentionsSeed;'
  Check 'IMPORTANT 3: "Grows the <seed> lookup table..." survives UNTRUNCATED' `
    ($proseSeedBlock -match [regex]::Escape('Grows the <seed> lookup table by one bucket.')) $proseSeedBlock

  $jProseDep = Apply-One 'preserve_tags.ProseMentionsDeprecatedSoon'
  Check 'ProseMentionsDeprecatedSoon apply #1 exits 0' ($LASTEXITCODE -eq 0) $jProseDep
  $proseDepLines = [IO.File]::ReadAllLines($target)
  $proseDepBlock = Get-DocBlockAbove $proseDepLines '^procedure ProseMentionsDeprecatedSoon;'
  Check 'IMPORTANT 3: "Marks the routine <deprecatedSoon>..." survives UNTRUNCATED' `
    ($proseDepBlock -match [regex]::Escape('Marks the routine <deprecatedSoon> but not really.')) $proseDepBlock

  # --- EmptyExampleSurvives: Minor 1 (a deliberate blank <example></example> slot survives) ---
  $jEmptyEx1 = Apply-One 'preserve_tags.EmptyExampleSurvives'
  Check 'EmptyExampleSurvives apply #1 exits 0' ($LASTEXITCODE -eq 0) $jEmptyEx1
  $emptyExLines1 = [IO.File]::ReadAllLines($target)
  $emptyExBlock1 = Get-DocBlockAbove $emptyExLines1 '^procedure EmptyExampleSurvives;'
  Check 'EmptyExampleSurvives decl + doc-comment found' ($null -ne $emptyExBlock1 -and $emptyExBlock1 -ne '')
  Check 'MINOR 1: deliberately empty <example></example> survives (not dropped)' `
    ($emptyExBlock1 -match [regex]::Escape('<example></example>')) $emptyExBlock1

  $afterEmptyEx1 = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $jEmptyEx2 = Apply-One 'preserve_tags.EmptyExampleSurvives'
  Check 'EmptyExampleSurvives apply #2: action=unchanged (stable fixed point)' ($jEmptyEx2 -match '"action":"unchanged"') $jEmptyEx2
  $afterEmptyEx2 = [IO.File]::ReadAllBytes($target)
  Check 'EmptyExampleSurvives byte-identical after a 2nd apply cycle' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$afterEmptyEx1,[byte[]]$afterEmptyEx2))

  # Every emitted /// line across PART 3 is 7-bit ASCII too.
  $linesPart3 = [IO.File]::ReadAllLines($target)
  $docLinesPart3 = $linesPart3 | Where-Object { $_.TrimStart() -match '^///' }
  $nonAsciiPart3 = $docLinesPart3 | Where-Object { $_ -match '[^\x00-\x7F]' }
  Check 'every /// line is 7-bit ASCII (PART 3)' ($nonAsciiPart3.Count -eq 0)

  # =====================================================================
  # PART 4: coordinator review round 2, NEW IMPORTANT (line-deletion on a
  # malformed-but-tag-shaped comment; see this file's own header comment).
  # Continues on scratch1/$target.
  # =====================================================================

  # $Survives1 is checked after cycle 1 (proves no IMMEDIATE full deletion).
  # $SurvivesFinal is checked after cycles 2 AND 3 -- most rows below settle
  # into their final form from cycle 1 already (so $Survives1 usually equals
  # $SurvivesFinal).
  #
  # v(ADP3 T3c): TabSeparatedSeeAlso used to be the one exception here, pre-
  # Task-3c -- its ONLY tag is a <seealso/>, whose presence alone did NOT
  # satisfy Document.pas' ExistingHasAnyTag before this task (same reasoning
  # as BareSeeOnly, PART 3, which is STILL pre-3c behaviour -- see its own
  # comment): cycle 1 took the fresh/additive path (original tab-bearing line
  # untouched), and only cycle 2 -- once MergeAdjacentSameKind folded the
  # additive facts block into the same region, which flipped HasContent True
  # via the pre-existing Remarks<>'' disjunct -- ran the repair path that
  # normalized the tab to a canonical single space. Task 3c widened HasContent
  # to include Length(SeeAlso) > 0 (DRagLint.Parser.DocComments.pas), so
  # ExistingHasAnyTag is now True from the ORIGINAL parse alone -- cycle 1
  # runs the repair path immediately (confirmed: cycle 1 now reports
  # "action":"extended", tab already normalized to a space, where it used to
  # report "action":"created" with the tab still present until cycle 2).
  # $Survives1's loose substring ('cref="Other.RelatedThing"', matching
  # either the tab or space form) still holds either way, so this assertion
  # needed no change -- only this comment did. Cycle 2/3 are now stable
  # no-op confirmations rather than the cycle that does the actual work; they
  # still prove the fixed point either way. This is the EXACT two-cycle
  # mechanism the line-deletion defect itself depended on -- now not merely
  # "exercised and proven safe" but not exercised as a two-cycle path AT ALL
  # for this decl, since a genuinely one-cycle repair is safer still.
  function Test-NeverDeletedAcrossCycles([string]$QName, [string]$DeclPattern, [string]$Survives1, [string]$SurvivesFinal, [string]$Label) {
    $j1 = Apply-One $QName
    Check "$Label apply #1 exits 0" ($LASTEXITCODE -eq 0) $j1
    $b1 = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) $DeclPattern
    Check "$Label`: decl + doc-comment found (cycle 1, not fully deleted)" ($null -ne $b1 -and $b1 -ne '') $b1
    Check "$Label`: expected content survives (cycle 1)" ($b1 -match [regex]::Escape($Survives1)) $b1

    & $exePath index $scratch --db $db 2>$null | Out-Null
    $j2 = Apply-One $QName
    Check "$Label apply #2 exits 0" ($LASTEXITCODE -eq 0) $j2
    $b2 = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) $DeclPattern
    Check "$Label`: decl + doc-comment found (cycle 2 -- the additive-then-merge mechanism the defect itself relied on)" `
      ($null -ne $b2 -and $b2 -ne '') $b2
    Check "$Label`: final/canonical content present (cycle 2)" ($b2 -match [regex]::Escape($SurvivesFinal)) $b2
    $after2 = [IO.File]::ReadAllBytes($target)

    & $exePath index $scratch --db $db 2>$null | Out-Null
    $j3 = Apply-One $QName
    $after3 = [IO.File]::ReadAllBytes($target)
    Check "$Label`: byte-identical after a 3rd apply cycle (stable fixed point)" `
      ([System.Linq.Enumerable]::SequenceEqual([byte[]]$after2,[byte[]]$after3)) $j3
    $b3 = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) $DeclPattern
    Check "$Label`: final/canonical content STILL present after 3 cycles" `
      ($b3 -match [regex]::Escape($SurvivesFinal)) $b3
  }

  Test-NeverDeletedAcrossCycles 'preserve_tags.SpaceBeforeCloseDeprecated' '^procedure SpaceBeforeCloseDeprecated;' `
    '<summary><deprecated >Space before the closing angle bracket.</deprecated></summary>' `
    '<summary><deprecated >Space before the closing angle bracket.</deprecated></summary>' `
    'NEW IMPORTANT: space before deprecated''s closing >'

  Test-NeverDeletedAcrossCycles 'preserve_tags.UnclosedDeprecated' '^procedure UnclosedDeprecated;' `
    '<summary><deprecated>No closing tag at all, just trailing words</summary>' `
    '<summary><deprecated>No closing tag at all, just trailing words</summary>' `
    'NEW IMPORTANT: unclosed <deprecated>'

  Test-NeverDeletedAcrossCycles 'preserve_tags.AllCapsDeprecatedTag' '^procedure AllCapsDeprecatedTag;' `
    '<deprecated>Recognized case-insensitively.</deprecated>' `
    '<deprecated>Recognized case-insensitively.</deprecated>' `
    'NEW IMPORTANT: <DEPRECATED> all-caps (case-insensitive sniff)'
  $allCapsBlock = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) '^procedure AllCapsDeprecatedTag;'
  Check 'NEW IMPORTANT: <DEPRECATED> genuinely recognized, NOT wrapped in a fabricated <summary>' `
    (-not ($allCapsBlock -match '<summary>')) $allCapsBlock

  Test-NeverDeletedAcrossCycles 'preserve_tags.ExceptionNoCrefAttr' '^procedure ExceptionNoCrefAttr;' `
    '<summary><exception>Missing the required cref attribute.</exception></summary>' `
    '<summary><exception>Missing the required cref attribute.</exception></summary>' `
    'NEW IMPORTANT: <exception> with no cref attribute'

  Test-NeverDeletedAcrossCycles 'preserve_tags.SeeAlsoNoCrefWithSummary' '^procedure SeeAlsoNoCrefWithSummary;' `
    '<summary>Has a real, well-formed summary.</summary>' `
    '<summary>Has a real, well-formed summary.</summary>' `
    'NEW IMPORTANT: <seealso> with no cref, alongside a real <summary>'
  $seeNoCrefBlock = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) '^procedure SeeAlsoNoCrefWithSummary;'
  Check 'NEW IMPORTANT: whole comment NOT reduced to just a facts block (the real <summary> is genuinely there)' `
    ($seeNoCrefBlock -match '<!-- drag-lint:auto BEGIN -->' -and $seeNoCrefBlock -match '<summary>') $seeNoCrefBlock
  # v(ADP3 T3f): FLIPPED. This used to pin the ACCEPTED limitation that the
  # malformed seealso fragment is captured by nothing (RxSee requires cref=
  # too) and therefore did not round-trip -- the same "unmodeled tag" loss
  # class (L1) run_doc_p3_valuetag_caller.ps1 pinned for <value>. Task 3f's
  # verbatim residual-line carry-through closes it: nothing on that line is
  # accounted for by the emitter, so the WHOLE line is handed back untouched.
  Check 'v(ADP3 T3f): the malformed seealso fragment now round-trips VERBATIM (was a pinned "unmodeled tag" gap before Task 3f)' `
    ($seeNoCrefBlock -match [regex]::Escape('/// <seealso>Missing the required cref, sitting alongside a real tag.</seealso>')) $seeNoCrefBlock
  Check 'v(ADP3 T3f): ...and exactly once (carried through, never duplicated)' `
    ((([regex]::Matches($seeNoCrefBlock, [regex]::Escape('Missing the required cref, sitting alongside'))).Count) -eq 1) $seeNoCrefBlock

  Test-NeverDeletedAcrossCycles 'preserve_tags.UnclosedExampleTag' '^procedure UnclosedExampleTag;' `
    '<summary><example>Unclosed example body, no closing tag</summary>' `
    '<summary><example>Unclosed example body, no closing tag</summary>' `
    'NEW IMPORTANT: unclosed <example>'

  Test-NeverDeletedAcrossCycles 'preserve_tags.TabSeparatedSeeAlso' '^procedure TabSeparatedSeeAlso;' `
    'cref="Other.RelatedThing"' `
    '<seealso cref="Other.RelatedThing"/>' `
    'NEW IMPORTANT: TAB before <seealso>''s cref (case-insensitive/whitespace-tolerant sniff)'
  $tabSeeBlock = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) '^procedure TabSeparatedSeeAlso;'
  # CollapseWhitespace ('[ \t]+' -> ' ') fires on EITHER path (a genuinely
  # recognized <seealso>'s cref, or ParseOneline's literal-prose fallback),
  # so the space-normalized substring check above alone cannot tell "sniff
  # genuinely recognized this as a tag" apart from "sniff missed it, prose
  # fallback coincidentally collapsed to the same-looking text" -- this
  # extra check is the one that actually distinguishes them (empirically
  # confirmed: reverting layer 1 to the old Pos()-based sniff during this
  # task's own revert-to-RED verification left the substring check above
  # GREEN by accident, and only this assertion caught the regression).
  Check 'NEW IMPORTANT: tab-separated <seealso> genuinely recognized, NOT wrapped in a fabricated <summary>' `
    (-not ($tabSeeBlock -match '<summary>')) $tabSeeBlock

  # Every emitted /// line across PART 4 is 7-bit ASCII too.
  $linesPart4 = [IO.File]::ReadAllLines($target)
  $docLinesPart4 = $linesPart4 | Where-Object { $_.TrimStart() -match '^///' }
  $nonAsciiPart4 = $docLinesPart4 | Where-Object { $_ -match '[^\x00-\x7F]' }
  Check 'every /// line is 7-bit ASCII (PART 4)' ($nonAsciiPart4.Count -eq 0)

  # =====================================================================
  # PART 5: coordinator review round 3 (NEW IMPORTANT <since>; STRUCTURAL 1
  # summary/param/returns/remarks). Continues on scratch1/$target.
  # =====================================================================

  # --- NEW IMPORTANT: <since> reads presence from a stripped view, content
  # from AExisting -- all three reproductions are stable from cycle 1
  # (Test-ThreeCycleNesting's own cycle-1-vs-cycle-2 byte-identical check
  # passes for all three either way -- see its own comment for why that
  # holds regardless of which cycle does the work). SinceWithNestedException/
  # SinceWithNestedDeprecated each independently force the repair path
  # immediately even before Task 3c: the nested tag makes Exceptions.
  # Length>0/Deprecated true, both already part of Document.pas'
  # ExistingHasAnyTag via HasContent pre-3c.
  #
  # v(ADP3 T3c): SinceWithNestedExample used NOT to belong in that "forces
  # repair immediately" group -- HasExampleTag (from the nested <example>)
  # was NOT part of HasContent pre-3c, so cycle 1 took the FRESH/additive
  # path (confirmed: cycle 1 reported "action":"created", the original
  # <since> line left untouched, a facts remarks block inserted beside it);
  # it converged to the same-looking content by cycle 2 only because that
  # cycle's repair-path output happened to be BYTE-IDENTICAL to what cycle 1
  # already wrote (no whitespace irregularity to normalize, unlike
  # TabSeparatedSeeAlso's tab), so the JSON read "unchanged"/0 edits even
  # though a repair computation genuinely ran -- same TWO-STEP mechanism as
  # TabSeparatedSeeAlso's OWN pre-3c behaviour (documented in PART 4 above),
  # not an exception to it. Task 3c widened HasContent to include
  # HasExampleTag, so SinceWithNestedExample NOW also forces the repair path
  # immediately from cycle 1 (confirmed: cycle 1 now reports "action":
  # "extended") -- it no longer differs from TabSeparatedSeeAlso in this
  # respect; both converge in one cycle now, not two.
  Test-ThreeCycleNesting 'preserve_tags.SinceWithNestedException' '^procedure SinceWithNestedException;' `
    '<since>1.0 <exception cref="EInSince">x</exception></since>' `
    'NEW IMPORTANT (round 3): <exception> nested inside <since>'

  Test-ThreeCycleNesting 'preserve_tags.SinceWithNestedExample' '^procedure SinceWithNestedExample;' `
    '<since>2.0 <example>see the sample below</example> onwards</since>' `
    'NEW IMPORTANT (round 3): <example> nested inside <since>'

  # The worst shape in the whole task: BOTH tags' own self-exclusion erased
  # the OTHER, so both failed their presence gate and the ENTIRE comment was
  # deleted, pre-fix. This is the load-bearing case for the fix.
  Test-ThreeCycleNesting 'preserve_tags.SinceWithNestedDeprecated' '^procedure SinceWithNestedDeprecated;' `
    '<since><deprecated>2.0-beta</deprecated></since>' `
    'NEW IMPORTANT (round 3): <deprecated> nested inside <since> (previously deleted the WHOLE comment)'

  # --- STRUCTURAL 1: summary/param now also read presence from a Standalone
  # view -- stable from cycle 1, PLUS an explicit "no standalone sibling
  # fabricated" check (the actual reported defect), which Test-
  # ThreeCycleNesting's own substring check alone would not catch (a
  # fabricated duplicate does not remove the original -- both would be
  # present, and the substring check only confirms the original survives).
  Test-ThreeCycleNesting 'preserve_tags.ExceptionWithNestedSummary' '^procedure ExceptionWithNestedSummary;' `
    '<exception cref="E1">exc text <summary>nested summary</summary> tail</exception>' `
    'STRUCTURAL 1 (round 3): <summary> nested inside <exception>'
  $excNestSummaryBlock = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) '^procedure ExceptionWithNestedSummary;'
  $summaryTagCount = ([regex]::Matches($excNestSummaryBlock, '<summary>')).Count
  Check 'STRUCTURAL 1: no standalone <summary> fabricated from the nested one (exactly one <summary> substring, inside the exception)' `
    ($summaryTagCount -eq 1) $excNestSummaryBlock

  Test-ThreeCycleNesting 'preserve_tags.ExampleWithNestedParam' '^procedure ExampleWithNestedParam\(AV: Integer\);' `
    '<example>Ex <param name="AV">nested param desc</param> body.</example>' `
    'STRUCTURAL 1 (round 3): <param> nested inside <example>'
  $exampleNestParamBlock = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) '^procedure ExampleWithNestedParam\(AV: Integer\);'
  $paramTagCount = ([regex]::Matches($exampleNestParamBlock, '<param name="AV">')).Count
  Check 'STRUCTURAL 1: no standalone <param name="AV"> fabricated from the nested one (exactly one substring, inside the example)' `
    ($paramTagCount -eq 1) $exampleNestParamBlock

  # --- STRUCTURAL 1, formerly a DISCLOSED RESIDUAL: DeprecatedWithNestedReturns
  # / ExampleWithNestedRemarks. PINS FLIPPED by v(ADP3 T3h).
  #
  # These two used to assert CYCLE-1 correctness ONLY, deliberately: T3b fixed
  # the fabrication on the first apply, but from cycle 2 on the unkeyed singular
  # CONTENT read still picked the wrong occurrence once MergeAdjacentSameKind
  # folded the engine's own freshly-inserted tag into the same region as the
  # nested look-alike (register N2). That gap was left visible in the suite
  # rather than silent -- and this is what "visible" was for: T3h closed it, so
  # both rows now go through Test-ThreeCycleNesting like every other nesting row
  # here, and each is additionally strip-round-tripped back to its pristine block.
  #
  # The cycle-1-only pins are NOT merely upgraded to 3 cycles: the "exactly once"
  # counts below are what actually caught the defect (a fabricated duplicate does
  # not remove the original, so a substring check alone passes either way), and
  # the strip round-trip is what made it matter (the fabricated tag carried no
  # marker, so `document --strip` could never remove it).
  Test-ThreeCycleNesting 'preserve_tags.DeprecatedWithNestedReturns' '^function DeprecatedWithNestedReturns: Integer;' `
    '<deprecated>dep <returns>nested returns text</returns> tail</deprecated>' `
    'STRUCTURAL 1 (round 3) / N2 (T3h): <returns> nested inside <deprecated>'
  $depRetBlock1 = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) '^function DeprecatedWithNestedReturns: Integer;'
  Check 'N2 (T3h): "nested returns text" appears exactly ONCE after 3 cycles -- never lifted out as a standalone sibling' `
    (([regex]::Matches($depRetBlock1, [regex]::Escape('nested returns text'))).Count -eq 1) $depRetBlock1
  Check 'N2 (T3h): the standalone <returns> is the ENGINE''s, marked and refilled from the mined case' `
    ($depRetBlock1 -match [regex]::Escape('<returns><!-- drag-lint:auto -->Observed: 1.</returns>')) $depRetBlock1

  Test-ThreeCycleNesting 'preserve_tags.ExampleWithNestedRemarks' '^procedure ExampleWithNestedRemarks;' `
    '<example>ex <remarks>nested remarks</remarks> tail</example>' `
    'STRUCTURAL 1 (round 3) / N2 (T3h): <remarks> nested inside <example>'
  $exRemBlock1 = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) '^procedure ExampleWithNestedRemarks;'
  Check 'N2 (T3h): "nested remarks" appears exactly ONCE after 3 cycles -- never duplicated into the engine''s own remarks prose' `
    (([regex]::Matches($exRemBlock1, [regex]::Escape('nested remarks'))).Count -eq 1) $exRemBlock1
  Check 'N2 (T3h): the engine''s <remarks> opens straight onto the fence (no author prose adopted)' `
    ($exRemBlock1 -match '(?m)^///\s*<remarks>\r?\n///\s*<!-- drag-lint:auto BEGIN -->') $exRemBlock1

  # --- N2 (T3h): and the round-trip, which is the point. The residue these two
  # used to accumulate was UNMARKED, so `document --strip` could not remove it and
  # the file kept a <returns>/<remarks> the author never wrote, permanently. Each
  # block must now come back to exactly what the fixture holds.
  $pristineFixtureLines = [IO.File]::ReadAllLines($fixture)
  foreach ($rt in @(
      @{ q = 'preserve_tags.DeprecatedWithNestedReturns'; p = '^function DeprecatedWithNestedReturns: Integer;' },
      @{ q = 'preserve_tags.ExampleWithNestedRemarks'   ; p = '^procedure ExampleWithNestedRemarks;'           })) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    & $exePath document --qname $rt.q --db $db --strip --apply 2>$null | Out-Null
    Check "N2 (T3h) ROUND-TRIP: $($rt.q) --strip exits 0" ($LASTEXITCODE -eq 0)
    $rtNow      = Get-DocBlockAbove ([IO.File]::ReadAllLines($target)) $rt.p
    $rtPristine = Get-DocBlockAbove $pristineFixtureLines               $rt.p
    Check "N2 (T3h) ROUND-TRIP: $($rt.q) returns to EXACTLY the author's own block" `
      ($rtNow -ceq $rtPristine) ("pristine=[$rtPristine] now=[$rtNow]")
  }

  # Every emitted /// line across PART 5 is 7-bit ASCII too.
  $linesPart5 = [IO.File]::ReadAllLines($target)
  $docLinesPart5 = $linesPart5 | Where-Object { $_.TrimStart() -match '^///' }
  $nonAsciiPart5 = $docLinesPart5 | Where-Object { $_ -match '[^\x00-\x7F]' }
  Check 'every /// line is 7-bit ASCII (PART 5)' ($nonAsciiPart5.Count -eq 0)
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
