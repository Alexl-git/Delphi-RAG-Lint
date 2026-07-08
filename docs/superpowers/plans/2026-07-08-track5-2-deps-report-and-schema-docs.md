# Track 5.2 -- Third-Party Dependency Report + Index Schema Docs -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `deps-report` CLI verb (a third-party dependency rollup over the index's uses-graph) plus index-schema documentation (a `docs/INDEX-SCHEMA.md` reference + a `schema` dump verb), then cut the v0.95 release.

**Architecture:** A pure engine unit (`src/report/DRagLint.Report.Deps.pas`) walks the existing `unit_uses` + `files` tables to classify each used unit as project vs external (unresolved OR library-path), groups externals (path-root then name-prefix), and computes per-external rollup + shortest path -- returning plain records with NO I/O. Thin CLI glue (`DoDepsReport`) opens stores + renders text/json/csv, mirroring the existing `DoUsesReport`. The `schema` verb reads live `sqlite_master`/`PRAGMA` for a self-documenting dump. All headless-testable.

**Tech Stack:** Delphi 13 (RAD Studio 37), FireDAC + SQLite (`ISymbolStore`/`TSQLiteSymbolStore`), Win64 CLI. PowerShell `run_*.ps1` autotests. No new index schema (reads existing tables).

## Global Constraints

