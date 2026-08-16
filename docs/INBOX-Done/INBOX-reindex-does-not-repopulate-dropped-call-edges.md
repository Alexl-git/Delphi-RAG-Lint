> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# INBOX -- a reindex does not repopulate `call_edges` when the table was dropped/emptied

> **FIXED 2026-08-12.** `ISymbolStore.CallEdgesNeedRebuild` (call_edges empty
> while call-site refs exist) now forces the pass. The suggested fix below was
> right about the probe but wrong about where it goes: the incremental *scoping*
> was never reached, because the skip happens one level up in the CLI -- and at
> **three** sites, not one (`DoIndex`, `BuildPlanItem` for `index --all`, and
> `IndexDictionary`). Patching only `DoIndex` made the fixture test green while
> the real `index --all --only YADF` still skipped, which is what caught it.
>
> Verified beyond the test: YADF's live index had **0** call edges and no source
> change; after the fix a plain `index --all --only YADF` rebuilt **2,900** of
> them. That empty table is also the likely mechanism behind the long-standing
> "autodoc oscillates on YADF -- `Covered by:` flips across a reindex", since
> that fact is derived from `call_edges` and the table was sometimes populated
> and sometimes not.

Found 2026-08-12 by the battery runner `tests\callresolve\run_migrate_v13_to_v14.ps1`,
which is RED on branch `fix/lint-noise-round1`.

## Symptom

```
[PASS] AFTER: call_edges table EXISTS
[PASS] AFTER: idx_call_edges_target created
[PASS] AFTER: idx_call_edges_ref created
[FAIL] AFTER: call_edges POPULATED (> 0 rows) (rows=0)
[PASS] AFTER: call_edges has expected columns
[FAIL] find-callers --resolved exits 0 on migrated db
```

## What the test does

1. Builds a real (v14) index of a small fixture with the current exe.
2. Mutates it to look like a pre-D5 index: stamps `schema_version` back to 13 and
   **drops `call_edges` and its indexes**. The source files are untouched.
3. Re-indexes the SAME fixture into the SAME database and asserts that the schema
   migration recreates `call_edges` **and repopulates it**.

Step 3's schema migration works -- the table and both indexes come back. What does not
happen is the refill: `call_edges` ends up with 0 rows.

## Likely cause

The incremental call-target resolution shipped in `043d402`
("perf(index): resolve call targets incrementally -- 2,252s -> 17s on a 2 GB index").
It decides how much to re-resolve from what has **changed on disk**. Here nothing on
disk changed -- only the database was mutated -- so the incremental pass concludes there
is no work to do, and the emptied `call_edges` is never refilled.

That is the mirror image of the defect `9898982` fixed ("make the call-target rebuild
atomic -- an interrupted pass emptied call_edges"). That commit stopped an interruption
from emptying the table; this is about **noticing the table is empty and refilling it**.

## Why it matters beyond the test

Any database whose `call_edges` is empty or partial -- a pre-D5 index, a database left
behind by an interrupted run before `9898982`, or one restored from an older backup --
will stay broken across reindexes, because the only signal the incremental pass consults
is file mtime/content. `find-callers --resolved` then returns nothing on that database
and nothing errors, which is the silent-wrong-answer shape this project keeps hitting.

## Suggested fix

Gate the incremental path on a cheap sanity probe as well as on file changes: if
`call_edges` is empty while `refs` is not, fall back to the full rebuild. The same probe
would cover a schema migration that recreates the table.

## Not caused by the _D-RAG / ownership work

The test drives the engine with an explicit `--db`, so none of the manifest DB-path
derivation added on this branch is involved. Verified: today's commits touch
`DRagLint.Index.Manifest` (section DB path + `Save`), `DRagLint.Core.Model` (one
constant), `DRagLint.CLI` (selftests, `migrate-dbs`, the lint ownership filter),
`DRagLint.Project.OwnRoots` (new), `DRagLint.Index.Plan` (`ResolvePlan`'s DbPath only)
and the IDE plugin. None of them touch call resolution.

## Reproducing

```
pwsh -File tests\callresolve\run_migrate_v13_to_v14.ps1
```
