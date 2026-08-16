> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# OWED: a guard that the CHECKER and WRITER use the same doc caps

> **CLOSED 2026-08-14 (session 19) -- `tests\autotest\run_doc_cap_parity.ps1`,
> non-vacuous, with a negative control.**
>
> **The missing precondition was a HAND-WRITTEN `<returns>` TAG.** The `Returns:`
> FACT line is gated by `IncludeReturns` (`DRagLint.Doc.Regions.pas:2856-2860`):
>
> ```pascal
> var ReturnsHandWritten: Boolean :=
>   AExistingHasAnyTag and StandaloneReturns.HasReturnsTag
>   and (not IsEngineOwnedRegardlessOfContent(BodyReturns));
> var IncludeReturns: Boolean :=
>   ReturnsHandWritten and AHasReturn and (Length(AFacts.ReturnCases) > 0);
> ```
>
> For a managed/empty `<returns>` the mined cases go INSIDE the tag as
> `Observed: ...` instead -- the two never both appear. **Both earlier attempts
> carried only bare `///` prose and no XML tag at all**, so they could never grow
> the line no matter how many cases they mined. Nothing was wrong with their
> return-case shapes; the diagnosis in "What to find out first" below was aimed
> at the wrong half of the gate. The working shape was already in the tree:
> `tests\autodoc\fixtures\docret\docret.pas`'s `Doubler`.
>
> Measured precondition, now asserted: `/// Returns: 'a'; 'b'; 'c'; 'd'; 'e'; 'f'`
> -- 6 of 9 mined cases, 7th (`'g'`) absent.
>
> **Two further things the third attempt had to discover, both recorded in the
> test's header so a fourth reader does not repay them:**
>
> 1. **`doc-drift` is a `lint-all` rule, not a `lint <file>` rule.** `lint
>    uCapPar.pas` prints `0 finding(s)` on the exact file `lint-all` warns about.
>    The first working version of this guard used `lint <file>` and went green
>    for the wrong reason. Filed separately:
>    `INBOX-lint-single-file-silently-omits-lint-all-rules.md`.
> 2. **The guard carries its own NEGATIVE CONTROL** -- it rewrites the local
>    `.drag-lint.json` to `max_return_cases: 20` and asserts the finding DOES
>    fire, then restores 6. Without it, "zero findings" is indistinguishable from
>    "the rule never ran", which is precisely how the first version passed. This
>    is what the note below was asking for and could not name.
>
> Attempt 2's dead fixture (`tests\autodoc\fixtures\docm1\cap_parity.pas`, a
> 9-arm `case` with bare `///` prose and no `<returns>` tag) was deleted; its
> shape is described above and it was never referenced by a runner.
>
> The cheaper "assert on the REAL corpus" alternative proposed at the bottom of
> this note was NOT needed and was not taken: the synthetic fixture reaches the
> same code path in ~20 seconds and needs no self-index.

The fix is shipped and verified on the real defect. **The regression guard is
not**, and this note exists so that is not mistaken for "tested".
(Historical text below -- kept because it records the two dead ends.)

## What was fixed

`TDocDrift.Analyze` called `TDocFactsBuilder.Build` with three arguments and
took the DEFAULTS for the rest, while every `document` entry point passed the
MANIFEST values. `docs.max_return_cases` is **6** in the manifest and **20** in
`BuildFor`'s default, so any routine with more than 6 minable return cases
deadlocked permanently: `document` wrote a `Returns:` list capped at 6, the
checker rebuilt one capped at 20 and called it stale, and `document` then
re-rendered the same 6 and reported "nothing to document". No command could
resolve it.

Caps are now threaded through `Analyze`, `RunDocDrift`, `FixEditsForDocDrift`
and the CLI call sites.

**Verified on the real case:** `DRagLint.Refactor.EnumHelper.Generate` (the
routine that surfaced it) no longer drifts, and every `managed facts block is
out of date` finding on drag-lint's own source is gone -- the only doc-drift
left is the 3 hand-written `<exception cref>` findings, which are a different
and arguably correct rule.

## Why the guard is not written

Two attempts. The fixture has to make the writer emit a managed block whose
`Returns:` fact line is TRUNCATED by a low configured cap, and neither shape got
there:

1. `Exit('negative')` x4 + `Result := 'large'` -- only ONE return case was
   mined, and with no caller the facts-only gate emitted no managed block at
   all.
2. `Result := X` in five branches, plus a caller unit so the gate passes -- a
   managed block IS emitted (`drag-lint:auto BEGIN` present) but it carries no
   `Returns:` fact line whatsoever.

So the precondition assertion -- "the cap actually took effect, i.e. the line is
truncated" -- failed both times, which correctly reported the other two
assertions as VACUOUS. They passed, and they were testing nothing. A green test
here without that precondition would have been worse than no test.

**Do not write this guard without that precondition.** It is the only thing
standing between a real assertion and one that passes because both sides used
the same default.

## What to find out first

What actually produces a `Returns:` FACT line (the one inside the managed block,
distinct from the `<returns>` XML tag)? `DRagLint.Refactor.EnumHelper.Generate`
has one with 6 entries:

    /// Returns: Default(TEnumHelperGen); Ord(Self); GetEnumName(...); ...

so the shape exists -- read `MineReturnExpressions` (DRagLint.Hover.Returns) and
copy the shape it actually mines rather than guessing, which is what failed
twice above.

## Cheaper alternative worth considering

Rather than a synthetic fixture, assert on the REAL corpus: after a converged
autodoc pass on drag-lint's own source, `lint-all` must report **zero**
`managed facts block is out of date`. `EnumHelper.Generate` lives in that
corpus, so re-breaking the threading fails the assertion immediately. The cost
is that the test needs a fresh self-index, which is slow; the benefit is that it
needs no fixture and cannot go vacuous.
