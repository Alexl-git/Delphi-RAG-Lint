# Open questions from the 2026-08-13 autonomous session

## 0. ANSWERED 2026-08-14: the cheap fix, segments to the backlog

**Owner ruling: exempt `dl:shared` units from inbound-list truncation now; keep
per-project attributed segments on the backlog for ATTRIBUTION.**

Implemented the same day. Two cap sites, not one -- `CalledFrom` (capped by
`docs.max_callers`) and `UsedInUnits` (capped by `DocDisplayCount`'s
>15-total->10-shown rule, a different rule that needed its own exemption and its
own fixture). Fixing one and leaving the other would have converged routines and
left every shared TYPE drifting. `Calls:` shares `DocDisplayCount` and is
deliberately NOT exempted: it derives from the unit's own code, so every project
computes the same set and there is nothing to reconcile.

Guards, since each of these fixes would otherwise "pass" by widening the rule:
`tests\autodoc\run_doc_cap.ps1` holds the cap in place for an UNMARKED unit
(16 callers -> 5 shown, `(+11 more)`), and a new `MarkTrunc` fixture in
`run_shared_unit_staleness.ps1` holds the still-live guard against a truncated
STORED line.

Two things the work turned up, both recorded:

* `docs\INBOX-shared-unit-empty-render-deletes-block.md` -- **destructive and
  pre-existing.** A narrow project whose fresh render is EMPTY emits a pure
  `tekDeleteLines` over the wide project's block. Repro in the note.
* The old assertion `a truncated inbound list is not forgiven` was passing for
  the WRONG REASON -- it exited at the residual byte compare and never reached
  `IsTruncated`, so that guard had no coverage at all until `MarkTrunc`.

Backlog record: `docs\BACKLOG-shared-unit-attribution.md`.

Original question follows.

## 0-original. READ FIRST -- the shared-unit fix may be far cheaper than the one chosen

You chose **per-project attributed segments** for the `(+N more)` churn. New
evidence found while implementing suggests a much smaller change would do, and
you should see it before that build starts.

**Every one of the 6 remaining doc-drift findings across YADFOT/YADFSetup is a
TRUNCATED line.** Verified by dry-running `document` per project and reading
the freshly rendered block (NOT the source line -- the source can look
untruncated while the fresh render carries `(+1 more)`; that mistake cost me a
wrong reading first time round).

And `TSharedFacts.MergeInboundFacts` **already reconciles across projects
without knowing any project's name.** It uses `UnitInClosure(AStore, E)` to
preserve exactly the entries "this project cannot see". The union is shipped,
reasoned about at length, and works -- on untruncated lines.

Truncation is the ONLY thing that breaks it, and for a stated reason: a
`(+N more)` window cannot be set-differenced soundly in either direction.

**So the cheap fix is: do not truncate inbound lists on a `dl:shared` unit.**
Not "raise `docs.max_callers` globally" (the option you declined, which
lengthens every line in every project) -- just exempt marked units, where the
whole point is that several projects must agree on one line. The existing union
then handles the rest and the family converges.

Per-project segments remain the better long-term answer for ATTRIBUTION (they
say WHICH project sees a caller, which no union can). But they are a large
change to a delicate unit, and they are no longer needed to reach convergence.

**Not implemented either way** -- this reverses part of a decision you already
made, so it is yours to take.


Recorded as instructed: none of these blocked the work, so I carried on past
them. Each says what I did in the meantime.

## 1. `try-except-swallowed`: mark uniformly-uncertain caller lists? (STILL OPEN)

The long-standing ' ?' ruling. Now a COST decision rather than a safety one,
because the fabrication defect that made it urgent is fixed (107 fabricated
callers -> 1, re-verified corpus-wide this session: 0 fan-out across 22 caller
lines in 4 units).

Flipping it adds ' ?' to **70-85%** of all reference entries (65/99 lines on
YADF, 832/1126 on drag-lint) and reverses a decision `run_doc_p3_callerline.ps1`
pins with mutation cases M2/M3.

**Meanwhile:** left alone. Recorded in the fabrication INBOX.

## 2. `unused-public-symbol` on a symbol used only by a SIBLING project

YADFOT reports `EmitTokens` and `OptionsHelpText` as dead. Both are reachable
from `YadfMain.pas`, a member of YADF and YADFSetup but not YADFOT. The finding
is TRUE within YADFOT's closure and answers the wrong question.

Needs the DB-role ruling (`specs/2026-08-13-db-authority-and-freshness.md`)
to say whether reachability may cross into a sibling project's DB for THIS rule
without reopening the fan-out that wrote junk facts into YADF source.

**Meanwhile:** NOT `allow`ed, per the standing instruction. Still reported.

## 3. `unit-too-large` cannot be acknowledged at all

Owner has said leave YADF.Layout.pas alone -- fine. But the finding anchors at
`:1:1`, which is inside a block comment, so `allow` REFUSES it (correctly: the
marker would be invisible and the rule would keep firing).

So a file-level rule has no way to record a review. Raising `threshold` in
config is not a review, it is hiding the number, and it silences every other
unit too.

**Question:** should `allow` grow a file-level anchor (e.g. a `dl:ok-file`
marker written after the unit header, or an entry in the project's
`_D-RAG\drag-lint-project.json`)?

**Meanwhile:** left reported. It is 1 finding per project.

## 4. `document --qname --apply` twice: stale anchor

Two applies without a reindex between them nest the second block inside the
first, because the DB still holds pre-insert line numbers.

This looks like it wants the freshness rule from
`specs/2026-08-13-db-authority-and-freshness.md` ("any DB/source mismatch ->
complete reindex"), i.e. `--apply` should refuse or self-reindex when the file
no longer matches the DB. That spec is OPEN and architectural.

**Meanwhile:** tested whether this session's duplicate-insert guard covers it
as a side effect (see the session's resume doc for the answer).

## 5. Should the `.bak` files autofix leaves be cleaned up?

`lint-all --fix --apply` writes `<file>.pas.bak` for every file it scanned, not
only the ones it changed -- 8 of them appeared in YADF for a 2-file edit. They
are gitignored, so they are clutter rather than risk.

**Meanwhile:** left in place; they are the autofix's safety net.
