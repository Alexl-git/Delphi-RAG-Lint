# RESUME -- 2026-08-13 (session 16)

Supersedes `RESUME-2026-08-13c-shared-unit-docs-and-menu.md`.

Plan: `docs/superpowers/plans/2026-08-13-shared-unit-docs-and-menu.md`.
**Tasks 1-4 DONE. Task 7 (LoopZero) RUN and CONVERGED.** Tasks 5-6 (IDE menu)
untouched and unblocked.

## Status

`main` = **`8abcc3e`**, **13 unpushed**. Battery **269/269**.
Pushing needs `git config http.postBuffer 524288000` + `http.version HTTP/1.1`.

`C:\Projects\YADF` on `autodoc-phaseC` at **`bc4bb02`**, clean apart from a
pre-existing `YADFOT.res` and untracked reports.

## THE RESULT -- a stable fixed point, the first ever for this family

Three consecutive full rounds (document each project, reindex all three,
measure) produce IDENTICAL counts. Previously every round rewrote the others.

| Project | before | after | doc-drift |
|---|---|---|---|
| YADF | 8 | **12** | 0 -> 4 |
| YADFOT | 50 | **35** | 17 -> **0** |
| YADFSetup | 44 | **24** | 20 -> **0** |
| total | 102 | **71** | |

**YADF's own count RISES by 4.** Those 4 plus YADFOT's 2 all sit on inbound
lines carrying `(+N more)`. The merge refuses truncated lists (a window onto a
list is not the list), so they keep the byte compare and churn. **12 such lines
remain** across the shared units -- bounded, stable, and the ONLY doc-drift left.

To finish those 6: raise `docs.max_callers` (manifest, currently 5) above the
shared units' real caller counts so nothing truncates, OR teach the merge to
reconcile truncated lists by count. **Owner decision, not taken.**

## What made it work

Three engine changes, in the order they were needed:

1. **`e6d0b8b`** Task 3 -- `dl:shared` marker, comment-state scanner, CLI.
2. **`57b0be4`** Task 4 -- checker forgives + writer merges = union across
   projects. Neither half works alone.
3. **`8abcc3e`** -- **the one that actually unblocked LoopZero.**
   `OpenExtraStores` called `ResolveConsumerDbs`, which auto-resolves the
   WHOLE MANIFEST when no `--db` is given, so `document --project X` searched
   every index on the machine (library DB included) for name-based fact matches.
   Its own comment always said "every --db the user passed"; the code never did.
   Now explicit-`--db` only. Explicit multi-`--db` (ORM3 COMMON) unchanged.

Plus `7eaff08`: the merge had parsed whole `Remarks` instead of the block
body and welded `AUTO_END` into a fact line in YADF.Tokens.pas.

## Beliefs this session CORRECTED

* The junk facts (`dxRibbon`, `TestCachedUpdates.dpr`) written off as "stale
  TEXT from the union-DB era, which the per-project split already prevents from
  recurring" were **not stale text. They REGENERATE**, from the fan-out. The
  per-project split never touched them.
* The plan's Architecture paragraph was wrong in three ways (writer IS changed;
  `certain` is one-way only; neither `Used in units:` nor `<seealso>` was
  scoped as written). Corrections kept visible in the plan, not rewritten away.

## Traps paid for

* **A fixture whose block ends with `Pure` cannot catch a slice overrun** --
  `Pure` IS a label, so the parse always stopped in time. 20/20 green while the
  engine corrupted real source. Any parser test needs the construct LAST.
* **`JoinRefs` emits `' ?'` only on a MIXED list** -- absence proves nothing.
* **`Used in units:` renders via `JoinEsc`, not `JoinRefs`** -- no
  confidence marker at all, so an uncertainty screen there is vacuous.
* **`lint-all --db` scopes to ownRoots** -- a scratch fixture outside the
  project folder reports a silent zero. Declare `_D-RAG\drag-lint-project.json`.
* **doc-drift reads the doc from the STORE** -- `document --apply` without a
  reindex makes every drift assertion pass vacuously.
* **The engine writes `(loaded defaults from ...)` to STDERR** -- merging
  streams in a test interleaves it into `--json` and fails every read assertion
  while the engine is correct.
* Battery ~14 min; background it.

## Not done

1. **The last 6 doc-drift** -- the `(+N more)` decision above.
2. **The rest of the 71**: `try-except-swallowed` (16 YADFOT), `local-var-casing`
   (7 each, AUTOFIXABLE and not yet run), `object-leak`,
   `used-before-assignment`, `unused-public-symbol`, `unit-too-large`.
   Only `doc-drift` and `local-var-casing` are autofixable.
3. **Tasks 5-6**, the IDE menu items. Need a LIVE IDE, BPLs built with RAD Studio
   CLOSED, both platforms.
4. **`TSharedUnit.IsShared` reads the file on every call** -- no cache.
5. **Item D**, `concat-in-loop` 15 on DataCopy. Separate plan.
6. `C:\Projects\DelphiAST` collateral damage from `aeeeee6` (2 modified + 2
   `.pas.bak`). Separate repo, never asked for.