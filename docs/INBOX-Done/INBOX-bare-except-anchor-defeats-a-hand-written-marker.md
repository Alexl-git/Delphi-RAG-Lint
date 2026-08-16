> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (430fd37): @warn moved to (kExcept). Guarded by run_bare_except_anchor.ps1 (6/6, red against both broken variants).

# `bare-except` anchors one line below the `except`, so a hand-written `dl:ok` never matches

> **FIXED 2026-08-16 (session 21).** Fix **(A)**, as recommended. `rules/bare-except.scm`
> now captures `@warn` on `(kExcept)`. Guarded by `tests/autotest/run_bare_except_anchor.ps1`
> (6/6) and by `tests/reviewmarker/run_review_marker_prose.ps1`, whose fixture now
> carries the marker on the `except` line -- i.e. the test that documented the
> defect is now the regression anchor for the fix.
>
> **The family question below is ANSWERED: there is no family.** Every sibling
> rule already anchors on its own keyword -- `empty-except` `(kExcept)`,
> `empty-finally` `(kFinally)`, `empty-on-handler` `(kDo)`, `empty-conditional`
> `(kThen)`/`(kElse)`, `empty-loop-body` `(kDo)`/`(kRepeat)`, `empty-case-branch`
> `(caseLabel)`. `bare-except` was the lone outlier, so (A) is the house
> convention rather than a new invention -- and the design spec
> (`docs/superpowers/specs/2026-08-12-reviewed-marker-design.md:35`) and
> `DRagLint.Lint.ReviewMarker.pas:6` had *both* been showing the marker on the
> `except` line the whole time. The query disagreed with its own spec.
>
> **A TRAP WORTH KEEPING.** The first fix wrote
> `(kExcept) @warn . except: (statements)`. The `.` anchor is tighter, compiles,
> and silently destroys the feature: a trailing comment on the `except` line is a
> node BETWEEN those two, so adding the marker made the rule stop matching. The
> marker then SILENCED the rule instead of accounting for it, and
> `review-marker-unused` turned around and told the reviewer to delete it -- the
> exact no-exit loop `COMMENT_SENSITIVE` (`DRagLint.CLI.pas`) exists to break.
> It presents as *"suppression works"*, because the finding is gone either way.
> Only an arm that adds a **non-marker** comment and demands the finding SURVIVE
> separates the two, which is why the guard has one. `bare-except` must never be
> added to `COMMENT_SENSITIVE`.
>
> **CHURN, MEASURED, AND NOT YET PAID.** 12 machine-written markers carry a
> recorded `@hash` and all sit on the statement line, one below their `except`:
> **DataCopy 8** (`CSVRoutines`, `DPPRoutines`, `uConfigurationService`,
> `uFileUtils` x4, `uMainZeissCopy`) and **YADF 4** (`YADF.Guard`, `YADF.Options`,
> `YADF.Tokens`, `YadfMain`). Each needs BOTH a move up one line and a NEW hash,
> because the hash is over the normalized code line and `except` hashes
> differently from `result := 0;`. None inside `Delphi-RAG-lint` itself (its two
> hits are prose in doc-comments). **This repo is clean; the two consumer repos
> are not, and re-stamping them is deliberately left as its own task** -- it edits
> another project's source and should not ride along on a linter commit.

Class: **wrong** (usability, in the suppression mechanism).
Found 2026-08-14 (session 19) while building
`tests\reviewmarker\run_review_marker_prose.ps1`.

## Symptom

```pascal
26  procedure RealMarked;
27  begin
28    try
29      Writeln('a');
30    except // dl:ok bare-except      <- where a human writes the marker
31      Writeln('b');                  <- where the finding actually anchors
32    end;
```

```
uProse.pas:31:5  [info] bare-except: Bare except (no 'on E: ... do') catches every exception ...
uProse.pas:30:1  [hint] review-marker-unused: dl:ok marker for "bare-except" no longer
                        matches any finding on this line -- remove it.
```

Both at once, from one `lint-all`: the finding is NOT suppressed, AND the marker
that was meant to suppress it is reported as useless. Moving the marker to line
31 (`Writeln('b'); // dl:ok bare-except`) works.

## Why it matters more than it looks

The marker grammar ties a marker to A LINE, and `dl:ok` is the accountable
suppression mechanism. So the rule's anchor choice silently decides where a
reviewer must write their signature -- and for `bare-except` that place is NOT
the construct the rule is about. `except` is the thing being reported on; the
statement after it is incidental, and in an empty handler there is no statement
at all.

Two consequences:

1. **The obvious placement fails silently in the worst way.** The reviewer
   believes they accepted the finding; the finding is still reported; and the
   extra `review-marker-unused` hint tells them to DELETE the marker, which is
   the opposite of what is needed.
2. **It compounds a second defect.** `review-marker-unused` was already firing on
   prose (see `INBOX-review-marker-matches-example-markers-in-prose.md`), so on
   this fixture three of the four reported "unused" markers were wrong for two
   different reasons at once.

Note `allow` is unaffected -- it writes to the `file:line` it is given, which
comes from the finding, so the machine-written marker lands correctly. This only
bites a HAND-WRITTEN marker, i.e. exactly the case the accountability story is
built on.

## Which is the bug?

Two candidate fixes, and they are not equivalent:

* **(A) Move the anchor to the `except` keyword.** Arguably where it belonged:
  the finding is about the handler, not its first statement. Risk: it changes the
  reported line for every existing `bare-except` finding, invalidating every
  `@hash` already recorded against the old line across all projects -- they would
  all become `review-marker-stale`. That is loud rather than dangerous, but it is
  a corpus-wide churn event and needs to be a deliberate one.
* **(B) Let a marker on the `except` line cover a finding on the following
  statement.** A special case in the matcher, which weakens the "a marker
  belongs to a line" rule that makes hashes verifiable. Do not.

(A) is the right shape, but check first whether other constructs share the
pattern (`try..finally`, `on E:` handlers, `empty-except`, `case` else arms) --
if several rules anchor one line off their own construct, fix the family, not the
instance, and take the hash churn once.

## Reproduce

`tests\reviewmarker\run_review_marker_prose.ps1` builds the fixture; move the
marker from the statement line back to the `except` line and the safety
assertion fails while a fourth `review-marker-unused` appears.

Must be run with **`lint-all`**, not `lint <file>` -- `review-marker-unused` is a
whole-run rule (see `INBOX-lint-single-file-silently-omits-lint-all-rules.md`).
