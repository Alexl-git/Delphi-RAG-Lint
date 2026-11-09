# Scoped calls pass with an attached library store (wave 149 lane IC)

Date: 2026-11-09. Owner of the row: lane IC (resolver 1.23.0 bump). Source rows: 148 OM item 2,
148 IX items 8 / 15 / "149 rows".

## Problem

`ResolveCallTargets` (DRagLint.Storage.SQLite.pas) refuses the scoped pass whenever ANY extra
store is attached:

    DeclineWhy := if Length(AExtraStores) > 0 then 'extra stores are attached, ...'

so on a project that resolves against its platform library (`libraryResolve: true`, or
`--library-db`), a 1-file incremental reindex re-runs the WHOLE-DB calls pass. OM measured
359 s for a 1-file trailing-comment reindex of drag-lint.dproj, 305 s of it in the calls pass.
The IDE reindexes on save, so this is the save latency.

## Why the decline was there

The scoped soundness argument (ScopedResolveIsSound header, points 1-5) proves: every ref whose
answer CHANGED is in "refs in FScopeFiles + refs named in FScopeNames" (+ the two type-name
widenings). It ranges over the symbols THIS database records. A library store is a second symbol
set the argument says nothing about, so the old code declined.

## What a ref's answer depends on when a library is attached

The cross-DB rung (`ResolveExternally`) runs LAST: a ref binds externally only when every local
rung declined. Its inputs are (a) the ref's own row and its file's scope (uses, locals): changes
there put the file in FScopeFiles; (b) whether a LOCAL candidate of that name exists: name-keyed,
covered by FScopeNames (points 2, 3); (c) the receiver's TYPE, resolved through local
declarations first and the library second; (d) the library's own content.

* (d) is constant iff the library did not change since the edges in this DB were written.
* (c) is the indirect channel of point 4. With a library attached it has a LIBRARY-SIDE half
  the existing widenings cannot see: `WidenScopeThroughAddedTypes` /
  `WidenScopeThroughRemovedTypes` collect member names of the added/withdrawn type's LOCAL
  declarations and LOCAL bound ancestors. Example: a run adds a local `TFoo` that shadows the
  library's `TFoo`; untouched `X.LibMethod` (X: TFoo) bound to the library's `TFoo.LibMethod`
  before, binds nowhere after, and `libmethod` is in no scoped set. Symmetric for a withdrawn
  local type that un-shadows a library type, and for an added local class whose ancestor is a
  library class (the ancestor's members are not local symbols).

## Options

A. Keep declining (today). Correct, 305 s per save.
B. Scope whenever a library is attached and the library is unchanged. UNSOUND by the (c)
   example above.
C. Scope when the library is unchanged AND this run neither added nor withdrew a declared type
   name (FScopeTypesBefore = FScopeTypesAfter as sets); whole DB otherwise. Under type-set
   equality point 4's indirect channel provably cannot fire (that is exactly the pre-2026-08-28
   gate), so the library-side half of (c) is closed too, and (d) is closed by the identity test.
D. C, plus extend both widenings to walk library ancestors / library declarations of the
   added/withdrawn names. Sound in principle, but it reads the library during scope building and
   needs its own channel fixtures; more code in a hot routine for the rarer shape.

## Chosen: C

It covers the case the row is about -- the ordinary save / `--recompile` shape (edit a body, a
comment, a statement; class declarations unchanged) -- with the smallest argument: two gates, both
conservative. D is a 150 row if type-adding saves on library projects turn out to matter.

### "The library did not change": the identity test

The pass already records, at its end and in the same transaction as its edges, which stores it
consulted: `schema_meta.external_stores` = JSON array of `{path, indexer_fingerprint,
resolver_fingerprint, indexed_at_unix}` per store (WriteExternalStores). `indexed_at_unix` is
re-stamped by CommitIndexerFingerprint after every completed index walk of the library, and both
fingerprints move with any engine change. So:

    scoped with stores  <=>  ExternalStoresJson(AExtraStores) = stored external_stores
                             AND type-name sets equal
                             AND every existing no-store condition holds (ScopedResolveDeclineReason)

The comparison is decided at the top of the pass (before WriteExternalStores rewrites the key).
The row text suggested `library_fingerprint_seen` (the CLI marker). Not used, because (1) it is
the library's indexer fingerprint only -- a library re-indexed by the same engine keeps it; (2) it
is written only when the marker state changes (IX item 8), and (3) it lives in the CLI, while
external_stores is written by the pass itself, atomically with the edges it describes. Item 8 is
still fixed (the marker is refreshed while bound), for readers of `info`.

### The history hole, and its fix

A scoped pass run WITHOUT stores (library pending / rebuilding during a re-parse, or not named)
keeps the old external_stores key today (its rows outside the scope keep their external names),
but the refs it re-resolved lost their external edges. A later run with the same library would
then see an equal key and scope -- leaving those refs without the edges a whole pass writes.
Fix: such a pass rewrites the key with `"partial":true` on every element. Readers that only test
the key for non-empty (PlanLibraryResolve) are unaffected; the identity test fails, so the next
library run goes whole and rewrites a clean key.

### Operator text

Every decline names its reason on the existing `calls ... whole database because %s` line:
* `extra stores are attached and this database has no record of the library its edges were bound against (no external_stores)`
* `extra stores are attached and the library changed since this database's edges were bound (external_stores differs)`
* `extra stores are attached and this run changed the set of declared type names (N before, M after); a library type can be shadowed or un-shadowed`

## Acceptance (row): identity, then speed

Corpus: drag-lint.dproj (this worktree) indexed with `--library-db library-Win64.sqlite`.
1. RED: base engine, 1-file trailing-comment incremental -> `whole database because extra stores
   are attached`, calls pass time recorded.
2. GREEN: lane build, same edit -> `starting SCOPED pass`.
3. Identity: copy of the GREEN DB, `index --project ... --resolve-only` (clear + whole) on the
   copy; every resolver-written table compared row-for-row (call_edges, member_accesses,
   ref_types, ref_receivers, refs.receiver_text/external_target/symbol_id, external_stores):
   0 differences. A speed-up that changes rows is reported, not merged.
4. Guards (fixture, library = a scratch index of a tiny unit): scoped with an unchanged library;
   whole after the library is re-indexed (positive control for the identity test); whole after a
   run that adds a type name; whole after a scoped no-store pass (the history hole).

## Assumptions the owner can reverse

* Option C, not D (type-name-changing saves on library projects stay whole-DB).
* external_stores, not library_fingerprint_seen, is the library identity.
* A library index KILLED after committing changed files but before CommitIndexerFingerprint keeps
  its old stamps; its readiness gate reports it as before. Such a library already gives
  inconsistent answers to every reader; this pass inherits that, it does not widen it.
* The pre-existing field-type channel (a field's declared type changes from one existing class to
  another, no type name added or removed, a ref `X.F.M` elsewhere) is a property of the no-library
  scoped argument and is neither introduced nor closed here.
