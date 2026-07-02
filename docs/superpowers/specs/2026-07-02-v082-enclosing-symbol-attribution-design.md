# v0.82 Design -- `enclosing_symbol_id` reference attribution + feature-envy + coupling retrofit

**Status:** approved design (2026-07-02). Next step: `writing-plans` -> SDD execution (fresh session after handoff).

## Goal
Add a persisted **enclosing-method attribution** to the reference index (`refs.enclosing_symbol_id`), then consume it
to ship `feature-envy`, retrofit the ref-based coupling metrics onto exact attribution, and land the smaller ready
items (CK `instability`, a first-cut `#4` interface/object mixing, and the two v0.81 review Minors).

## Resolved decisions (controller + user, 2026-07-02)
- **Scope: broad** -- foundation + all consumers + independents (user chose "Broad").
- **Attribution hook: per-file, in-memory in `IndexFile`** -- resolve each ref's innermost enclosing method by
  `impl_start_line..impl_end_line` containment against the file's just-inserted in-memory symbols; pass the resolved
  DB id to `UpsertReference`. No parser-walk plumbing, no whole-DB pass.
- **Backfill: NONE (explicit full reindex).** User will reindex all configured DBs once after the new indexer ships.
  Per-file resolution then keeps every index current. No migration-detection/backfill code.
- **Release: `v0.82.0-alpha`** (version + tag carry `-alpha` again -- schema changes are still on the table), published
  as a **full** GitHub release (`gh release --latest`, NOT `--prerelease`), win32+win64. (User: "continue calling
  releases alpha since we still can do schema changes" + "ful release".)

## Grounding (from the v0.82 recon -- exact anchors so the implementer does not re-derive)
- Table is **`refs`** (not `references`). Current DDL: `src/storage/DRagLint.Storage.Schema.pas:39-41`
  (`id, symbol_id, file_id, kind, name_text, start_line, start_col, end_line, end_col`). Indexes at `Schema.pas:48`.
- `SCHEMA_VERSION` const `Schema.pas:6` (=12); stamped at `SQLite.pas:399`, **never read/compared** (stamp only).
- `Migrate` `SQLite.pas:331-457`: flat idempotent `CREATE TABLE IF NOT EXISTS` DDL loop + hand-written
  `TryExec('ALTER TABLE ... ADD COLUMN ...')` for additive cols (`SQLite.pas:434-440`, the `impl_start_line` precedent).
- `refs.symbol_id` is a **vestigial target slot** -- parser sets it 0 (`Delphi13.pas:150`), no pass ever resolves it
  (`FindCallersByName` matches on `name_text`). DISTINCT from the new `enclosing_symbol_id`. Do not conflate.
- Indexing order: symbols inserted first with real ids via `IdxToId: TDictionary<Integer,Int64>`, refs second, same
  file transaction; `IdxToId` in scope during the refs loop -- `src/core/DRagLint.Core.Indexer.pas:223-244`.
- Impl body ranges stamped in-memory during parse by `SetRoutineImplRange` (`Delphi13.pas:735-756`, called ~`:1001`).
- Ref insert: `Indexer.pas:244` -> `TSQLiteSymbolStore.UpsertReference` `SQLite.pas:764-777`; prepared stmt `SQLite.pas:484-485`.
- Existing whole-DB resolve-pass precedent (shape reference only; we are NOT adding one): `ResolveUnitUseTargets`
  `SQLite.pas:2377`, `ResolveAncestry` `SQLite.pas:2495+`, both called from the index paths `CLI.pas:1610-1611` etc.
- String-literal enclosing-symbol resolution precedent (uses `FindContainingSymbol` on the DECLARATION span):
  `Indexer.pas:251-261`; `FindContainingSymbol` `SQLite.pas:1637-1649` / query `SQLite.pas:544` -- **NOTE: it queries
  `start_line/end_line` (decl span), which for a method is just its header, so it does NOT contain body call sites.**
  Our resolution must match against `impl_start_line/impl_end_line` for routine-kind symbols instead (new logic).
- `TReference` record: `src/core/DRagLint.Core.Model.pas:84-95` (fixed fields; add `EnclosingSymbolId: Int64`).
- Ref-reading store methods to populate the new field: `GetReferencesFromFile` `SQLite.pas:1227-1258`
  (**also fix its pre-existing gap: it never reads `end_line`/`end_col`**), `FindReferencesTo`, `FindCallersByName`.
- `ISymbolStore` `src/core/DRagLint.Core.Interfaces.pas` (`GetReferencesFromFile` ~:75).

---

## Section 1 -- `enclosing_symbol_id` capability (FOUNDATION; all other sections depend on it)
1. **Schema** (`Schema.pas`): add `enclosing_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL` to the `refs`
   `CREATE TABLE` block; add `CREATE INDEX IF NOT EXISTS idx_refs_enclosing ON refs(enclosing_symbol_id)`; bump
   `SCHEMA_VERSION` -> 13. (`SQLite.pas`): add `TryExec('ALTER TABLE refs ADD COLUMN enclosing_symbol_id INTEGER')`
   after the existing ALTER block (~`:440`) for existing DBs; extend the `refs` INSERT prepared stmt (`:484-485`) +
   `UpsertReference` (`:764-777`) to write the new param.
2. **Attribution** (`Indexer.pas` `IndexFile`, ~`:223-244`): after the symbols loop builds `IdxToId`, and while inserting
   refs, compute for each ref its innermost enclosing routine: among the file's in-memory `ParseRes.Symbols` of kind
   `skMethod/skFunction/skProcedure/skConstructor/skDestructor` with `ImplStartLine>0` whose `[ImplStartLine,ImplEndLine]`
   contains `Ref.StartLine`, pick the one with the LARGEST `ImplStartLine` (innermost / handles nested procs); map its
   array index -> DB id via `IdxToId`; set `Ref.EnclosingSymbolId`. Refs not inside any routine body -> 0/NULL. Keep it
   O(refs x routines) per file (fine at file scale) or pre-sort routines; do NOT add DB round-trips.
3. **Consumer** (`Model.pas`, `Interfaces.pas`, `SQLite.pas`): add `EnclosingSymbolId: Int64` to `TReference`; populate it
   in `GetReferencesFromFile` (and `FindReferencesTo`/`FindCallersByName`) with the NULL-guard idiom (`IsNull -> 0`).
   While editing `GetReferencesFromFile`, ALSO read `end_line`/`end_col` (pre-existing omission).
4. **Rollout (operational, post-build):** reindex every configured DB once (manifest `index --all` / per-DB) so
   `enclosing_symbol_id` is populated everywhere. Documented in BACKLOG + the release notes.
5. **Tests:** a store fixture asserting refs inside a method resolve to that method's id (and a nested-proc case resolves
   to the inner). Add a targeted unit/harness check via `check-ast --db` or a small store-fixture rule that surfaces the
   attribution, OR assert indirectly through feature-envy's fixture. No harness regressions (file 150 / store 14 /
   catalog 29 / flowengine 33 all still green).

