# Auto-Document Phase 2 -- Analysis Facts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six *analysis* facts (complexity, reads/writes fields, covered-by-tests, DFM event wiring, SQL tables touched, returned-object ownership) to the auto-document + hover facts, computed once at index time and persisted so hover stays fast.

**Architecture:** A new `symbol_facts` SQLite table, keyed by `symbol_id`, is materialized during `drag-lint index` by a new `TSymbolFactsAnalyzer` (always-on, every DB). `TDocFactsBuilder` (doc) and `BuildHoverModel` (hover) read the persisted row -- a cheap indexed SELECT, no re-analysis. Each fact renders as one omit-when-empty line in the managed `<!-- drag-lint:auto -->` block, mirrored in the hover popup.

**Tech Stack:** Delphi 13 (Studio 37), Win64 CLI, SQLite (built-in wrapper `DRagLint.Storage.SQLite`), tree-sitter parse via the existing indexer. Tests are PowerShell runners under `tests/autodoc/` driving the built exe.

## Global Constraints

- All `.pas`/`.dfm`: strict 7-bit ASCII, CRLF, DocInsight on new public surface (per `C:\Projects\CLAUDE.md`).
- Deterministic, NO AI, idempotent output (Phase 1 discipline). Absence over a wrong fact.
- Build: `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` + log (EXIT:0, no `[dcc] Error`). Deploy copies to `third_party/dll-win64/drag-lint.exe`.
- No sqlite3 on PATH -> inspect DBs with `C:\Python314\python` (stdlib sqlite3, open `?mode=ro`).
- Facts render inside the existing `<!-- drag-lint:auto BEGIN/END -->` region; hand prose preserved.
- Uncertainty follows the Phase 1 `?`-suffix convention; lists capped with ` (+N more)`.
- Config lives in the manifest `docs` section (`third_party/dll-win64/drag-lint.json`); new keys optional with in-code defaults.

---

## File structure

- Create `src/doc/DRagLint.Doc.SymbolFacts.pas` -- the `TSymbolFacts` record (persisted analysis facts) + `TSymbolFactsAnalyzer` (computes all six from a parsed unit + store) + serialize/deserialize helpers. One unit, one responsibility (the analysis layer).
- Modify `src/storage/DRagLint.Storage.Schema.pas` -- add the `symbol_facts` table DDL + schema-version bump + migration.
- Modify `src/storage/DRagLint.Storage.SQLite.pas` + `src/core/DRagLint.Core.Interfaces.pas` -- `ISymbolStore.GetSymbolFacts(ASymbolId): TSymbolFacts` and `.PutSymbolFacts(const AFacts: TSymbolFacts)`.
- Modify `src/core/DRagLint.Core.Indexer.pas` -- after a file's symbols are written, run `TSymbolFactsAnalyzer` per routine symbol and `PutSymbolFacts`; invalidated with the file's symbols on reindex.
- Modify `src/doc/DRagLint.Doc.Facts.pas` -- `TDocFacts` gains the six fields; `TDocFactsBuilder.Build` reads them via `GetSymbolFacts`.
- Modify `src/doc/DRagLint.Doc.Regions.pas` -- `RenderFactsBlock` renders the six omit-when-empty lines.
- Modify `src/cli/DRagLint.Hover.Renderer.pas` -- `BuildHoverModel` (or the hover markdown) surfaces the same facts.
- Create `tests/autodoc/run_doc_phase2_*.ps1` + `tests/autodoc/fixtures/docp2/*.pas` -- one runner per fact + a plumbing/consistency runner.

Each analysis reuses an existing engine (read it before implementing the task):
`src/analysis/DRagLint.Analysis.Cfg.pas` (complexity), `.DataFlow.pas` + `.Flow.Lattices.pas` (reads/writes), `src/report/DRagLint.Report.RCallTree.pas` (covered-by-tests), `src/core/DRagLint.Project.Members.pas` `PairDfmSiblings` + `src/parser/DRagLint.Parser.DFM.pas` (DFM wiring), `src/parser/DRagLint.Parser.Sql.pas` (SQL tables).

---

## Task 1: `symbol_facts` table + storage read/write plumbing