- **Encoding:** all `.pas` files strict 7-bit ASCII, CRLF, no BOM, no Unicode. (CLAUDE.md)
- **DocInsight (CDD):** every NEW public type/function gets a `///` `<summary>` (+ `<param>`/`<returns>`/`<remarks>` as apt). (CLAUDE.md)
- **TDD:** the deps-report engine and the schema verb are headless-testable -- write the failing `run_*.ps1` first, then implement to green. Reuse `tests/autotest/run_doc_returns.ps1` conventions ($Exe absolutize BEFORE any Push-Location; `Check($name,$ok,$detail)` helper; exit 0 PASS / 1 FAIL / 2 fatal).
- **Build recipe:** use the `delphi-build` skill. CLI = `src/cli/drag-lint.dproj`, Win64, Debug -> `src/cli/Win64/Debug/drag-lint.exe`. `BUILD_EXITCODE=0`, no `[dcc64 Error]`. After a green build that changed the exe, redeploy `src/cli/Win64/Debug/drag-lint.exe` -> `third_party/dll-win64/drag-lint.exe` (the canonical deployed CLI) before running tests that default to the deployed exe -- OR point the test's `-Exe` at the fresh debug build (the run_doc_returns default is the debug build; keep that).
- **Commit cadence:** one source commit per task; the test in its task's commit or a paired commit. The v0.95 release commit (Task 7) = CLI.pas VERSION + CHANGELOG + BACKLOG only (v0.94 convention); no BPL in the release commit.
- **No index schema change** unless a task explicitly finds it trivial and safe (the spec leans AGAINST it -- a schema bump = v15->v16 + migration, out of scope). Default: document the project/external boundary, don't add a column.
- **External classification (exact, from the spec):** a used unit is EXTERNAL when its `unit_uses.target_file_id` is unresolved (NULL/-1 -- not indexed) OR it resolves to a `files` row whose path is a library path (`IsLibraryPath`: lowercased path contains `\embarcadero\`, `\program files`, or `\dcc\`). Otherwise it is a PROJECT unit.
- **Determinism:** every list/report is sorted deterministically (never rely on hash-map iteration order). Two identical runs must be byte-identical.
- **Trailer:** end every commit message with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## Existing code this plan consumes (verbatim anchors)

```pascal
// src/cli/DRagLint.CLI.pas
function DoUsesReport(const AArgs: TArgs): Integer;   // :5432 -- the TEMPLATE. Its
//   TUsesEdge{UnitName,UnitNameNorm,TargetFileId(-1=external),Section},
//   TFileMeta{Path,Stem,StoreIndex,FileId}, TBfsQueueItem{...,Via,External},
//   OpenStores (multi --db), ComputeStem -- REUSE these shapes.
function IsLibraryPath(const P: string): Boolean;     // :1973 (local in find-unit).
//   L:=LowerCase(P); Result:= (Pos('\embarcadero\',L)>0) or (Pos('\program files',L)>0) or (Pos('\dcc\',L)>0);
//   Promote to a shared spot OR copy into the report unit (prefer a shared helper).
// TArgs (:~110-175): has DbPaths, DbPath, Depth(default 3), IncludeExternal,
//   AllSources, Name, Format, Output. ADD: Edges: Boolean (--edges).
// Arg parse (:~575): '--include-external'/'--all-sources' pattern -- ADD '--edges'.

// src/storage/DRagLint.Storage.SQLite.pas
//   SCHEMA_VERSION const (currently 15). schema_meta(key,value) holds 'schema_version'.
//   unit_uses(file_id, unit_name, unit_name_norm, section, in_path, target_file_id,
//             start_line, start_col, end_line, end_col). target_file_id NULL = external.
//   files(id, path, ...). ISymbolStore is the query interface.
// ISymbolStore: opens a db; has query methods + the FireDAC connection behind it.
//   For raw sqlite_master/PRAGMA (Task 4), add a small read-only pass-through OR
//   open the file with a fresh read-only FireDAC query in DoSchema.
```

Read `DoUsesReport` in full before Task 1 -- it is the working reference for multi-store opening, the `unit_uses` walk, stem-based file resolution, and BFS. The new engine mirrors its data handling but returns records instead of writing CSV.

---

## Task 1: deps-report engine -- classification + rollup (pure, unit-testable via CLI)

Build the pure engine that reads `unit_uses`, classifies project vs external, groups externals, and produces the rollup + edge records. No printing.

**Files:**
- Create: `src/report/DRagLint.Report.Deps.pas`
- Reference (read only): `src/cli/DRagLint.CLI.pas` `DoUsesReport` (:5432), `IsLibraryPath` (:1973); `src/storage/DRagLint.Storage.SQLite.pas` (`unit_uses`/`files`, `ISymbolStore`).

**Interfaces:**
- Produces:
  ```pascal
  type
    TDepsGroup = (dgRTL, dgDevExpress, dgSpring4D, dgFireDAC, dgOther, dgUnknown);
    // dgUnknown = unresolved/not-indexed with no name match; dgOther = resolved
    // library file that matched no known group.

    TDepsExternal = record
      UnitName    : string;            // verbatim external unit name
      Group       : TDepsGroup;
      Resolved    : Boolean;           // True = resolved to a library file; False = not indexed
      UsedByCount : Integer;           // FULL distinct-project-unit count (NOT capped)
      UsedBy      : TArray<string>;    // importing project units, sorted asc, capped (see AMaxList)
      UsedByMore  : Integer;           // count beyond the cap (0 when not capped)
      ShortestPath: string;            // 'ProjUnit > ... > ExternalUnit' ('>'-joined)
      Sections    : TArray<string>;    // distinct sections it's used in ('interface'/'implementation')
    end;

    TDepsEdge = record
      SourceUnit  : string;            // project unit
      ExternalUnit: string;
      Group       : TDepsGroup;
      Section     : string;
      Resolved    : Boolean;
    end;

    TDepsGroupCount = record Group: TDepsGroup; UnitCount, ProjectUnitCount: Integer; end;

    TDepsSummary = record
      ExternalUnitCount : Integer;             // distinct external units
      ExternalEdgeCount : Integer;             // distinct (project->external) edges
      UnresolvedCount   : Integer;             // externals not in the index
      GroupCounts       : TArray<TDepsGroupCount>;
    end;

    TDepsReport = record
      Summary   : TDepsSummary;
      Externals : TArray<TDepsExternal>;       // sorted: group asc, then UsedByCount desc, then name asc
      Edges     : TArray<TDepsEdge>;           // sorted: source asc, then external asc
    end;

    TDepsOptions = record
      Depth      : Integer;   // BFS depth for shortest path (default 3)
      AllSources : Boolean;   // consider every db's files as project sources (else first db only)
      NamePattern: string;    // restrict project-unit sources (substring, ci); '' = all
      MaxList    : Integer;   // cap for UsedBy lists (default 20)
    end;

  /// <summary>Builds the third-party dependency report from the index's uses-graph.
  /// Borrows AStores (does not open/free them). Classifies each used unit as project
  /// vs external (unresolved OR library-path), groups externals, and computes the
  /// per-external rollup + the flat edge list + summary. No I/O.</summary>
  function BuildDepsReport(const AStores: TArray<ISymbolStore>;
    const AOpts: TDepsOptions): TDepsReport;

  /// <summary>True when APath is a Delphi library/RTL/3rd-party path (lowercased
  /// path contains '\embarcadero\', '\program files', or '\dcc\'). The canonical
  /// project-vs-library path test; shared with find-unit.</summary>
  function IsLibraryPath(const APath: string): Boolean;

  /// <summary>Classifies an external unit into a display group by resolved library
  /// path root first, then unit-name prefix (cx*/dx*/dxBar*->DevExpress; Spring.*->
  /// Spring4D; FireDAC.*->FireDAC; System/Winapi/Vcl/FMX/Data/Soap/Xml->RTL).</summary>
  function ClassifyDepsGroup(const AUnitName, AResolvedPath: string; AResolved: Boolean): TDepsGroup;

  /// <summary>Lowercase group label for output ('RTL','DevExpress','Spring4D',
  /// 'FireDAC','other','unknown').</summary>
  function DepsGroupStr(AGroup: TDepsGroup): string;
  ```

- [ ] **Step 1: Read the reference + write the failing test fixture + test**

Read `DoUsesReport` (`DRagLint.CLI.pas:5432`) fully. Create the test `tests/autotest/run_deps_report.ps1` (see Task 3 for the full test -- but write a FIRST minimal version now that will fail because the verb doesn't exist yet). Minimal RED assertion: `& $Exe deps-report --db <db> --json` exits non-zero / prints "unknown command" today.
Actually: defer the full test to Task 3 (the verb doesn't exist until Task 2). For THIS task, the engine has no CLI surface yet, so its RED/GREEN is proven via the Task 3 test once the verb is wired. Mark this step: "engine is exercised by Task 3's test; Task 1 delivers the unit + a compile gate."

- [ ] **Step 2: Write the engine unit**

Create `src/report/DRagLint.Report.Deps.pas` implementing the interface above:
- `IsLibraryPath`: exact logic from `CLI.pas:1973`.
- `ClassifyDepsGroup`: if `AResolved` and `AResolvedPath<>''`, match the path (contains `\embarcadero\` or `\dcc\` and a `lib`/`bin`/`dcp` segment -> dgRTL; contains a devexpress/`\dev express`/`cx`-lib marker -> dgDevExpress; `spring` -> dgSpring4D) then fall through to name-prefix. Name-prefix (also the only signal for unresolved): lowercased unit name starts with `cx`/`dx` -> dgDevExpress; starts with `spring.` -> dgSpring4D; starts with `firedac.` -> dgFireDAC; starts with `system.`/`winapi.`/`vcl.`/`fmx.`/`data.`/`soap.`/`xml.`/`web.` -> dgRTL; resolved-but-unmatched -> dgOther; unresolved-unmatched -> dgUnknown.
- `BuildDepsReport`:
  1. Build the global file map (stem -> {path, storeIndex, fileId}) across `AStores` (mirror `DoUsesReport`'s AllFiles/StemToGlobal). A "project source" file = in the first store (or any store when `AllSources`), NOT a library path, matching `NamePattern` if set.
  2. Walk `unit_uses` for every project-source file. For each edge: resolve `target_file_id` -> a file (via the store) -> its path. Classify EXTERNAL when `target_file_id` is NULL/unresolved OR the resolved path `IsLibraryPath`. Skip project-to-project edges (those are not external deps).
  3. Accumulate: per external unit -> distinct set of importing project units, distinct sections, resolved flag, group. Record each (project->external) edge for the flat list.
  4. Shortest path: for each external unit, BFS from project sources over `unit_uses` up to `Depth`; the direct edge is depth 1 (always exists since the unit only appears if imported). Emit the `'>'`-joined chain of the shortest.
  5. Build `Summary` (distinct external units, distinct edges, unresolved count, per-group counts).
  6. Sort: Externals by (group asc, UsedByCount desc, name asc); Edges by (source asc, external asc); UsedBy within each external by name asc, capped at `MaxList` with `UsedByMore` = overflow.
- DocInsight on every public type/function.

- [ ] **Step 3: Add the unit to the CLI project + build**

Add `..\report\DRagLint.Report.Deps.pas` to `src/cli/drag-lint.dproj` `<DCCReference>` (mirror how a `src/project` or `src/core` unit is listed) AND to `drag-lint.dpr`'s `uses` if the CLI uses it directly (it will, in Task 2 -- but adding the DCCReference now lets it compile). Build the CLI Win64 (delphi-build). Expected: `Build succeeded`, 0 errors. (The unit isn't called yet; this proves it compiles.)

- [ ] **Step 4: Commit**

```bash
git add src/report/DRagLint.Report.Deps.pas src/cli/drag-lint.dproj
git commit -m "feat(deps-report): pure dependency-report engine (classify project vs external, group, rollup)"
```

---

## Task 2: Wire the `deps-report` CLI verb

Add `DoDepsReport` glue + the `--edges` flag + verb registration + renderers (text/json/csv).

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (add `DoDepsReport`; add `Edges: Boolean` to `TArgs`; parse `--edges`; register the verb in dispatch + usage banner; `uses` the new unit).

**Interfaces:**
- Consumes: `BuildDepsReport`/`TDepsReport`/`TDepsOptions`/`DepsGroupStr` from Task 1.
- Produces: the `deps-report` verb.

- [ ] **Step 1: Add `--edges` to TArgs + arg parse**

Add `Edges: Boolean;` to the `TArgs` record (near `IncludeExternal`). In the arg-parse chain (near `:575`, the `'--include-external'` branch), add `else if A = '--edges' then Result.Edges := True`.

- [ ] **Step 2: Write `DoDepsReport`**

```pascal
/// <summary>drag-lint deps-report: third-party dependency rollup over the index
/// uses-graph. Rollup by default; --edges for the flat (project->external) list.
/// Formats: text|json|csv. Reuses the uses-report multi-store opening.</summary>
function DoDepsReport(const AArgs: TArgs): Integer;
```
- Open stores exactly like `DoUsesReport.OpenStores` (multi `--db`; error "deps-report: need at least one --db" -> Exit 2 if none).
- Build `TDepsOptions` from AArgs (Depth default 3; AllSources; NamePattern:=AArgs.Name; MaxList:=20).
- `Rep := BuildDepsReport(Stores, Opts);`
- Render by `AArgs.Format` (default 'text'):
  - **text (rollup):** group headers (`DepsGroupStr`), then each external `unit  (used by N)  [resolved|not-indexed]` and its shortest path; capped UsedBy with `(+K more)`; end with the summary lines. **text (--edges):** aligned `source -> external  [group]  [section]`.
  - **json:** `{ "schema": "deps-report/1", "summary": {...}, "externals":[...] }` or, with `--edges`, `{..., "edges":[...] }`. Use `System.JSON`.
  - **csv:** rollup rows `unit,group,resolved,used_by_count,shortest_path` (UsedBy joined with `|` in a trailing column if desired); `--edges` rows `source_unit,external_unit,group,section,resolved`.
- `--output <file>` writes to the file (TFile.WriteAllText, ANSI) else stdout. Free the stores in a finally.
- Return 0 on success.

- [ ] **Step 3: Register the verb**

In the command dispatch (where `uses-report`/`impact`/`callgraph` are routed), add the `deps-report` branch calling `DoDepsReport`. Add a usage-banner line next to the `uses-report` line (`:350`):
```
Writeln('  drag-lint deps-report --db <file.sqlite> [--db ...] [--depth N] [--edges] [--all-sources] [--name <pat>] [--format text|json|csv] [--output <file>]   (third-party dependency rollup)');
```
Add `DRagLint.Report.Deps` to the CLI unit's `uses`.

- [ ] **Step 4: Build + smoke**

Build CLI Win64 (delphi-build), 0 errors. Redeploy `src/cli/Win64/Debug/drag-lint.exe` -> `third_party/dll-win64/drag-lint.exe`. Quick manual smoke: `drag-lint deps-report --db <any real index> --format json | head` prints a summary+externals (no crash).

- [ ] **Step 5: Commit**

```bash
git add src/cli/DRagLint.CLI.pas
git commit -m "feat(deps-report): CLI verb (rollup default + --edges; text/json/csv; multi --db)"
```

---

## Task 3: deps-report headless test (RED -> GREEN with teeth)

**Files:**
- Create/finish: `tests/autotest/run_deps_report.ps1`

**Interfaces:** consumes the built `drag-lint.exe` `deps-report` verb.

- [ ] **Step 1: Write the test with a fixture that has all three unit kinds**

`run_deps_report.ps1` (follow run_doc_returns conventions: absolutize `$Exe`, `Check` helper, exit codes). Build a fixture in a temp dir:
- `projmain.pas` (a project unit) with `uses ProjHelper, NotIndexedLib, System.SysUtils;` in the interface.
- `projhelper.pas` (a project unit, resolved, NOT a library path -> must NOT appear as external).
- Do NOT create a file for `NotIndexedLib` -> it stays unresolved/external (dgUnknown, resolved=false).
- For an indexed-but-library case: create `libunit.pas` and index it via a path the exe will see as a library path -- EASIEST: put it under a temp subdir literally containing `dcc` (e.g. `$work\dcc\libunit.pas`) so `IsLibraryPath` (`\dcc\`) fires; `projmain` also `uses LibUnit`. (If placing under a `\dcc\` dir is awkward in the harness, use a subdir named to contain `\program files`... not creatable; `\dcc\` is the reliable one -- create `$work\dcc\` and index it.)
- Index the whole `$work` into a temp DB (`$Exe index $work --db $db`). Run `$Exe deps-report --db $db --json` from a neutral CWD.
- Assert (parse the JSON):
  - `NotIndexedLib` appears in externals, `resolved=false`, group `unknown`.
  - `LibUnit` appears in externals, `resolved=true` (it's indexed but under `\dcc\`).
  - `System.SysUtils` appears in externals, group `RTL` (name-prefix `system.`).
  - `ProjHelper` does NOT appear in externals (it's a resolved non-library project unit).
  - `used_by_count` for each external >= 1 and matches the fixture (projmain imports all three).
  - shortest_path for a direct import is `projmain > <external>` (depth 1).
  - `--edges` run emits flat rows including `projmain -> NotIndexedLib`.
  - `--csv` run: header/columns present; a determinism check -- run `--json` twice, assert byte-identical.
- Run against the CURRENT exe FIRST (before Task 2 is built into the deployed exe) to capture RED (verb missing / assertions fail). Then after Tasks 1-2 build, GREEN.

- [ ] **Step 2: Run RED then GREEN**

RED: on an exe without the verb -> fails. GREEN (after the Task 2 build+deploy): `pwsh -File tests/autotest/run_deps_report.ps1` -> PASS. Capture both in the report.

- [ ] **Step 3: No regression**

Run `tests/autotest/run_doc_returns.ps1` + any uses-report-adjacent test -> still PASS (deps-report is additive; uses-report untouched).

- [ ] **Step 4: Commit**

```bash
git add tests/autotest/run_deps_report.ps1
git commit -m "test(deps-report): project-vs-external classification + grouping + shortest-path (headless)"
```

---

## Task 4: `schema` dump verb (self-documenting live schema)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (add `DoSchema`; register `schema` verb + usage line).
- (Optional) Modify: `src/storage/DRagLint.Storage.SQLite.pas` only if a tiny read-only pragma pass-through is cleaner than a fresh read-only query in DoSchema. Prefer a self-contained read-only FireDAC query in DoSchema -- do NOT change the store interface if avoidable.

**Interfaces:**
- Produces: `drag-lint schema --db PATH [--json]`.

- [ ] **Step 1: Write the failing test**

`tests/autotest/run_schema.ps1`: index a tiny fixture into a temp DB; run `$Exe schema --db $db --json`; assert (a) `schema_version` present and > 0; (b) the core tables present in the dump: `files`, `symbols`, `refs`, `unit_uses`, `schema_meta` (and `type_ancestors`, `type_helpers`); (c) `--json` parses; (d) a plain `schema --db $db` (text) run exits 0 and prints a table list + row counts. Run vs current exe -> RED (verb missing).

- [ ] **Step 2: Write `DoSchema`**

```pascal
/// <summary>drag-lint schema: dumps the LIVE index schema of --db -- schema_version,
/// each table with its columns (PRAGMA table_info) + row count. --json emits a
/// machine-readable structure so other tools can introspect the index. Read-only.</summary>
function DoSchema(const AArgs: TArgs): Integer;
```
- Require `--db` (Exit 2 with a usage line if missing; if multiple `--db`, use the first).
- Open the SQLite file READ-ONLY (a fresh FireDAC `TFDConnection`/query, or via the store's connection). Read:
  - `SELECT value FROM schema_meta WHERE key='schema_version'` (0/absent if missing).
  - `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name` -> the table list.
  - For each table: `PRAGMA table_info(<t>)` -> columns (name, type); `SELECT COUNT(*) FROM <t>` -> row count. (Guard table names -- they come from sqlite_master so they're safe, but build the SQL with the name inline only after confirming it matches `^[A-Za-z_][A-Za-z0-9_]*$`.)
- text: `schema_version: N`, then per table `<table> (<rowcount> rows): col1 TYPE, col2 TYPE, ...`. json: `{ "schema_version": N, "tables": [ { "name": "...", "row_count": N, "columns": [ {"name","type"} ] } ] }`.
- Return 0.

- [ ] **Step 3: Register + build + deploy**

Register the `schema` verb in dispatch + a usage-banner line. Build CLI Win64 (0 err), redeploy the exe. Run `run_schema.ps1` -> GREEN.

- [ ] **Step 4: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_schema.ps1
git commit -m "feat(schema): live index-schema dump verb (schema_version + tables + columns + row counts; --json)"
```

---

## Task 5: `docs/INDEX-SCHEMA.md` -- the index reference for external consumers

**Files:**
- Create: `docs/INDEX-SCHEMA.md`

**Interfaces:** none (docs). Verify every claim against `DRagLint.Storage.SQLite.pas` + a live DB (use the `schema` verb from Task 4 against a real index: `drag-lint schema --db C:\Projects\DB\ORM3\drag-lint.sqlite --json`).

- [ ] **Step 1: Author the doc (verified against the live schema)**

Write `docs/INDEX-SCHEMA.md` covering:
- Purpose ("consume the drag-lint SQLite index from another tool"), the schema version (from `SCHEMA_VERSION` / the `schema` verb -- state the current number), and the stability contract (tables stable within a schema version; check `schema_meta.schema_version` first; use `drag-lint schema --json` to introspect).
- A section per core table (from the `schema` verb output + the DDL): `files`, `symbols` (kind/kind_text, visibility, signature, impl-span), `refs`, `unit_uses` (**call out `target_file_id`: NULL/unresolved = the unit is not indexed; resolved = a `files` row exists**), `type_ancestors`, `type_helpers`, `call_edges`, `params`/`local_vars`, `schema_meta`, and the FTS text tables (name them; note they back `query --text`). For each: what it holds + the key columns + how they join.
- **"Project vs external" section (the user's ask):** state the rule explicitly -- a used unit is "in the project" when it resolves to a `files` row whose path is NOT a library path (`\embarcadero\`/`\program files`/`\dcc\`); external = unresolved `target_file_id` OR a resolved library path. Point at `drag-lint deps-report` (Task 2) as the ready-made consumer that applies this rule, and note the `schema` verb for programmatic introspection.
- Keep it clean ASCII.

- [ ] **Step 2: Cross-check against a live DB**

Run `drag-lint schema --db C:\Projects\DB\ORM3\drag-lint.sqlite --json` (or any real index) and reconcile the doc's table/column list with the actual output. Fix any mismatch. (If a table in the live DB isn't documented, add it; if the doc names a column that isn't there, correct it.)

- [ ] **Step 3: Commit**

```bash
git add docs/INDEX-SCHEMA.md
git commit -m "docs: INDEX-SCHEMA.md -- index database reference for external consumers (project-vs-external boundary)"
```

---

## Task 6: Docs mentions (AI-USAGE / README) for the two new verbs

**Files:**
- Modify: `docs/AI-USAGE.md`, `README.md` (short lines; verify against the shipped verbs).

- [ ] **Step 1: Add the verb mentions**

- `docs/AI-USAGE.md`: add `deps-report` (third-party dependency rollup; `--edges`; text/json/csv) and `schema` (introspect the index) to the query/report verb list, each one line with the flags. Point at `docs/INDEX-SCHEMA.md` for consuming the index.
- `README.md`: a line under the CLI/features section mentioning the dependency report + the published index-schema doc (so external tools discover it).
- Clean ASCII.

- [ ] **Step 2: Commit**

```bash
git add docs/AI-USAGE.md README.md
git commit -m "docs: mention deps-report + schema verbs + INDEX-SCHEMA in AI-USAGE/README"
```

---

## Task 7: Cut the v0.95 release (autonomous -- user pre-authorized)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (VERSION `0.94.0-alpha` -> `0.95.0-alpha`), `CHANGELOG` (if present; else the release notes), `docs/lint/BACKLOG.md` (LATEST resume).

- [ ] **Step 1: Bump VERSION + CHANGELOG + BACKLOG**

Change `VERSION = '0.94.0-alpha';` (`CLI.pas:6`) to `'0.95.0-alpha'`. Add a CHANGELOG entry (find the CHANGELOG file used by prior releases -- `git show v0.94.0-alpha --stat` reveals it) summarizing: deps-report verb, schema verb, INDEX-SCHEMA.md. Update `docs/lint/BACKLOG.md` LATEST block (v0.95 shipped: Track 5.2 + schema docs).

- [ ] **Step 2: Build the RELEASE CLI (Win64 + Win32) + verify version**

Build `src/cli/drag-lint.dproj` Win64 **Release** (and Win32 Release, matching the prior release's zips). Run `drag-lint --version` -> `0.95.0-alpha`. Run the full battery (`run_deps_report`, `run_schema`, `run_doc_returns`, `run_manifest`) against the fresh exe -> all PASS.

- [ ] **Step 3: Commit the release commit, tag, push**

```bash
git add src/cli/DRagLint.CLI.pas <CHANGELOG> docs/lint/BACKLOG.md
git commit -m "release: v0.95.0-alpha -- deps-report + schema verbs + INDEX-SCHEMA docs"
git tag v0.95.0-alpha
git push origin main
git push origin v0.95.0-alpha
```

- [ ] **Step 4: Build the release zips + create the GH release**

Mirror the v0.94 release packaging (inspect `git show v0.94.0-alpha` + any `pack`/release script). Zip the Win64 + Win32 CLI exes (CLI-only; no BPL, per convention). Create the GitHub release:
```bash
gh release create v0.95.0-alpha --title "v0.95.0-alpha" --notes-file <notes> --latest <win64.zip> <win32.zip>
```
Confirm it's Latest, not draft/prerelease-blocked as the prior ones (`isPrerelease=false`, `--latest`).

- [ ] **Step 5: Report**

Report the release URL + the branch state. (No further push needed.)

---

## Final verification (before/at release)

- [ ] `run_deps_report.ps1` + `run_schema.ps1` PASS; `run_doc_returns.ps1` + `run_manifest.ps1` still PASS (no regression).
- [ ] Both CLI builds (Debug during dev, Release for the ship) = 0 errors; `--version` = 0.95.0-alpha.
- [ ] `docs/INDEX-SCHEMA.md` reconciled against a live DB (Task 5 Step 2).
- [ ] Encoding clean on every touched `.pas`; determinism check in run_deps_report passes.
- [ ] GH release v0.95.0-alpha is Latest with the CLI zips; tag pushed; `origin/main` synced.

## Notes for the executor

- **deps-report is a REPORT over shipped data** -- it adds NO index schema and does NOT modify `uses-report`. If you find yourself changing the schema or `uses-report`, stop -- that's out of scope.
- **The `\dcc\` path trick** is the reliable way to make a fixture file classify as a library in the headless test (avoids needing a real Embarcadero install path). Document it in the test.
- **Grouping is best-effort + cosmetic** -- a wrong group label is not a test failure; the resolved flag + unit name are the load-bearing assertions.
- **schema verb is read-only** -- never write to the DB it inspects.
- **When a claim in INDEX-SCHEMA.md can't be verified against the live DB, correct it against the DB** -- the live schema is the truth, not the doc's first draft.
- If any anchor (`DoUsesReport` shape, `IsLibraryPath`, `TArgs` fields, `unit_uses` columns) has drifted from this plan, STOP and report -- don't guess.
