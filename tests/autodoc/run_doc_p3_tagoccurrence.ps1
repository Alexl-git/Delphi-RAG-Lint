<#
  run_doc_p3_tagoccurrence.ps1 -- Auto-Document Phase 3, Task 3h: which
  OCCURRENCE of a singular-match tag the engine reads, and what happens to the
  occurrences it has no slot for.

  Fixture: fixtures\docp3\tagoccurrence.pas -- see its own header for why each
  shape is shaped the way it is.

  ROOT CAUSE (register N2 + D11). TDocCommentParser.ParseXmlDoc reads
  <summary>/<returns>/<remarks>/<example>/<deprecated>/<since> with a SINGULAR
  .Match, so TParsedDoc holds exactly one body per tag: the textually first
  occurrence in the region, nested or not. Two symptoms follow:

    (a) WRONG OCCURRENCE (N2). MergeComment takes PRESENCE from a filtered view
        (BuildStandaloneFor, which removes nested look-alikes) but CONTENT from
        the unfiltered singular field, so presence can describe one occurrence
        while content describes a different one. The nested look-alike's text is
        then emitted at the genuine standalone tag's slot -- UNMARKED, so
        `document --strip` cannot remove it, which is a broken round-trip.
        NestedReturnsInDeprecated / NestedRemarksInExample.

    (b) SURPLUS OCCURRENCE (D11 and its siblings). Occurrences past the first
        are silently DELETED: T3f's residual mask accounts for every match of a
        container pattern while the parse represents only one, so the second is
        accounted (hence not carried through verbatim) and then never emitted.
        TwoSinceTags / TwoSummaryTags / TwoReturnsTags.

  THE FIX, as this file measures it:
    * content for the unkeyed singular tags comes from the FIRST GENUINELY
      STANDALONE occurrence, located through a LENGTH-PRESERVING mask of the
      other containers and read back out of the ORIGINAL text at that
      occurrence's own offsets (so anything legitimately nested inside it
      survives verbatim -- that is what control F guards);
    * a SURPLUS occurrence of a singular-match container is no longer accounted,
      so T3f's own carry-through hands its line back verbatim.

  Both directions of getting it wrong are guarded by controls, not left to
  inspection: F (NestedTagsInSummary) fails if content is read from the STRIPPED
  view (the nested <exception> would be mangled out of the summary's own prose);
  G (PrefixProseEmptySummary) fails if an empty located body blanks the summary
  instead of deferring to ParseXmlDoc's untagged-prefix fallback; H
  (PlainDocumented) fails if the ordinary, non-exotic shape churns at all.

  ACCEPTANCE CRITERION for this task is the STRIP ROUND-TRIP at 3 cycles, not
  cycle-1 correctness -- cycle-1 correctness is exactly what the T3b pins
  already covered and exactly what hid symptom (a). Every shape therefore
  applies 3 times (reindex between each) and is then stripped and compared to
  its own pristine block, byte for byte.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\tagoccurrence.pas')).Path

$scratchRoot = Join-Path C:\TEMP 'draglint_docp3tagocc'
if (Test-Path $scratchRoot) { Remove-Item $scratchRoot -Recurse -Force }
$scratch = Join-Path $scratchRoot 'src'
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'tagoccurrence.pas'
$db     = Join-Path $scratchRoot 'q.sqlite'
Copy-Item $fixture $target -Force

# The contiguous run of ///-prefixed lines immediately above the FIRST line
# matching $declPattern, RAW (never trimmed), joined with LF. $null when the
# decl is not found OR has no doc lines above it at all -- an EMPTY array is
# neither, and returning one would let a "block located" check pass for a block
# that had been deleted outright. Same idiom as run_doc_p3_guards.ps1.
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
function Count-Of([string]$hay, [string]$needle) {
  if ($null -eq $hay) { return -1 }
  return ([regex]::Matches($hay, [regex]::Escape($needle))).Count
}
function Get-Md5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash.Substring(0,8) }

