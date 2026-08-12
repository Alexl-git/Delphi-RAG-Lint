# Design -- `dl:ok` reviewed-marker: suppress one finding on one line, and know when it goes stale

**Date:** 2026-08-12
**Status:** approved design, not yet planned or implemented
**Goal (owner):** account for every remaining lint message one way or another --
either fix it, tighten the rule, or record that a human looked at it and accepted
it. A review that cannot survive a reformat or a code move is not a review.

## Why not a line-number ledger, and why not an invisible watermark

`--baseline` already exists (`DRagLint.Lint.Baseline.pas`) and is already better
than line numbers -- it hashes
`ruleId | normalizedPath | Trim(line text) | ordinal`. It survives line-number
shifts and reindentation, but NOT interior whitespace changes, identifier
re-casing, line splits/joins, or a routine moving to another unit. Three of those
four are things **YADF does by design**, so running the formatter invalidates the
baseline.

Invisible watermarks (zero-width characters, trailing whitespace) are rejected
outright:

1. `.pas` files here are strict 7-bit ASCII and the battery enforces it. Zero-width
   characters are Unicode.
2. Trailing whitespace is the usual carrier, and stripping it is table stakes for
   a formatter -- YADF would silently destroy the review state.
3. Invisible state does not appear in code review or `git diff`, which defeats the
   purpose of recording that a human accepted a finding.

A visible marker that lives ON the line travels with the code through reformats,
line moves, file splits and routine renames, because it IS the code.

## Marker syntax

```pascal
except // dl:ok bare-except@7f3a -- rethrown by the caller, see TFoo.Run
```

* `dl:ok` -- the abbreviation. Short, greppable, ASCII.
* `bare-except` -- the rule id. REQUIRED, because a line can carry more than one
  finding and the marker must say which one was reviewed.
* `@7f3a` -- 4 hex characters of the line's content hash (below). This is what
  makes the marker self-invalidating when the code changes.
* `-- <reason>` -- optional free text, and the reason the whole feature exists.

Several findings on one line share one marker:

```pascal
// dl:ok bare-except@7f3a, deep-nesting@7f3a -- both accepted, see ADR-4
```

## The content hash

Computed over the line's **code tokens only**:

* comments EXCLUDED -- otherwise inserting the marker would change the hash the
  marker encodes (chicken-and-egg);
* whitespace dropped, so reindentation and interior alignment do not matter;
* identifiers lowercased, so YADF's first-occurrence case normalisation does not
  matter (Delphi is case-insensitive, so this loses nothing).

4 hex characters. This is a staleness detector, not a security primitive: a
collision means one changed line keeps its suppression, which is the same failure
mode as no hash at all, and the cost of more characters is line noise.

## Semantics at lint time

For a finding on line L with rule R:

| marker on L | hash | outcome |
|---|---|---|
| lists R | matches | **suppressed** |
| lists R | mismatches | **reported**, plus a `review-marker-stale` hint on the marker |
| does not list R | -- | reported normally |
| lists R, but R produces no finding | -- | `review-marker-unused` hint |

The stale case is the load-bearing one. Without it, editing a reviewed line keeps
the old suppression and the finding is silently lost -- exactly the
silent-wrong-answer shape this project keeps hitting. `review-marker-unused` is a
hint so markers get cleaned up rather than accumulating; default ON as a hint,
disableable like any rule.

## Insertion UX

**Primary: LSP code action.** Each diagnostic gets a `drag-lint: mark reviewed`
action. Accepting it appends the marker to the end of that line, or merges the
rule id into an existing `dl:ok` marker on the same line. This is what serves the
VS Code diagnostics panel's right-click menu, and it is the standard mechanism.

**Follow-on: the Delphi IDE plugin** gets the same item in its diagnostics panel
context menu, reusing the same insertion function -- the marker text is produced
by one shared pure routine, never formatted twice in two places.

Insertion must respect the file conventions: 7-bit ASCII, CRLF preserved, and no
trailing whitespace introduced.

## Interaction with YADF

The marker is an ordinary end-of-line `//` comment, which YADF already round-trips
(its token list carries comments with their leading whitespace). Two regression
tests:

1. Run YADF over a file containing markers; assert every marker survives verbatim.
2. Assert the hash still MATCHES after YADF reformats the line -- this is the test
   that pins the "whitespace dropped, identifiers lowercased" normalisation. If it
   ever fails, the marker scheme is broken for the one tool most likely to touch
   the code.

## Relationship to `--baseline`

Complementary, not a replacement.

* `dl:ok` -- per-finding, deliberate, carries a reason, survives anything. For
  findings a human has actually looked at.
* `--baseline` -- bulk "accept the existing debt on day one", no source changes.
  Separately worth hardening to fingerprint on
  `enclosing qualified name + normalized token sequence` instead of
  `file path + raw line text`, which would give it the same reformat-immunity.

## Out of scope

Block-level or file-level markers (`dl:ok-file`), and any marker that suppresses a
rule across a whole project -- that is what the config's disable list is for.
