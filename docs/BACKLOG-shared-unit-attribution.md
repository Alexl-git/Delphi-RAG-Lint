# BACKLOG -- per-project attributed segments for shared-unit facts

Status: **deferred by owner ruling, 2026-08-14 (Q0).** Not abandoned -- it answers
a question the shipped design cannot, and that question will come back.

## What was decided instead

Q0 asked whether to build per-project attributed segments or exempt `dl:shared`
units from inbound-list truncation. The owner took the exemption. It is two lines
of behaviour at two cap sites in `DRagLint.Doc.Facts` (`CalledFrom`'s
`docs.max_callers` cap and `UsedInUnits`' `DocDisplayCount` cap), and it lets
`TSharedFacts`' existing union -- already shipped, already reasoned about at
length -- reach a fixed point across the projects that compile a marked unit.

The reasoning: truncation was the ONLY thing breaking convergence. A `(+N more)`
window cannot be set-differenced soundly in either direction, so
`TSharedFacts.BlockDrifted` withheld forgiveness on any truncated line and the
block drifted forever. Measured 2026-08-13, every remaining doc-drift finding
across YADFOT/YADFSetup was a truncated line. Remove the window and the union
already handles the rest.

Raising `docs.max_callers` was considered and declined separately: any finite cap
only moves the cliff, and it lengthens every line in every project to buy one
shared unit's convergence.

## What segments would still buy

**Attribution, which no union can express.** The union says a caller exists
somewhere across the family. It cannot say WHICH project sees it, so a reader of

    /// Called from: YADF.Options.OptionTable (YADF.Options.pas), YadfMain.ParseFlags (YadfMain.pas)

cannot tell that the second entry is invisible to YADFOT. Segments would say so:

    /// Called from [YADF]: YadfMain.ParseFlags (YadfMain.pas)
    /// Called from [YADF, YADFOT, YADFSetup]: YADF.Options.OptionTable (YADF.Options.pas)

**Reaping.** `DRagLint.Doc.SharedFacts`' header records the cost of the union
under ENTRIES ONLY ACCUMULATE: a caller deleted in ANOTHER project's source is
indistinguishable, from inside one project, from a caller this project simply
cannot see. Both read as "in stored, not in fresh, unit not in my closure", so the
union never reaps either. Attributed segments make the two distinguishable --
an entry attributed to project P, checked while running under P, is reapable.

**The line-length cost the exemption accepts.** Uncapped lists grow without bound
on exactly the units most likely to have many callers. Segments keep a cap per
segment, so the growth is bounded per project rather than per family.

## Why it is not cheap

`DRagLint.Doc.SharedFacts` is a delicate unit that has produced five incidents on
this seam. Segments change the block GRAMMAR, which means:

* every reader of `INBOUND_LABELS` re-learns how a label is spelled;
* `ParseBlock` / `SplitEntries` / `IsTruncated` all take a project dimension;
* the marker's project list stops being documentation and becomes load-bearing
  input, so `check-shared` moves from "nice to have" to "required" -- a stale
  marker would then mis-attribute rather than merely mislead;
* every existing block in every marked unit needs a migration, and the migration
  runs through the same `--apply` path currently gated by two open defects.

## Prerequisites before this is worth starting

1. `docs\INBOX-shared-unit-empty-render-deletes-block.md` -- a narrow project
   emits a pure deletion over a marked unit's block when its own render is empty.
   Segments would make the blast radius larger, not smaller.
2. `docs\INBOX-document-qname-second-apply-nests-block-on-stale-anchor.md` --
   anchors go stale mid-apply. Any migration is a wide `--apply`.
3. `docs\superpowers\specs\2026-08-13-db-authority-and-freshness.md` -- still
   open and architectural; it owns whether reachability may cross into a sibling
   project's DB at all.

## Trigger to revisit

Any of: a shared unit's reference line becomes unreadably long in practice; a
stale entry on a shared unit is traced to a caller deleted in a sibling project
(the reaping cost coming due); or question 2 in
`docs\QUESTIONS-2026-08-13-autonomous-session.md` (`unused-public-symbol` on a
symbol used only by a sibling project) is answered in a way that needs per-project
reachability anyway.
