# Triage -- the 22 red autodoc checks, and the ruling they need

Produced 2026-08-02, on `feat/autodoc-phase3` @ `4438c06` (post `main` merge).
Requested by LATEST-75: *"produce a per-case triage (genuine defect vs known-gap
fixture that should be re-pinned) with a recommendation, and get a ruling before
touching the engine."* **No engine change has been made.**

## The count is confirmed, and it is stable across the merge

22 failing checks in 5 suites, unchanged before and after merging `main`:

| suite | failing checks |
|---|---|
| `run_doc_p3_decayrouting` | 12 |
| `run_doc_p3_guards` | 3 |
| `run_doc_p3_idempotency_sweep` | 3 |
| `run_doc_p3_tagoccurrence` | 1 |
| `run_doc_p3_unhandledtags` | 3 |

## The mechanism, now measured rather than described

LATEST-75 described it correctly: harvest writes a `<summary>` on cycle 1, so
cycle 2 sees a populated region, routes the symbol from the **fresh-insert**
branch to the **repair** branch, and repair "re-emits only what it models" --
deleting hand-written tags it does not model.

What the numbers add is **what the late cycle actually does**. From
`run_doc_p3_idempotency_sweep`, SWEEP C, `idempotency_shapes.EmptyRemarksOnly`:

```
sizes  = 7502 -> 9481 -> 9456 -> 9456
actions= created/1  extended/2  unchanged/0
```

Cycle 1 creates (+1979 bytes). **Cycle 2 SHRINKS the file by 25 bytes.** Cycle 3
is a fixed point. The three symbols that settle late are
`EmptyRemarksOnly`, `ValuePlusEmptyRemarks` and `GappedEmptyRemarks` -- every one
of them named for an author's **empty `<remarks></remarks>`**. LATEST-75 recorded
watching exactly that element be deleted at
`fixtures/docp3/decayrouting.pas:31`.

So the late cycle is not cosmetic re-ordering. It is the repair branch **deleting
the author's tag**, and the file is stable afterwards only because there is
nothing left to delete.

## Why this matters for the "obvious fix" -- it does NOT do what it appears to

The obvious fix is to widen the repair-vs-fresh term so harvested content routes
to repair on cycle 1. `src/doc/DRagLint.Doc.Document.pas:764-770` records that
this was already tried and **deliberately reverted**.

The measurement above says something sharper than "it was reverted for a reason":

> Widening the term does not PREVENT the deletion. It moves it from cycle 2 to
> cycle 1.

Idempotency would go green because the destruction would happen inside the very
first apply, leaving nothing for cycle 2 to change. The suites would pass and the
author's `<remarks>` would still be gone -- sooner, and now on the first run a
user ever performs. **That trades a red test for silent data loss, and it buys
the appearance of a fix.** It should not be done.

## Per-case classification

**Group A -- direct symptoms of the mechanism (16 checks). Genuine defect.**
`decayrouting`'s md5 convergence check (`F0AE1CFC 5D809B3C 5D809B3C` -- cycle 1
differs, 2 and 3 agree), all 3 `idempotency_sweep` checks, and the
`decayrouting` N4 group. These fail because output settles one cycle late, and
the late cycle is a deletion. Fixing the deletion fixes all of them.

**Group B -- "KNOWN GAP, pinned" checks whose gap CHANGED SHAPE (5 checks).**
`decayrouting` N5/N6/N7 and `tagoccurrence`'s round-trip. These assert that a
known defect is still present; they fail because the defect's shape moved once
harvested content began arriving. Each needs re-pinning to the current
behaviour **after** Group A is settled -- re-pinning them first would bake in a
shape that is about to change again.

**Group C -- fabrication beside the author's element (1 check).**
`guards`' "T3f minor 1: no `<remarks>` was fabricated beside the author's". This
is the same family but the opposite direction -- an ADDED sibling rather than a
deleted element. `unhandledtags`' 3 checks are its counterpart: the guard that
protects unmodeled tags still holds for `<value>`, so the protection exists and
is simply not applied on the repair path.

Group C is the useful clue: **the engine already has a guard that preserves an
unmodeled tag** (`unhandledtags` check 3 passes -- `HasValueTag`'s span is
byte-identical after apply). The repair branch does not use it.

## Recommendation

**Do not widen the repair-vs-fresh routing term.** Make the REPAIR branch
non-destructive instead: it should preserve hand-written tags it does not model,
exactly as the fresh-insert path's existing guard already preserves `<value>`.

Then cycle 2 has nothing to delete, makes no edit, and idempotency holds *because
the output is genuinely a fixed point* rather than because everything removable
has been removed. Group A goes green on the merits; Group B can then be re-pinned
against a shape that has stopped moving.

This is a larger change than the reverted one-line widening, and it is the one
that matches what the tests are actually asserting.

## What is needed from the user

A ruling on the recommendation above before any engine change. Two specific
questions:

1. **Confirm the direction** -- repair becomes non-destructive, rather than
   routing harvested content to repair earlier.
2. **Confirm the scope** -- is preserving *every* unmodeled tag correct, or are
   there tags the engine should be allowed to rewrite (e.g. a stale
   `<param>` for a parameter that no longer exists)? The current repair branch
   makes no distinction, and that distinction is a product call, not a
   derivation.

Until that ruling, the 22 remain red **by choice**, and that choice is now
recorded with its evidence rather than inherited.