## Section 2 -- `feature-envy` (category `refactoring`, `info`, OFF-by-default)
Per method M (from `enclosing_symbol_id`) in class C: count M's references split into own-class (target member declared
in C) vs each other class X (target member declared in X). Resolve a ref's target class via the same name->declaring-class
maps CBO already builds (`ClassMetrics.pas` `ByName`/member lookup); ambiguous names (member declared in >1 class) are
**skipped** (documented FP-avoidance). Flag M when `max_X foreign[X] > own[C]` (strictly greater; a method that touches a foreign class more than its own)
AND `foreign[X] >= minAccess` (a floor to kill tiny/noise methods; default `minAccess = 3`, config-tunable). Message
names M, the envied class X, and the counts. Lives in
`ClassMetrics.pas` (per-class/per-method) reachable from `DoLintAll`; `DefDisabled` wiring (OFF). Store fixture +
src/ FP-sanity (report count; stays OFF regardless). **KEY LIMITATION (document):** target-class resolution is name-based
(no expression type inference), so precision is bounded; enclosing attribution is exact but the own/foreign split is
heuristic -> OFF-by-default.

## Section 3 -- CBO / RFC / fan-in / fan-out retrofit onto exact attribution
Replace the line-range `InAnyMethodBody(AInfo, R.StartLine)` attribution in `ComputeCBO`/`ComputeRFC` (and thus the
CBO-derived `fan-out`, and `ComputeAllFanIn`) with an exact test: the ref's `EnclosingSymbolId` is one of the class's
method ids. More precise for nested procs / overlapping spans; cheaper (no per-ref span scan). **LCOM4 is EXCLUDED** --
it is an AST identifier re-walk (`ComputeLCOM4`/`CollectDefProcNodes`), not ref-attribution, so `enclosing_symbol_id`
does not replace it; leave it unchanged. **GUARDRAIL:** the existing CK store fixtures + a src/ FP-sanity diff must show
**no change in findings** (this touches ON-by-default metrics); if any metric's retrofit changes results, investigate --
if the change is a genuine correctness improvement, update the fixture with justification; if it is a regression, DEFER
that metric's retrofit within v0.82 and document. Do this AFTER Section 1 lands and DBs are reindexed (retrofit reads a
populated column).