**Files:**
- Create: `src/doc/DRagLint.Doc.SymbolFacts.pas`
- Modify: `src/storage/DRagLint.Storage.Schema.pas` (DDL + version bump), `src/core/DRagLint.Core.Interfaces.pas` (ISymbolStore methods), `src/storage/DRagLint.Storage.SQLite.pas` (impl)
- Test: `tests/autodoc/run_doc_p2_store.ps1`

**Interfaces:**
- Produces: the `TSymbolFacts` record and `ISymbolStore.GetSymbolFacts` / `.PutSymbolFacts` used by every later task.

```pascal
// DRagLint.Doc.SymbolFacts.pas
type
  TSymbolFacts = record
    SymbolId    : Int64;
    ReadsFields : string;   // CSV of field names read
    WritesFields: string;   // CSV of field names written
    ReturnsOwner: string;   // '', 'new', 'borrowed', 'self'
    Cyclomatic  : Integer;  // 0 = not computed
    BodyLoc     : Integer;
    DfmEvent    : string;   // 'Button1.OnClick' or ''
    SqlReads    : string;   // CSV of tables read
    SqlWrites   : string;   // CSV of tables written
    CoveredBy   : string;   // CSV of test qnames (capped)
    Present     : Boolean;  // False when no row -> renderer omits all lines
  end;
```

- [ ] **Step 1: Write the failing test** `tests/autodoc/run_doc_p2_store.ps1`: index a 1-function fixture, then a tiny hidden self-test verb `doc-facts-selftest` (added in Step 3) that `PutSymbolFacts` a known record and `GetSymbolFacts` it back, printing `RT=<ReturnsOwner> CYC=<n>`. Assert round-trip equality.
- [ ] **Step 2: Run it, verify FAIL** (`doc-facts-selftest` unknown verb). Run: `& $exe doc-facts-selftest --db <db>`. Expected: exit 2 / unknown command.
- [ ] **Step 3: Implement** the record + serialize helpers; add `symbol_facts(symbol_id INTEGER PRIMARY KEY REFERENCES symbols(id), reads_fields TEXT, writes_fields TEXT, returns_owner TEXT, cyclomatic INTEGER, body_loc INTEGER, dfm_event TEXT, sql_reads TEXT, sql_writes TEXT, covered_by TEXT)` to the schema; bump `SCHEMA_VERSION` + add a `CREATE TABLE IF NOT EXISTS` migration; implement `Get/PutSymbolFacts` (UPSERT by symbol_id; Get returns `Present=False` when absent); add the `doc-facts-selftest` verb.
- [ ] **Step 4: Build + run test, verify PASS.** Build via the recipe; Run the runner. Expected: round-trip PASS.
- [ ] **Step 5: Commit** `feat(doc): symbol_facts table + Get/PutSymbolFacts plumbing (Phase 2 T1)`.

## Task 2: index-time analyzer hook + invalidation

**Files:**
- Modify: `src/doc/DRagLint.Doc.SymbolFacts.pas` (`TSymbolFactsAnalyzer.Analyze(const ASym: TSymbol; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts` -- returns an EMPTY-but-Present record for now), `src/core/DRagLint.Core.Indexer.pas` (call it per routine symbol after symbols are persisted, then `PutSymbolFacts`)
- Test: `tests/autodoc/run_doc_p2_index.ps1`

**Interfaces:**
- Consumes: Task 1's `TSymbolFacts` + `PutSymbolFacts`.
- Produces: `TSymbolFactsAnalyzer.Analyze` (later tasks fill in each fact); a `symbol_facts` row written for every routine symbol at index time, invalidated (row deleted) when the file's symbols are cleared on reindex.

- [ ] **Step 1: Write the failing test** `run_doc_p2_index.ps1`: index a fixture with one function; via Python read `symbol_facts` and assert exactly one row exists for that symbol (Present). Edit the file (add a line), reindex, assert the row still maps to the (re-created) symbol id and stale rows are gone.
- [ ] **Step 2: Run, verify FAIL** (no rows written yet).
- [ ] **Step 3: Implement** `Analyze` (empty Present record); in the indexer, after the file's symbols are written, for each routine-like symbol (`skFunction/skProcedure/skMethod/skConstructor/skDestructor`) compute + `PutSymbolFacts`; on the file-clear path (where old symbols are deleted on reindex) delete their `symbol_facts` rows (ON DELETE CASCADE via the FK, or explicit delete).
- [ ] **Step 4: Build + run, verify PASS.**
- [ ] **Step 5: Commit** `feat(index): materialize symbol_facts per routine at index time (Phase 2 T2)`.

