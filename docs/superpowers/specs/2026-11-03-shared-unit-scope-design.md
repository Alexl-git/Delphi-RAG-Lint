# SHARED-UNIT-SCOPE -- judge a shared unit by the UNION of its projects

Status: implemented on lane/141-rules (1.41). Owner ruling 2026-11-02: UNION.
Source: `docs\INBOX-unused-public-shared-unit-cross-project.md`.

## Problem

`unused-public-symbol` and `unused-global` decide "nothing uses this" from ONE project DB.
A unit compiled into several projects (`DRagLint.Core.ControlChannel.pas` is in both
`drag-lint.dproj` and `dclDragLintWizard.dproj`) is judged differently per DB: the heartbeat
API is dead in the plugin DB and alive in the CLI DB, so no `dl:ok` satisfies both
(`review-marker-unused` fires in the DB where the finding does not).

Before this change only a unit carrying a `dl:shared A, B` header was treated as shared, and
the two rules disagreed about it: unused-public-symbol consulted the named siblings (and still
reported when one could not be opened), unused-global skipped every interface symbol of it.

## Rule

A symbol of a shared unit is reported unused only when NO project that lists the unit uses it.

## How the listing projects are found

The listing set of a unit path P, for the run's own DB D:

1. Every name on P's `dl:shared` header (the declared relationship, as before).
2. Every manifest project section whose DB holds a `files` row for P
   (`FindFileIdByPath(P) > 0`). A project index is the compile closure of its `.dproj`, so a
   files row IS "this project lists the unit". This is what finds ControlChannel, which has no
   header.

D itself is dropped from the set (identity: same `project_tag` and `indexed_at_unix` meta).
The section names come from the same manifest + plan the existing sibling resolver reads
(`--config` wins), through a new lister callback the CLI hands to `TProjectLintRules.Run`.

## Cost

Nothing is opened unless a rule already has a candidate finding in some unit. On the first
one the lister resolves the plan once and each section DB is opened read-only at most once
per run (the resolver's cache); membership is one indexed lookup per (DB, unit), cached.
On this box that is ~30 read-only opens per lint run that has a candidate, measured in
milliseconds each; a run with no candidate opens nothing. The freshness probe
(`ProbeIndexFreshness`, one stat per indexed file) runs only for DBs that LIST the unit, once
per DB per run.

## Missing or stale listing DB -- conservative

* A header-named project whose DB is not configured, will not open, or is stale: the verdict
  is UNDECIDED and the finding is NOT reported. An unopened or out-of-date index is not
  evidence of absence. (Before: unused-public-symbol reported with "check there" advice.)
* A manifest section whose DB will not open is IGNORED for membership: nothing says it lists
  the unit, and treating every broken DB on the box as a listing project would silence the
  rule everywhere.
* No lister and no resolver (a bare `lint-all --db X`, tests): only the header is known;
  a header-shared unit is UNDECIDED (not reported); an unshared unit is judged as before.

## Per rule

* unused-public-symbol (unit-level routine): used elsewhere = `FindCallersByName(name) > 0`
  in a listing DB (the predicate the sibling check already used). Unused in all listing DBs
  -> reported, message names the projects checked. Own-unit tier: unchanged (skip shared).
* unused-global (interface symbol): used elsewhere = a reference naming the symbol, not on
  its own declaration line, in a listing DB (`FindRefsNamingInFiles`). Unused everywhere ->
  reported; was always skipped before.
* review-marker-unused: lives in `DRagLint.CLI.pas` (cli lane) and is NOT changed. It becomes
  consistent because the two rules now give the same verdict in every listing DB. Known
  limit: in an UNDECIDED run a marker for the suppressed finding reads unused. Follow-up for
  the cli lane: skip review-marker-unused on a marker whose rule declined as UNDECIDED.

## CLI change (minimal, named)

`DRagLint.CLI.pas`: one new function `MakeSiblingProjectLister` beside
`MakeSiblingStoreResolver` (same manifest load), passed as the new last argument of the three
`TProjectLintRules.Run` calls. No flag, no output change.

## Tests

`tests\autotest\run_shared_unit_scope.ps1`: one shared unit listed by two `.dproj` projects
(no header), manifest with both sections.
* RED on 1.40: linting P1 reports `Beat` (used only in P2) as unused-public-symbol and
  `GShared` (named only in P2) is silently skipped by unused-global... the guard asserts
  the union verdict both ways (used-elsewhere suppressed; dead-everywhere still reported),
  and that deleting P2's DB makes the verdict UNDECIDED (no finding).