## Section 4 -- CK `instability` (category `metrics`, `info`, OFF-by-default)
`I = Ce/(Ca+Ce)` per class, where Ce = CBO/fan-out and Ca = fan-in. Independent of the extension (pure arithmetic on the
existing metrics). Because I is a 0..1 ratio, flag with a **range** shape, not a `> threshold` count: flag only when I is
near an extreme (e.g. `I >= highThreshold` "unstable: depends on many, nothing depends on it") AND `Ca+Ce >= noiseFloor`
(ignore trivially-coupled classes). Config keys for `highThreshold` (e.g. 0.8) + `noiseFloor` (e.g. 5). Emit `info`.
Store fixture + OFF wiring.

## Section 5 -- first-cut `#4` interface/object mixing (`info`, OFF; category = reuse `freeandnil-on-interface`'s category, confirm at impl)
Needs instance aliasing, which the codebase lacks -> attempt only a NARROW, low-FP same-routine slice: an object created
(`X := TFoo.Create`), assigned to an interface-typed variable in the same routine (`I := X` / `I := X as ISomething`),
AND `X` is manually `Free`d/`FreeAndNil`'d in that routine -> the ARC/manual dual-handle double-free. Pure-AST,
same-routine, reusing `freeandnil-on-interface`'s `TypeMap`/`TypeTextIsInterface`. **If the first cut cannot reach an
acceptable FP rate in src/ sanity, SHIP NOTHING for #4 and document the deferral** (do not ship a noisy rule). OFF-by-default
either way.

## Section 6 -- v0.81 review Minors (cleanups)
1. `default-encoding-io` `ArgsHaveNoEncoding` (`DeadCodeChecks.pas`): skip `literalString` named children in the
   `TEncoding` scan so a filename literal containing "TEncoding" no longer falsely suppresses.
2. Exit code from survivors not raw findings: `FinalizeAndOutput`/`ExitCodeFor` -- when `--fail-on` is unset, derive the
   default exit from the post-`ShouldKeep` survivor set, consistently for both `DoLintAll` and `DoLintProject`, so a bare
   command whose only matches were suppressed OFF rules exits 0 and prints "0 finding(s)" consistently.

---

## Task decomposition (for writing-plans -- dependency order)
1. **Section 1** (foundation): schema + attribution + consumer + fixture. MUST land + DBs reindexed before 2/3.
2. **Section 6** (Minors): independent, cheap -- can run in parallel with 1 (different files).
3. **Section 2** (feature-envy): depends on 1.
4. **Section 3** (retrofit): depends on 1 + a reindexed DB; guardrailed no-regression.
5. **Section 4** (instability): depends on fan-in/fan-out (already shipped); independent of 1.
6. **Section 5** (#4 first cut): independent (pure-AST); attempt-or-defer.
7. **Release**: v0.82.0-alpha full release + reindex-all rollout note + docs/MEMORY.

## Testing / rollout
- Harness baselines to keep green: file 150, store 14 (grows with new fixtures), catalog 29, flowengine 33.
- New store fixtures: enclosing-attribution, feature-envy, instability (+ #4 if shipped). CK retrofit reuses existing CK
  fixtures as the regression guard.
- OFF-by-default rules: catalog `False` + `DefDisabled` in every emitting CLI path (verify at runtime, per the v0.80/v0.81 lesson).
- Rollout: after the new exe is built, reindex all configured DBs once.

## Open risks
- feature-envy precision is bounded by name-based target-class resolution -> ships OFF; FP-sanity will size the noise.
- CBO/RFC retrofit touches ON metrics -> the no-regression guardrail is mandatory; be ready to defer a metric's retrofit.
- #4 may not reach an acceptable FP rate -> defer-if-noisy is an accepted outcome.