## Task 3: Complexity (cyclomatic + body LOC)

**Files:** Modify `DRagLint.Doc.SymbolFacts.pas` (fill `Cyclomatic`/`BodyLoc` in `Analyze`, reusing `src/analysis/DRagLint.Analysis.Cfg.pas`), `DRagLint.Doc.Facts.pas` (`TDocFacts.Cyclomatic/BodyLoc` + read in `Build`), `DRagLint.Doc.Regions.pas` (render). Config: `docs.complexity_min` (default 10). Test: `tests/autodoc/run_doc_p2_complexity.ps1` + fixture `fixtures/docp2/complexity.pas`.

**Interfaces:** Consumes Task 2's `Analyze`. Produces the `Complexity:` render line.

- [ ] **Step 1: Write the failing test.** Fixture: a function with ~12 branches (if/for/case/and/or) + a trivial 1-branch function. `index -> document --unit --apply`; assert the complex fn's block has `Complexity: <n> (cyclomatic), <m> lines` with `n >= 10`, and the trivial fn has NO Complexity line (below `complexity_min`).
- [ ] **Step 2: Run, verify FAIL** (no Complexity line).
- [ ] **Step 3: Implement.** Read `Analysis.Cfg` first; compute cyclomatic = 1 + branch-node count over the routine body CFG; `BodyLoc = impl_end_line - impl_start_line`. Store in `symbol_facts`. `TDocFacts` reads them; `RenderFactsBlock` emits `Complexity: N (cyclomatic), M lines` only when `Cyclomatic >= LoadDocComplexityMin` (mirror `LoadDocMaxReturnCases`; default 10).
- [ ] **Step 4: Build + REINDEX the fixture + run, verify PASS.** (Analysis facts are index-time -- the test must reindex after building so rows exist.)
- [ ] **Step 5: Commit** `feat(doc): Complexity fact -- cyclomatic + LOC (Phase 2 T3)`.

## Task 4: Reads / writes fields

**Files:** Modify `DRagLint.Doc.SymbolFacts.pas` (fill `ReadsFields`/`WritesFields`, reuse `DRagLint.Analysis.DataFlow` + `.Flow.Lattices`), `DRagLint.Doc.Facts.pas`, `DRagLint.Doc.Regions.pas`. Test: `run_doc_p2_fields.ps1` + `fixtures/docp2/fields.pas`.

**Interfaces:** Produces the `Reads:` / `Writes:` render line.

- [ ] **Step 1: Write the failing test.** Fixture: a class `TCounter` with fields `FCount`, `FName`; a method that reads `FName` and writes `FCount` (`Inc(FCount)` / `FCount := 0`). Assert the method's block has `Reads: FName` and `Writes: FCount` (order-insensitive; a field both read+written appears in both).
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.** Read `Analysis.DataFlow` first. For the routine body, resolve each identifier that is an instance field of the owning class; classify write when it is a `:=` LHS, a `var`/`out` arg, or an `Inc/Dec` target; else read. Cap each list (e.g. 8) with ` (+N more)`. Store CSV. Render `Reads: a, b   Writes: c` (omit an empty side; omit the whole line when both empty).
- [ ] **Step 4: Build + reindex + run, verify PASS.**
- [ ] **Step 5: Commit** `feat(doc): Reads/Writes fields fact via dataflow (Phase 2 T4)`.

## Task 5: Covered-by-tests

**Files:** Modify `DRagLint.Doc.SymbolFacts.pas` (fill `CoveredBy`, reuse `DRagLint.Report.RCallTree` reverse closure), `DRagLint.Doc.Facts.pas`, `DRagLint.Doc.Regions.pas`. Test: `run_doc_p2_covered.ps1` + `fixtures/docp2/covered.pas`.

