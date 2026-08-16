# A narrow project DELETES a shared unit's doc block when its own render is empty

> **CLOSED -- AND IT WAS ALREADY GUARDED. Verified 2026-08-16, no code written.**
>
> The ask below ("rebuild the 3-unit fixture and CHECK IT IN this time") had
> ALREADY been done, in the same session that wrote the banner. The fixture is
> not a new file -- it is inside `tests\autotest\run_shared_unit_staleness.ps1`,
> whose `Busy` unit is exactly the shape described here: marked
> `dl:shared ProjA, ProjB`, called seven times from `AOnly`, and absent from
> `BOnly`'s uses clause so B renders nothing for it.
>
> The three assertions are at `run_shared_unit_staleness.ps1:337-352`, under a
> comment block naming this defect's mechanism verbatim (`BlockDrifted` exiting
> on `SRes <> FRes` before reaching the inbound labels; `TDocumenter` emitting a
> pure `tekDeleteLines`; both halves now asking `HoldsForeignInboundEntries`
> first):
>
> * `the empty-render block is not deleted under B` (the writer half)
> * `and B reports no drift on it` (the checker half)
> * `A still sees no drift on the same block` (the wide project is not provoked
>   into rewriting it either)
>
> **Third note this session closed by RE-MEASURING rather than coding**, after
> `naming-autofix-corrupts-source` and `audit-store-backed-fix-paths`. The
> common failure is the same each time: the note records the state of the world
> when it was WRITTEN, and nothing walks back to amend it when the fix lands.
> Reading the guard file before rebuilding its fixture costs a minute.
>
> **Retire to `INBOX-Done/`.**
>
> Original 2026-08-14 banner follows.
>
> **LIKELY CLOSED by `eec91d2` ("close the empty-render hole in SharedFacts'
> header", 45 changed lines in `DRagLint.Doc.SharedFacts.pas` plus
> `Doc.Document`, `Core.Interfaces` and `Lint.SharedUnit`) -- but NOT VERIFIED,
> because that commit landed after this note was written and the note's repro
> script lived in a session scratchpad that is now gone.**
>
> Triaged 2026-08-14 (session 19) and left open deliberately rather than marked
> fixed on the strength of a commit subject. **To close it properly: rebuild the
> 3-unit fixture described below** (shared unit marked `dl:shared ProjA, ProjB`;
> project A calls the routine seven times, project B compiles the unit and never
> calls it), document from A, then run `document --apply` under B and assert A's
> block SURVIVES. That fixture is worth checking in this time -- this is a
> DESTRUCTIVE defect and it has now been re-diagnosed twice from scratch.
>
> Note the sibling defect `b3be650` ("shared-unit: never delete another project's
> contribution") also lands in this area, so the two may between them have closed
> it; that makes a written fixture more valuable, not less.

Found 2026-08-14 while building the Q0 truncation fixture. **Destructive** --
`lint-all --fix --apply` (and `document --apply`) under the narrow project removes
documentation the wide project wrote. Pre-existing; NOT introduced by the
truncation exemption, and not fixed by it.

## Repro (minimal, 3 units, ~20 s)

`C:\TEMP\claude\...\scratchpad\probe_busy.ps1` builds it from scratch. Shape:

* `shared\Busy.pas` -- marked `// dl:shared ProjA, ProjB`, declares `BusyRoutine`.
* `a\AOnly.pas` -- calls `BusyRoutine` from seven routines.
* `b\BOnly.pas` -- compiles `Busy` and **never calls `BusyRoutine`**.

Both projects index `shared` + their own folder. A documents `Busy` and applies:

    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: AOnly.BusyCaller1 (AOnly.pas), ... AOnly.BusyCaller7 (AOnly.pas)
    /// Pure
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure BusyRoutine;

Then, under B's database:

    drag-lint document --unit shared\Busy.pas --db B.sqlite
    -> File: ...\shared\Busy.pas
         delete lines 5..10
       doc: 1/1 decl(s), 1 edit(s) -- pass --apply to write

    drag-lint lint-all --db B.sqlite --quiet
    -> shared\Busy.pas:5:1  [warning] doc-drift: managed facts block is out of date

**Expected:** B leaves the block alone. Every entry in it names `AOnly.pas`, which
is outside B's closure -- the exact condition `TSharedFacts` already forgives.
**Actual:** B calls it stale and emits a pure deletion. `lint-all --fix --apply`
under B strips the block, and A then rewrites it on its next run: the unbounded
rewrite loop `dl:shared` exists to end.

## Mechanism -- two independent holes, both upstream of the shared-unit logic

**Checker.** `TSharedFacts.BlockDrifted` (`src\doc\DRagLint.Doc.SharedFacts.pas:408`)
compares the non-inbound residual FIRST:

    if SRes <> FRes then Exit(True);

Under B the fresh render has no managed block at all, so `FRes` is `''` while
`SRes` is `'Pure'`. It exits there and never reaches the inbound labels. The
forgiveness rule, the closure test and the truncation guard are all downstream of
a comparison that has already decided.

**Writer.** `TDocumenter` (`src\doc\DRagLint.Doc.Document.pas:1001`) sees
`Trim(Merged) = ''` -- `MergeComment` had nothing to say under B -- and, because
the region is fully engine-owned, emits `tekDeleteLines` and reports `daRemoved`.
`TSharedFacts.MergeInboundFacts` ran one line earlier (`:990`) and could not help:
it merges INTO a rendered block, and there is no block to merge into.

So the writer's preservation rule has the same blind spot as the checker's
forgiveness rule, in the one case where the narrow project renders nothing.

## Why it was invisible until now

`run_shared_unit_staleness.ps1` asserted `a truncated inbound list is not
forgiven` on this exact fixture and PASSED -- for the wrong reason. It exited at
the residual compare above and never reached `IsTruncated`. That guard therefore
had **no coverage at all** before the `MarkTrunc` fixture added on 2026-08-14.

Every other fixture in that file is called by BOTH projects, so all of them render
a non-empty block under B and none can reach this path.

## Fix sketch (not implemented -- it is a second decision, not a follow-on)

Both holes need the same fact: *the stored block holds inbound entries this
project cannot see*. `UnitInClosure(AStore, E)` already answers it.

1. **Checker:** on a marked unit, when the fresh block is ABSENT (not merely
   different), do not let the residual compare decide. If every stored inbound
   entry is out-of-closure and not uncertain, it is not drift.
2. **Writer:** on a marked unit, never emit `tekDeleteLines` over a region whose
   inbound entries are all out-of-closure. `daUnchanged`, not `daRemoved`.

Note the asymmetry to preserve: a marked unit whose block is genuinely dead --
every project has stopped calling it -- should still be reapable. This design
cannot tell that from "I cannot see the callers", which is the cost already
recorded in `DRagLint.Doc.SharedFacts`'s header under ENTRIES ONLY ACCUMULATE.
Deleting on the narrow project's say-so is the wrong side of that trade.

## Severity

Higher than `INBOX-document-qname-second-apply-nests-block-on-stale-anchor`: that
one corrupts a block on a second apply, this one silently discards another
project's work on a first apply. Both gate a wide `--apply`.
