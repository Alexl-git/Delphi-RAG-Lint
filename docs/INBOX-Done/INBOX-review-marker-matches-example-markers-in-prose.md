> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# `review-marker-unused` fires on EXAMPLE markers inside comments and doc-tags

> **FIXED 2026-08-14 (session 19).** `TReviewMarkers.MarkerBearingLines` carries
> brace / star-paren state across lines and rejects `///`; the unused-marker walk
> in `DRagLint.CLI` consults it before parsing a line.
>
> **The risk this note flags was DESIGNED OUT rather than accepted.** The gate is
> applied to the REPORTER ONLY -- suppression is decided in a separate loop, over
> a line that already carries a finding, and that loop is untouched. So the
> failure mode described in "Why it was NOT fixed on the spot" (real `dl:ok`
> markers stop being recognised, every suppressed finding returns across every
> project at once, no signal as to why) is not reachable by this change. The
> regression test asserts it directly: a real marker still suppresses its
> `bare-except`, and is still reported as unverifiable-without-hash, which proves
> the marker was READ and not merely skipped.
>
> **NOT taken: lifting `ScanHeader` out of `SharedUnit`.** That was this note's
> suggestion and it remains the tidier end state, but `ScanHeader` is shaped
> around one question ("where is the marker in the header region") and is
> load-bearing for `dl:shared`. Generalising it to answer "which lines of a whole
> file can bear a marker" would have put a live suppression mechanism and a new
> reporter on one freshly-refactored code path. Two ~40-line state machines that
> each do one job beat one that does two, when one of them is the suppression
> mechanism. Recorded so it is a decision rather than an oversight.
>
> **DELIBERATELY NOT implemented: "no code before the `//`".** This note names it
> as part of the discriminator and it would be more correct, but it also stops a
> stranded own-line marker being reported as unused -- a behaviour change neither
> reported case needs. Both come out right on block state and `///` alone. The
> test asserts the own-line marker IS still reported, so this stays a decision.
>
> **Found while fixing it, filed separately:**
> `INBOX-bare-except-anchor-defeats-a-hand-written-marker.md`. `bare-except`
> anchors on the first statement INSIDE the handler, so a marker written at the
> obvious place -- trailing the `except` keyword -- never matches its finding and
> is then itself reported unused. Two wrongs on one line, from two causes.
>
> Note for the next reader: `review-marker-unused` is a **`lint-all`** rule.
> `lint <file>` prints `0 finding(s)` on a file `lint-all` warns about, and the
> first version of the regression test used `lint` and passed for that reason.
> See `INBOX-lint-single-file-silently-omits-lint-all-rules.md`.

Class: **wrong**. 2 findings on drag-lint's own source, both in the unit that
DEFINES the marker syntax. Found 2026-08-14 during LoopZero round 1.

## Reproduce

    drag-lint lint-all --project src\cli\drag-lint.dproj --quiet

    src\lint\DRagLint.Lint.ReviewMarker.pas:6:1    [hint] review-marker-unused:
      dl:ok marker for "bare-except" no longer matches any finding on this line -- remove it.
    src\lint\DRagLint.Lint.ReviewMarker.pas:176:1  [hint] review-marker-unused: (same)

Neither line carries a marker. Both are documentation OF the marker:

* **Line 6** sits inside the unit's `{ ... }` header block comment, which opens
  on line 3. The line reads
  `    except // dl:ok bare-except@7f3a -- rethrown by the caller`
  -- it LOOKS like code plus a trailing marker, and is entirely commented out.
* **Line 176** is inside a DocInsight tag:
  ``/// <returns>e.g. `dl:ok bare-except@7f3a -- rethrown by the caller`.</returns>``

So the rule reports that a marker "no longer matches any finding" on lines that
never had a marker, and its advice ("remove it") would damage the documentation.

## Why it happens, and why the obvious fix is wrong

`TReviewMarker.Parse(const ALineText: string)` takes ONE LINE. A single line
cannot tell whether it is inside a `{ }` / `(* *)` block comment, so the defect
is not in `Parse` -- it is in the caller that walks the file and decides which
lines to hand it.

**"Ignore markers in comments" is NOT the fix.** A real marker is always in a
comment:

    except // dl:ok bare-except@7f3a -- rethrown by the caller

The discriminator is whether the `dl:ok` sits in a `//` comment that TRAILS CODE
on that line, versus inside a block comment, a `///` doc comment, or a line with
no code before it.

## The precedent is in the sibling unit, and it is explicit

`DRagLint.Lint.SharedUnit`'s header already argues this at length, for the
`dl:shared` marker, under "WHY THE READER IS A COMMENT-STATE SCANNER AND NOT A
LINE SPLIT" -- it notes that matching text answers "does the string appear",
which is a different question from "is there a marker here", and that the naive
version both accepts markers inside string literals and rejects real ones. Its
`ScanHeader` tracks brace / star-paren / slash-slash comment state plus string
state. The same machine is what this reader needs; it should be lifted out of
`SharedUnit` and shared rather than written twice.

## Why it was NOT fixed on the spot

This is the SUPPRESSION mechanism. If a comment-state scanner is wrong in the
other direction, real `dl:ok` markers stop being recognised, every suppressed
finding silently returns, and counts jump across every project at once -- with
no signal that the cause was the reader rather than the code. That deserves a
focused change against the three `run_review_marker_*.ps1` suites, not a
drive-by edit at the end of a long session.

## Note for whoever takes it

`review-marker-unused` is a LoopZero done-criterion (the marker corpus must
itself be at zero), so this defect currently makes a true zero unreachable on
this repo no matter what else is fixed. That is the argument for doing it.
