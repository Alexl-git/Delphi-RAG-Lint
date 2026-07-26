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
# comment elsewhere in the file.
function Get-DocBlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return $null }
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
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
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