**Interfaces:** Produces the `Covered by:` render line.

- [ ] **Step 1: Write the failing test.** Fixture: a function `Target`; a `[Test] procedure TestTarget` that calls `Target`; a non-test caller. Assert `Target`'s block has `Covered by: <unit>.TestTarget` and does NOT list the non-test caller.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.** Read `Report.RCallTree` first. Reverse call-closure from the symbol; keep callers that are (a) attributed `[Test]`/`[TestCase]` OR (b) in a `*Test`/`Test.*` unit. Cap (e.g. 5) + ` (+N more)`. Store CSV of qnames. Render `Covered by: A, B (+N more)`.
- [ ] **Step 4: Build + reindex + run, verify PASS.**
- [ ] **Step 5: Commit** `feat(doc): Covered-by-tests fact via reverse call closure (Phase 2 T5)`.

## Task 6: DFM event wiring

**Files:** Modify `DRagLint.Doc.SymbolFacts.pas` (fill `DfmEvent`, reuse `PairDfmSiblings` + `DRagLint.Parser.DFM`), `DRagLint.Doc.Facts.pas`, `DRagLint.Doc.Regions.pas`. Test: `run_doc_p2_dfm.ps1` + `fixtures/docp2/dfmwire/` (a `.pas` + paired `.dfm`).

**Interfaces:** Produces the `Handles:` render line.

- [ ] **Step 1: Write the failing test.** Fixture: `uForm.pas` with `procedure Button1Click(Sender: TObject);` + `uForm.dfm` with `object Button1: TButton ... OnClick = Button1Click`. Assert `Button1Click`'s block has `Handles: Button1.OnClick`.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.** Read `Project.Members.PairDfmSiblings` + `Parser.DFM` first. For a published method, scan the paired `.dfm` for an `On* = <MethodName>` assignment; record `<ObjectName>.<EventProp>`. Store; render `Handles: Button1.OnClick`.
- [ ] **Step 4: Build + reindex + run, verify PASS.**
- [ ] **Step 5: Commit** `feat(doc): DFM event-wiring fact (Phase 2 T6)`.

## Task 7: SQL tables touched

**Files:** Modify `DRagLint.Doc.SymbolFacts.pas` (fill `SqlReads`/`SqlWrites`, reuse `DRagLint.Parser.Sql`), `DRagLint.Doc.Facts.pas`, `DRagLint.Doc.Regions.pas`. Test: `run_doc_p2_sql.ps1` + `fixtures/docp2/sql.pas`.

**Interfaces:** Produces the `SQL:` render line.

- [ ] **Step 1: Write the failing test.** Fixture: a method building `'SELECT * FROM OPTRLIST WHERE ...'` and `'UPDATE PDF_SCAN SET ...'` via string literals. Assert `SQL: reads OPTRLIST; writes PDF_SCAN`.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.** Read `Parser.Sql` first. Collect string literals in the body that look like SQL; parse table names (FROM/JOIN -> reads; INSERT INTO/UPDATE/DELETE FROM -> writes). Best-effort; skip un-parsable/dynamic SQL (absence over wrong). Store CSVs; render `SQL: reads A, B; writes C`.
- [ ] **Step 4: Build + reindex + run, verify PASS.**
- [ ] **Step 5: Commit** `feat(doc): SQL-tables-touched fact (Phase 2 T7)`.

## Task 8: Returned-object ownership (escape analysis) -- conservative

**Files:** Modify `DRagLint.Doc.SymbolFacts.pas` (fill `ReturnsOwner`), `DRagLint.Doc.Facts.pas`, `DRagLint.Doc.Regions.pas`. Test: `run_doc_p2_owner.ps1` + `fixtures/docp2/owner.pas`.

**Interfaces:** Produces the `Returns: <owner>` render line (distinct from the Phase 1.x mined `Returns:` cases -- see Step 3).