# decl patterns, one per fixture shape
$pat = [ordered]@{
  NestedReturnsInDeprecated = '^function NestedReturnsInDeprecated: Integer;'
  NestedRemarksInExample    = '^procedure NestedRemarksInExample;'
  TwoSinceTags              = '^procedure TwoSinceTags;'
  TwoSummaryTags            = '^procedure TwoSummaryTags;'
  TwoReturnsTags            = '^function TwoReturnsTags: Integer;'
  TwoSinceAndTwoSummary     = '^procedure TwoSinceAndTwoSummary;'
  TwoRemarksNoFacts         = '^procedure TwoRemarksNoFacts;'
  TwoRemarksWithFacts       = '^procedure TwoRemarksWithFacts;'
  NestedTagsInSummary       = '^procedure NestedTagsInSummary;'
  PrefixProseEmptySummary   = '^procedure PrefixProseEmptySummary;'
  PrefixProseBlankSummaryExotic = '^procedure PrefixProseBlankSummaryExotic;'
  PlainDocumented           = '^function PlainDocumented\(AValue: Integer\): Integer;'
}

Push-Location C:\TEMP
try {
  $pristineLines = [IO.File]::ReadAllLines($target)
  $pristine = @{}
  foreach ($k in $pat.Keys) { $pristine[$k] = Get-DocBlock $pristineLines $pat[$k] }

  # --- FIXTURE DISCRIMINATION ---------------------------------------------
  # Every shape must still HAVE the property that makes its assertion decide
  # something. A fixture tidy-up must break these loudly rather than silently
  # reduce an assertion to a tautology.
  Check 'FIXTURE: all 12 doc blocks were located' `
    ((@($pat.Keys | Where-Object { $null -eq $pristine[$_] })).Count -eq 0) `
    ("missing=" + (($pat.Keys | Where-Object { $null -eq $pristine[$_] }) -join ','))
  Check 'FIXTURE (a): the <returns> really is NESTED inside <deprecated> (one line, one span)' `
    ($pristine.NestedReturnsInDeprecated -match [regex]::Escape('<deprecated>dep <returns>nested returns text</returns> tail</deprecated>'))
  Check 'FIXTURE (a): the <remarks> really is NESTED inside <example>' `
    ($pristine.NestedRemarksInExample -match [regex]::Escape('<example>ex <remarks>nested remarks</remarks> tail</example>'))
  Check 'FIXTURE (b): TwoSinceTags really carries TWO standalone <since> tags' `
    ((Count-Of $pristine.TwoSinceTags '<since>') -eq 2)
  Check 'FIXTURE (b): TwoSummaryTags really carries TWO standalone <summary> tags' `
    ((Count-Of $pristine.TwoSummaryTags '<summary>') -eq 2)
  Check 'FIXTURE (b): TwoReturnsTags really carries TWO standalone <returns> tags' `
    ((Count-Of $pristine.TwoReturnsTags '<returns>') -eq 2)
  Check 'FIXTURE (b): TwoSinceAndTwoSummary really carries a surplus of TWO DIFFERENT tags' `
    (((Count-Of $pristine.TwoSinceAndTwoSummary '<since>') -eq 2) -and
     ((Count-Of $pristine.TwoSinceAndTwoSummary '<summary>') -eq 2))
  Check 'FIXTURE (b): both TwoRemarks shapes really carry TWO standalone <remarks> tags' `
    (((Count-Of $pristine.TwoRemarksNoFacts '<remarks>') -eq 2) -and
     ((Count-Of $pristine.TwoRemarksWithFacts '<remarks>') -eq 2))
  Check 'FIXTURE F: the control summary really has a tag nested INSIDE its own prose' `
    ($pristine.NestedTagsInSummary -match [regex]::Escape('<summary>Body with an inline <exception cref="EIn">inline desc</exception> tail.</summary>'))
  Check 'FIXTURE G: the control really has prose on its own line and an EMPTY <summary>' `
    ($pristine.PrefixProseEmptySummary -match [regex]::Escape('/// Leading prose the fallback adopts.') -and
     $pristine.PrefixProseEmptySummary -match [regex]::Escape('<summary></summary>'))

  # --- three whole-unit apply cycles --------------------------------------
  $fileMd5 = @()
  $blocks  = @()   # $blocks[cycle-1][shape]
  $applyJson = @()
  for ($cycle = 1; $cycle -le 3; $cycle++) {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    Check "cycle $cycle : index exits 0" ($LASTEXITCODE -eq 0)
    # v(ADP3 T3k, Group 2b item 6): the --json payload used to be piped straight
    # to Out-Null. Exit codes were checked and the bytes asserted byte-exactly,
    # so practical coverage was strong -- but an `edits` regression across the
    # three cycles was structurally UNOBSERVABLE here: a build that made cycle 2
    # rewrite the file with the identical bytes would report the same md5 and
    # the same exit code while doing work it must not do. Captured and asserted
    # below, the same treatment the other runners in this suite got.
    $j = (& $exePath document --unit $target --db $db --apply --json 2>$null) -join "`n"
    Check "cycle $cycle : document --unit --apply exits 0" ($LASTEXITCODE -eq 0)
    $applyJson += $j
    Check "cycle $cycle : --json payload is non-empty and carries an edits count" `
      ($j -match '"edits"\s*:\s*\d+') $j
    $fileMd5 += (Get-Md5 $target)
    $ls = [IO.File]::ReadAllLines($target)
    $snap = @{}
    foreach ($k in $pat.Keys) { $snap[$k] = Get-DocBlock $ls $pat[$k] }
    $blocks += $snap
  }
  Write-Host ("  whole-file md5 by cycle: c1={0} c2={1} c3={2}" -f $fileMd5[0], $fileMd5[1], $fileMd5[2])

  # THE binding criterion for the branch: a SECOND apply is a zero-byte diff.
  # Pre-fix this failed at c1 != c2 -- symptom (a) needs the second cycle to
  # surface, which is why a cycle-1-only pin could not see it.
  Check 'IDEMPOTENT: whole-file md5 is a fixed point from cycle 1 (c1 == c2 == c3)' `
    (($fileMd5[0] -eq $fileMd5[1]) -and ($fileMd5[1] -eq $fileMd5[2])) `
    ("md5=" + ($fileMd5 -join ' '))
  # v(ADP3 T3k, Group 2b item 6): the md5 fixed point says the RESULT stopped
  # changing; this says the engine stopped WORKING. They are different claims --
  # a rewrite that reproduces the identical bytes satisfies the first and not the
  # second -- and only the second would catch an edit path that re-emits on every
  # run. Cycles 2 and 3 must report zero edits.
  Check 'IDEMPOTENT: cycle 2 reports ZERO edits (not merely identical bytes)' `
    ($applyJson[1] -match '"edits"\s*:\s*0\b') $applyJson[1]
  Check 'IDEMPOTENT: cycle 3 reports ZERO edits' `
    ($applyJson[2] -match '"edits"\s*:\s*0\b') $applyJson[2]
  foreach ($k in $pat.Keys) {
    Check "IDEMPOTENT: $k block is byte-identical across all 3 cycles" `
      (($blocks[0][$k] -ceq $blocks[1][$k]) -and ($blocks[1][$k] -ceq $blocks[2][$k])) `
      ("c1=[" + $blocks[0][$k] + "] c2=[" + $blocks[1][$k] + "]")
  }

  $after = $blocks[2]

  # =====================================================================
  # A -- NestedReturnsInDeprecated: the nested <returns> is NOT this
  # symbol's own returns tag, and its text must never be lifted out of the
  # <deprecated> into a standalone slot.
  # =====================================================================
  Check 'A1: the nested <returns> survives verbatim inside <deprecated>' `
    ($after.NestedReturnsInDeprecated -match [regex]::Escape('<deprecated>dep <returns>nested returns text</returns> tail</deprecated>')) `
    $after.NestedReturnsInDeprecated
  Check 'A2: "nested returns text" appears EXACTLY ONCE -- never lifted out as a standalone sibling' `
    ((Count-Of $after.NestedReturnsInDeprecated 'nested returns text') -eq 1) `
    $after.NestedReturnsInDeprecated
  Check 'A3: the standalone <returns> is the ENGINE''s, marked, refilled from the mined case' `
    ($after.NestedReturnsInDeprecated -match [regex]::Escape('<returns><!-- drag-lint:auto -->Observed: 1.</returns>')) `
    $after.NestedReturnsInDeprecated
  # The mined case goes into the TAG (engine-owned <returns>), never ALSO into
  # a managed 'Returns:' fact line -- "never both" is MergeComment's own rule,
  # and pre-fix the wrong-occurrence read made ReturnsHandWritten True, which
  # produced BOTH.
  Check 'A4: no ''Returns:'' fact line beside the marked tag (IncludeReturns is False for an engine-owned returns)' `
    ((Count-Of $after.NestedReturnsInDeprecated 'Returns: 1') -eq 0) `
    $after.NestedReturnsInDeprecated

  # =====================================================================
  # B -- NestedRemarksInExample: the nested <remarks> is not this symbol's
  # remarks prose, so the facts fence must not attach to its text.
  # =====================================================================
  Check 'B1: the nested <remarks> survives verbatim inside <example>' `
    ($after.NestedRemarksInExample -match [regex]::Escape('<example>ex <remarks>nested remarks</remarks> tail</example>')) `
    $after.NestedRemarksInExample
  Check 'B2: "nested remarks" appears EXACTLY ONCE -- never duplicated into the engine''s own remarks prose' `
    ((Count-Of $after.NestedRemarksInExample 'nested remarks') -eq 1) `
    $after.NestedRemarksInExample
  Check 'B3: the engine''s <remarks> opens straight onto the fence (no author prose line adopted)' `
    ($after.NestedRemarksInExample -match '(?m)^///\s*<remarks>\r?\n///\s*<!-- drag-lint:auto BEGIN -->') `
    $after.NestedRemarksInExample

  # =====================================================================
  # C/D/E -- SURPLUS occurrences: the engine has one slot, the author wrote
  # two. The second must come back verbatim (T3f carry-through), never be
  # deleted.
  # =====================================================================
  Check 'C1: BOTH <since> tags survive (register D11)' `
    (($after.TwoSinceTags -match [regex]::Escape('<since>1.0</since>')) -and
     ($after.TwoSinceTags -match [regex]::Escape('<since>2.0</since>'))) `
    $after.TwoSinceTags
  Check 'C2: each <since> appears exactly once -- carried through, not duplicated' `
    (((Count-Of $after.TwoSinceTags '<since>1.0</since>') -eq 1) -and
     ((Count-Of $after.TwoSinceTags '<since>2.0</since>') -eq 1)) `
    $after.TwoSinceTags

  Check 'D1: BOTH <summary> tags survive (same class as D11, different tag)' `
    (($after.TwoSummaryTags -match [regex]::Escape('<summary>First summary.</summary>')) -and
     ($after.TwoSummaryTags -match [regex]::Escape('<summary>Second summary the author also wrote.</summary>'))) `
    $after.TwoSummaryTags
  Check 'D2: each <summary> appears exactly once' `
    (((Count-Of $after.TwoSummaryTags '<summary>First summary.</summary>') -eq 1) -and
     ((Count-Of $after.TwoSummaryTags '<summary>Second summary the author also wrote.</summary>') -eq 1)) `
    $after.TwoSummaryTags

  Check 'E1: BOTH <returns> tags survive' `
    (($after.TwoReturnsTags -match [regex]::Escape('<returns>First returns.</returns>')) -and
     ($after.TwoReturnsTags -match [regex]::Escape('<returns>Second returns the author also wrote.</returns>'))) `
    $after.TwoReturnsTags
  Check 'E2: each <returns> appears exactly once' `
    (((Count-Of $after.TwoReturnsTags '<returns>First returns.</returns>') -eq 1) -and
     ((Count-Of $after.TwoReturnsTags '<returns>Second returns the author also wrote.</returns>') -eq 1)) `
    $after.TwoReturnsTags
  # The FIRST <returns> is hand-written, so its mined case goes to the managed
  # 'Returns:' fact line and never into the author's tag -- unchanged from
  # before this task, asserted so the surplus fix cannot silently move it.
  Check 'E3: the mined case still goes to the managed ''Returns:'' fact line (the first tag is hand-written)' `
    ($after.TwoReturnsTags -match 'Returns: 7') $after.TwoReturnsTags

  # E'' -- TWO tags each with a surplus, in ONE comment. The occurrence counter
  # must reset per tag; if it carried over, the second tag's FIRST occurrence
  # would be miscounted as surplus and retracted -- preserved, but moved to the
  # residual position, which is a silent output change no single-tag row sees.
  Check "E''1: all FOUR tags survive when TWO different tags each have a surplus" `
    (($after.TwoSinceAndTwoSummary -match [regex]::Escape('<since>1.0</since>')) -and
     ($after.TwoSinceAndTwoSummary -match [regex]::Escape('<since>2.0</since>')) -and
     ($after.TwoSinceAndTwoSummary -match [regex]::Escape('<summary>First summary here.</summary>')) -and
     ($after.TwoSinceAndTwoSummary -match [regex]::Escape('<summary>Second summary here.</summary>'))) `
    $after.TwoSinceAndTwoSummary
  Check "E''2: each of the four appears exactly once" `
    (((Count-Of $after.TwoSinceAndTwoSummary '<since>1.0</since>') -eq 1) -and
     ((Count-Of $after.TwoSinceAndTwoSummary '<since>2.0</since>') -eq 1) -and
     ((Count-Of $after.TwoSinceAndTwoSummary '<summary>First summary here.</summary>') -eq 1) -and
     ((Count-Of $after.TwoSinceAndTwoSummary '<summary>Second summary here.</summary>') -eq 1)) `
    $after.TwoSinceAndTwoSummary
  # Position, which is what a carried-over counter would move. Each tag's
  # ordinal-1 occurrence keeps its own MODELED slot (summary first, since near
  # the end -- MergeComment's fixed order), and BOTH surplus lines land together
  # in the contiguous residual run after every modeled tag, in SOURCE order
  # (since 2.0 was written above summary "Second"). A carried-over counter would
  # push one of the ordinal-1 occurrences into that residual run instead.
  $eIdx = @{}
  foreach ($needle in @('<summary>First summary here.</summary>','<since>1.0</since>',
                        '<summary>Second summary here.</summary>','<since>2.0</since>')) {
    $eIdx[$needle] = $after.TwoSinceAndTwoSummary.IndexOf($needle)
  }
  Check "E''3: both ordinal-1 occurrences keep their MODELED slots, then both surplus lines follow in source order" `
    (($eIdx['<summary>First summary here.</summary>'] -lt $eIdx['<since>1.0</since>']) -and
     ($eIdx['<since>1.0</since>'] -lt $eIdx['<since>2.0</since>']) -and
     ($eIdx['<since>2.0</since>'] -lt $eIdx['<summary>Second summary here.</summary>'])) `
    $after.TwoSinceAndTwoSummary

  # =====================================================================
  # E' -- <remarks> is the ONE singular container whose surplus is NOT handed
  # back, and the reason is structural: it is the only modeled tag emitted
  # AFTER the residual block, so retracting a surplus <remarks> would move it
  # ahead of the slot-holder, the next scan would read the OTHER one as
  # occurrence 1, and the two would swap on every run. That oscillation was
  # MEASURED on these two shapes (md5 A/B/A over three cycles) before the
  # retraction set excluded <remarks>. The surplus text is therefore still
  # lost -- exactly as before this task -- and both shapes are pinned, with
  # facts and without, so the outcome cannot silently become facts-dependent.
  # The IDEMPOTENT block above is what makes the no-oscillation half
  # load-bearing: restore <remarks> to the retraction set and these two rows
  # fail there.
  foreach ($k in @('TwoRemarksNoFacts','TwoRemarksWithFacts')) {
    Check "E'1 ($k): the FIRST <remarks> survives" `
      ($after[$k] -match [regex]::Escape('First remarks.')) $after[$k]
    Check "E'2 ($k) PINNED LOSS: the SURPLUS <remarks> is still dropped -- retracting it cannot reach a fixed point (see IsRetractableSurplusContainer)" `
      (-not ($after[$k] -match [regex]::Escape('Second remarks the author also wrote.'))) $after[$k]
    Check "E'3 ($k): exactly ONE <remarks> element is emitted (nothing duplicated in exchange)" `
      ((Count-Of $after[$k] '<remarks>') -eq 1) $after[$k]
  }

  # =====================================================================
  # F -- CONTROL, the LOSSY direction. Reading the located body out of the
  # STRIPPED view instead of the ORIGINAL text would mangle the nested
  # <exception> out of this summary's own prose ("Body with an inline
  # tail."), the exact failure BuildStandaloneFor's content ban exists for.
  # =====================================================================
  Check 'F1: the tag nested inside a GENUINELY STANDALONE <summary> survives verbatim, unmangled' `
    ($after.NestedTagsInSummary -match [regex]::Escape('<summary>Body with an inline <exception cref="EIn">inline desc</exception> tail.</summary>')) `
    $after.NestedTagsInSummary
  Check 'F2: no standalone <exception> was fabricated from the nested one (exactly one <exception)' `
    ((Count-Of $after.NestedTagsInSummary '<exception') -eq 1) `
    $after.NestedTagsInSummary

  # =====================================================================
  # G -- CONTROL, ParseXmlDoc's untagged-prefix fallback. The <summary> tag
  # IS present and its body is EMPTY, so the parser's own fallback adopts the
  # leading prose. An occurrence-located read must defer to that, not return
  # the empty body and blank the summary.
  # =====================================================================
  Check 'G1: the leading prose is still adopted into the <summary> (the parser fallback still fires)' `
    ($after.PrefixProseEmptySummary -match [regex]::Escape('<summary>Leading prose the fallback adopts.</summary>')) `
    $after.PrefixProseEmptySummary
  # G2 is the one that reaches the located read at all: the <since> trips
  # HasAnySignal, so content comes from StandaloneBodyOf, and the <summary> body
  # is WHITESPACE (an empty body is caught by the length guard before
  # normalization ever runs). Remove the empty-located-body defer and this row
  # fails with an empty <summary> the author never wrote.
  Check 'G2: prose is adopted even on the FILTERED-VIEW path, with a whitespace <summary> body' `
    ($after.PrefixProseBlankSummaryExotic -match [regex]::Escape('<summary>Leading prose beside an exotic tag.</summary>')) `
    $after.PrefixProseBlankSummaryExotic
  Check 'G3: ...and the exotic tag that put it on that path is still there' `
    ($after.PrefixProseBlankSummaryExotic -match [regex]::Escape('<since>3.0</since>')) `
    $after.PrefixProseBlankSummaryExotic

  # =====================================================================
  # H -- CONTROL, no churn on the ordinary shape. The overwhelmingly common
  # case must be emitted exactly as before: this fix is a no-op wherever a
  # tag has at most one occurrence.
  # =====================================================================
  $hExpected = @(
    '/// <summary>Plain documented routine; nothing exotic.</summary>',
    '/// <param name="AValue">The value.</param>',
    '/// <returns>Twice AValue.</returns>',
    '/// <remarks>',
    '/// Hand prose.',
    '/// <!-- drag-lint:auto BEGIN -->',
    '/// Called from: tagoccurrence.CallsPlainDocumented (tagoccurrence.pas)',
    '/// Returns: AValue * 2',
    '/// <!-- drag-lint:auto END -->',
    '/// </remarks>'
  ) -join "`n"
  Check 'H1: the plain, fully-documented shape is emitted EXACTLY as expected (no churn)' `
    ($after.PlainDocumented -ceq $hExpected) ("actual=[" + $after.PlainDocumented + "]")

  # --- 7-bit ASCII --------------------------------------------------------
  $bad = @([IO.File]::ReadAllBytes($target) | Where-Object { $_ -gt 127 }).Count
  Check 'every byte written back is 7-bit ASCII' ($bad -eq 0) "nonascii=$bad"

  # =====================================================================
  # STRIP ROUND-TRIP -- this task's acceptance criterion.
  # =====================================================================
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'pre-strip index exits 0' ($LASTEXITCODE -eq 0)
  & $exePath document --unit $target --db $db --strip --apply 2>$null | Out-Null
  Check 'strip --apply exits 0' ($LASTEXITCODE -eq 0)

  $strippedLines = [IO.File]::ReadAllLines($target)
  $stripped = @{}
  foreach ($k in $pat.Keys) { $stripped[$k] = Get-DocBlock $strippedLines $pat[$k] }

  # PrefixProseEmptySummary is the ONE shape that legitimately does not
  # round-trip, and the reason is pre-existing and unrelated to this task:
  # ParseXmlDoc's fallback ADOPTS untagged prose into the <summary> tag, so the
  # author's two lines become one and no marker records that it happened.
  # Pinned as ACTUAL behaviour rather than excluded silently.
  # The two TwoRemarks shapes cannot round-trip either, for the structural
  # reason above (their surplus is never carried through, so it is gone by the
  # time --strip runs). Pinned below in their own right rather than excluded
  # quietly.
  # TwoSinceAndTwoSummary is a third kind of non-round-trip, and a third
  # PRE-EXISTING reason: its tags are not written in MergeComment's canonical
  # emission order, and `document --apply` canonicalizes order for every comment
  # it repairs -- no marker records a reorder, so --strip cannot undo one. All
  # four tags and their exact texts survive; only the order is the engine's.
  # (guards.TwoSinceTags is the same shape; that runner just does not strip.)
  $noRoundTrip = @('PrefixProseEmptySummary','PrefixProseBlankSummaryExotic',
                   'TwoRemarksNoFacts','TwoRemarksWithFacts','TwoSinceAndTwoSummary')
  $roundTripShapes = @($pat.Keys | Where-Object { $noRoundTrip -notcontains $_ })
  foreach ($k in $roundTripShapes) {
    Check "ROUND-TRIP: $k returns to EXACTLY what the author wrote" `
      ($stripped[$k] -ceq $pristine[$k]) `
      ("pristine=[" + $pristine[$k] + "] stripped=[" + $stripped[$k] + "]")
  }
  $proseStrippedExpected = @{
    PrefixProseEmptySummary       = '/// <summary>Leading prose the fallback adopts.</summary>'
    PrefixProseBlankSummaryExotic = "/// <summary>Leading prose beside an exotic tag.</summary>`n/// <since>3.0</since>"
  }
  foreach ($k in @('PrefixProseEmptySummary','PrefixProseBlankSummaryExotic')) {
    Check "ROUND-TRIP (pinned pre-existing): $k does NOT round-trip -- the parser fallback adopted the prose into the tag" `
      ($stripped[$k] -cne $pristine[$k]) ("stripped=[" + $stripped[$k] + "]")
    Check "ROUND-TRIP (pinned pre-existing): ...and what $k leaves is the ADOPTED summary, nothing lost" `
      ($stripped[$k] -ceq $proseStrippedExpected[$k]) ("stripped=[" + $stripped[$k] + "]")
  }
  # What each one keeps differs only by the pre-existing v(ADP3 T2) rule that a
  # <remarks> with facts to fence takes the multi-line form and stays there after
  # the fence is stripped (no marker records the reformat, so --strip cannot undo
  # it). Both keep the FIRST remarks and lose the surplus; both are marker-free.
  $remarksStrippedExpected = @{
    TwoRemarksNoFacts   = '/// <remarks>First remarks.</remarks>'
    TwoRemarksWithFacts = "/// <remarks>`n/// First remarks.`n/// </remarks>"
  }
  Check 'ROUND-TRIP (pinned pre-existing): TwoSinceAndTwoSummary does NOT round-trip -- the engine canonicalized tag ORDER' `
    ($stripped.TwoSinceAndTwoSummary -cne $pristine.TwoSinceAndTwoSummary) `
    ("stripped=[" + $stripped.TwoSinceAndTwoSummary + "]")
  Check 'ROUND-TRIP: ...but ALL FOUR of its tags survive the round-trip, texts intact -- only the order is the engine''s' `
    ($stripped.TwoSinceAndTwoSummary -ceq ("/// <summary>First summary here.</summary>`n" +
                                           "/// <since>1.0</since>`n" +
                                           "/// <since>2.0</since>`n" +
                                           "/// <summary>Second summary here.</summary>")) `
    ("stripped=[" + $stripped.TwoSinceAndTwoSummary + "]")
  foreach ($k in @('TwoRemarksNoFacts','TwoRemarksWithFacts')) {
    Check "ROUND-TRIP (pinned loss): $k does NOT round-trip -- its surplus <remarks> was never carried through" `
      ($stripped[$k] -cne $pristine[$k]) ("stripped=[" + $stripped[$k] + "]")
    Check "ROUND-TRIP (pinned loss): $k keeps the FIRST <remarks> and only that" `
      ($stripped[$k] -ceq $remarksStrippedExpected[$k]) ("stripped=[" + $stripped[$k] + "]")
  }

  # No engine marker survives anywhere after a strip: the whole point of the
  # round-trip is that nothing engine-written is left behind unmarked either.
  $stillMarked = @($strippedLines | Where-Object { $_ -match 'drag-lint:auto' })
  Check 'ROUND-TRIP: not one drag-lint marker survives the strip' ($stillMarked.Count -eq 0) `
    ($stillMarked -join ' | ')
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
