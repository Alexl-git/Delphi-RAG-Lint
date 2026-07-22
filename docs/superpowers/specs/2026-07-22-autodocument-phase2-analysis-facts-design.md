# Design: Auto-Document Phase 2 -- Analysis Facts (index-time facts layer)

- Date: 2026-07-22
- Status: Draft (design; needs a brainstorm/refinement pass before an implementation plan)
- Repo: `C:\Projects\Delphi-RAG-lint` (main)
- Depends on: Phase 1 (shipped v1.2.0-alpha) -- the managed `<!-- drag-lint:auto -->`
  block, `TDocFacts` / `TDocFactsBuilder`, `RenderFactsBlock`, and the return-case miner.
- Supersedes the "Phase 2 (deferred)" stub in
  `2026-07-21-whole-project-autodocument-phase1-design.md`.

## Motivation

Phase 1's facts are all **cheap index lookups** (callers/callees, overrides, overload set,
raises, deprecated, return cases). The user asked for a **richer** layer of *analysis* facts
that describe what a routine actually DOES:

1. **Reads / writes fields** -- which instance fields the routine reads vs. mutates.
2. **Returned-object ownership** -- does it return a freshly-constructed object the caller must
   free (escape), or a borrowed/owned reference?
3. **Complexity** -- cyclomatic complexity + body LOC (a "this is a big one" signal).
4. **DFM event wiring** -- which control/event a method is wired to as a handler (`Button1Click`
   -> `Button1.OnClick`), from the paired `.dfm`.
5. **SQL tables touched** -- for methods that run SQL (FireDAC/BDE), which tables they
   read/write, mined from the query text + the SQL index.
6. **Covered-by-tests** -- which DUnitX tests exercise this symbol (reverse call-edge from a
   `[Test]` method).

Each is a real *analysis* (dataflow / escape / CFG / cross-artifact join), not a single SELECT.

## The load-bearing architectural decision: compute at INDEX time, persist, SELECT at use time

The user's key question in Phase 1 was **"would hover slow down?"** Yes -- if these facts were
computed on demand (per `document`/hover call) they would each re-parse the body and walk a
CFG, making hover sluggish. So:

- **Compute during `drag-lint index`** (the file is already parsed into an AST there), and
  **persist** the results in a new `symbol_facts` table keyed by `symbol_id`.
- **At document / hover time**, the facts are a **cheap indexed SELECT** -- no re-analysis.
- BOTH consumers (autodoc `TDocFactsBuilder` AND the hover popup `BuildHoverModel`) read the
  same persisted rows, so the two surfaces stay consistent (as the Phase 1 return cases and the
  Phase 1.x `Returns:` fact line now already are) and hover stays fast.

This is the inverse of Phase 1's model (where facts are derived lazily from other index rows);
Phase 2 facts are **too expensive to derive lazily**, so they are materialized at index time.

### Schema

New table (migration, additive; bump schema version):

```
symbol_facts(
  symbol_id      INTEGER PRIMARY KEY REFERENCES symbols(id),
  reads_fields   TEXT,   -- CSV of field names read
  writes_fields  TEXT,   -- CSV of field names written
  returns_owner  TEXT,   -- '', 'new' (caller owns), 'borrowed', 'self'
  cyclomatic     INTEGER,
  body_loc       INTEGER,
  dfm_event      TEXT,   -- 'Button1.OnClick' or ''
  sql_reads      TEXT,   -- CSV of tables SELECTed
  sql_writes     TEXT,   -- CSV of tables INSERT/UPDATE/DELETEd
  covered_by     TEXT    -- CSV of test qnames (capped)
)
```

All columns nullable/absent-tolerant so a partial recompute (or an older index) degrades to
"fact absent -> line omitted", exactly like the opt-in Phase 1 facts.

## Per-fact analysis notes