- [ ] **Step 1: Write the failing test.** Fixture: `function MakeIt: TFoo; begin Result := TFoo.Create; end;` (-> `new`), `function GetIt: TFoo; begin Result := FFoo; end;` (-> `borrowed`), `function Me: TFoo; begin Result := Self as TFoo; end;` (-> `self`), and `function Amb: TFoo; begin if X then Result := TFoo.Create else Result := FFoo; end;` (-> NO ownership line, ambiguous). Assert each.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.** Conservative single-pass over `Result :=` sites: ALL sites `TType.Create` with no intervening ownership transfer -> `new (caller owns)`; ALL sites a field/param -> `borrowed`; `Self` -> `self`; mixed/anything else -> omit (absence over wrong). Render as a separate `Owns returned: new (caller owns)` line so it never collides with the mined return-cases `Returns:` line.
- [ ] **Step 4: Build + reindex + run, verify PASS.**
- [ ] **Step 5: Commit** `feat(doc): returned-object ownership fact -- conservative escape analysis (Phase 2 T8)`.

## Task 9: Hover surfaces the analysis facts + doc/hover consistency lock

**Files:** Modify `src/cli/DRagLint.Hover.Renderer.pas` (`BuildHoverModel` reads `symbol_facts` and the markdown renders the lines), `src/lsp/DRagLint.LSP.Server.pas` + `src/cli/DRagLint.CLI.pas` DoHover (pass the store so hover can read facts). Test: `run_doc_p2_hover.ps1`.

**Interfaces:** Consumes `GetSymbolFacts`. Produces hover markdown lines matching the doc block.

- [ ] **Step 1: Write the failing test.** Reuse a fixture from T3-T8; `hover --qname <complex fn> --format md` must show `Complexity:` (and the others where present), matching the documented block.
- [ ] **Step 2: Run, verify FAIL.**
- [ ] **Step 3: Implement.** `BuildHoverModel`/the markdown renderer reads `GetSymbolFacts` for the symbol and appends the same omit-when-empty lines. Keep one shared formatter (a `TSymbolFacts -> TArray<string>` render helper in `DRagLint.Doc.SymbolFacts.pas` used by BOTH `RenderFactsBlock` and hover) so the two surfaces cannot drift.
- [ ] **Step 4: Build + reindex + run, verify PASS.**
- [ ] **Step 5: Commit** `feat(hover): surface Phase 2 analysis facts + shared formatter (Phase 2 T9)`.

## Task 10: Library-reindex benchmark + docs + CHANGELOG

**Files:** Modify `docs/AI-USAGE.md` (Docs section: the six facts + `docs.complexity_min`), `CHANGELOG.md` (Unreleased), the manifest schema note. Add a benchmark note.

- [ ] **Step 1: Benchmark.** Time a full `index --all --only <one library section>` before (current `main`) vs after this branch; record the delta in the plan's PR description / CHANGELOG. If the regression is large (say >2x), FILE a follow-up for the opt-in gate (do NOT block this increment -- always-on was the decision).
- [ ] **Step 2: Docs.** Document each fact + the config key + that facts are index-time (reindex after `document --apply`).
- [ ] **Step 3: Full battery.** Run the whole `tests/autodoc/` + `tests/autotest/run_hover_*` battery green.
- [ ] **Step 4: Commit** `docs(autodoc): Phase 2 analysis facts + CHANGELOG + benchmark`.

---

## Self-review notes

- **Spec coverage:** T1-T2 = the index-time facts layer (schema §Schema + §"compute at INDEX time"); T3-T8 = the six facts (§"Per-fact analysis notes", cheap->hard order per Decision 1); T9 = the doc+hover consistency (§Rendering + the "same rows" architecture); T10 = the benchmark risk (§Risks) + docs + testing (§Testing). All spec sections map to a task.
- **Always-on (Decision 2):** T2 wires the analyzer unconditionally in the indexer -- no flag. T10 benchmarks the cost.
- **Ownership conservatism (Decision 3):** T8 emits only unanimous `new`/`borrowed`/`self`; mixed -> omit.
- **Idempotency:** facts are index-time; each fact test reindexes after build, and `document --apply` output stays idempotent because the rendered lines are deterministic from the persisted row.
- **Naming consistency:** `TSymbolFacts` / `GetSymbolFacts` / `PutSymbolFacts` / `TSymbolFactsAnalyzer.Analyze` used consistently T1->T9; the shared `TSymbolFacts -> TArray<string>` formatter (T9) is the single render source for doc + hover.