- **Reads/writes fields** -- a bounded dataflow pass over the routine body: an identifier that
  resolves to an instance field of the owning class, classified as read (rvalue) vs write
  (lvalue / `:=` target / `var`-param). Reuse `src/analysis/DRagLint.Analysis.DataFlow.pas` +
  `.Flow.Lattices.pas` (already present). Cap the lists; mark uncertainty with the `?` convention.
- **Returned-object ownership** -- escape analysis on `Result`: `Result := TFoo.Create` with no
  intervening `Result.Free` / ownership transfer -> `new` (caller owns). `Result := FField` ->
  `borrowed`. `Result := Self` -> `self`. Conservative: emit only high-confidence verdicts.
- **Complexity** -- cyclomatic from the existing CFG (`src/analysis/DRagLint.Analysis.Cfg.pas`):
  1 + count of branch nodes. `body_loc` = `impl_end_line - impl_start_line`. Render only when
  above a configurable threshold (`docs.complexity_min`, default e.g. 10) so trivial routines
  stay lean.
- **DFM event wiring** -- during indexing a `.dfm` is already paired with its `.pas`
  (`PairDfmSiblings`); join a published method to the `On*` property that names it.
- **SQL tables touched** -- for a routine whose body builds SQL (string literals / `.SQL.Text`),
  extract table names via the existing SQL parser (`src/parser/DRagLint.Parser.Sql.pas`) and/or
  cross-reference the SQL index. Best-effort; skip dynamic SQL it can't parse.
- **Covered-by-tests** -- reverse call closure: a `[Test]`-attributed method (or a `*Test`/
  `Test*` unit) that transitively calls the symbol. Reuse the reverse-call-tree engine
  (`DRagLint.Report.RCallTree`). Cap + `(+N more)`.

## Rendering

Each fact is one omit-when-empty line in the managed block (Phase 1 convention), e.g.:

```
/// Reads: FName, FCount   Writes: FCount
/// Returns: new (caller owns)
/// Complexity: 14 (cyclomatic), 63 lines
/// Handles: Button1.OnClick
/// SQL: reads OPTRLIST, PDF_SCAN; writes PDF_SCAN
/// Covered by: TScanTest.TestAutoScan, TScanTest.TestForceRescan (+2 more)
```

Hover shows the same via `BuildHoverModel` reading `symbol_facts`. All config keys optional
under the manifest `docs` section, defaults chosen to stay lean.

## Phasing (suggested implementation order -- each independently shippable)

1. The `symbol_facts` table + index-time write hook + the read path in `TDocFactsBuilder` and
   `BuildHoverModel` (no facts yet -- just the plumbing + a reindex).
2. Complexity + body LOC (cheapest; CFG already exists).
3. Reads/writes fields (dataflow lattices already exist).
4. Covered-by-tests (reverse-call engine already exists).
5. Returned-object ownership (escape analysis -- the hardest; ship last).
6. DFM event wiring + SQL tables touched (cross-artifact joins).

## Risks / open questions (resolve in the brainstorm before planning)

- **Index cost** -- materializing these adds work to every `index` run. Measure; gate the most
  expensive (escape, SQL) behind a `docs.analysis` opt-in if they slow indexing materially.
- **Ownership analysis precision** -- escape analysis is easy to get wrong; prefer ABSENCE over a
  wrong "caller owns" (a wrong ownership fact could cause a real leak/double-free if trusted).
- **Staleness** -- `symbol_facts` must be invalidated with the symbol on reindex (same
  mtime/sha gate as `symbols`); a `document --apply` that shifts lines still needs the
  reindex-after step (the recurring stale-index trap).
- **Determinism** -- like all doc facts, output must be deterministic (no AI) and idempotent.

## Testing

- Per-fact fixtures under `tests/autodoc/` with known-answer analysis (a class with a field it
  reads and writes; a factory returning `TFoo.Create`; a 15-branch method; a `Button1Click`
  wired in a `.dfm`; a method running `SELECT ... FROM OPTRLIST`; a `[Test]` covering a target).
- An index-time test that the `symbol_facts` row is written + invalidated on reindex.
- Hover + document render the same facts from the same rows (consistency lock).
