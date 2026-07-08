# Track 5.2 -- Third-Party Dependency Report + Index Schema Docs -- Design

**Date:** 2026-07-08
**Status:** Approved (brainstorm complete; ready for implementation plan)
**Roadmap:** `docs/lint/drag-lint TODO plan.md` Track 5.2 (Analysis & Reporting)
**Ships in:** v0.95 (with the dependency report + the index-schema documentation
+ dump verb; the two are companions -- both are about making "what is in the
index, project vs external" consumable).

## Goal

A new CLI verb that produces a **third-party dependency report**: it isolates
external / library units (RTL, DevExpress, Spring4D, ...) from the project's own
units and shows, per external dependency, how deeply the project relies on it --
which project units import it, how many, the shortest uses-path to it, and a
library grouping. This packages already-shipped uses-graph traversal into a
consumable report (like Peganza PAL's third-party dependency lists / SciTools
Understand's dependency reports). It is a **report/output layer**, not a new
analysis engine.

## Background & grounding (what already exists)

- **`uses-report`** (`DoUsesReport`, `DRagLint.CLI.pas:5432`) already: opens N
  `--db` stores, builds a global file map (stem -> file), walks the `unit_uses`
  edge table, treats `TargetFileId = -1` as external/unresolved, BFS-walks the
  graph to `--depth`, and writes CSV. Its `TUsesEdge` / `TFileMeta` /
  `TBfsQueueItem` records and multi-store plumbing are the exact substrate this
  verb reuses.
- **`unit_uses`** table: one row per uses edge (file_id, unit_name,
  unit_name_norm, section [interface|implementation|program|package],
  target_file_id [NULL/unresolved = external], line/col).
- **`IsLibraryPath`** heuristic (`DRagLint.CLI.pas:1973`): a resolved file is a
  library file when its path contains `\embarcadero\`, `\program files`, or
  `\dcc\`. Used today by `find-unit` to rank project units above library units.
- **`TProjectResolver.ResolveLibraryPaths(AAllPlatforms)`** (RTL-only unit):
  returns the Delphi Library + Browsing folders. Available for path-root
  grouping.

## Decisions (from brainstorm 2026-07-08)

1. **"External" classification = unresolved OR library-path.** A dependency is
   external when EITHER its `target_file_id` is unresolved (the unit is not in
   the index at all) OR its resolved file sits under a library path
   (`IsLibraryPath` + the resolved Library/Browsing folders). This catches both
   not-indexed units AND indexed-but-library units. Everything else (resolved to
   a non-library file) is a **project** unit.
2. **Output = rollup by default, `--edges` for the flat edge list.** Default is a
   per-external-unit rollup; `--edges` switches to a flat
   (project-unit -> external-unit) edge list. Both support text + `--json` +
   `--csv` (the existing output-format conventions).
3. **Grouping = by path root + known-prefix names.** Group each external unit by
   the Library/Browsing folder it resolves under (an Embarcadero `lib`/`dcp` path
   -> `RTL`; a DevExpress path -> `DevExpress`; a Spring4D path -> `Spring4D`;
   etc.); for UNRESOLVED units (no path) fall back to unit-name-prefix heuristics
   (`cx*`/`dx*`/`Ts*Bar*`/`dxBar*` -> DevExpress; `Spring.*` -> Spring4D;
   System/Winapi/Vcl/FMX/Data/FireDAC namespace prefixes -> RTL). Anything
   uncategorized -> `unknown` (with a `not-indexed` note when unresolved).

## The verb

`drag-lint deps-report --db PATH [--db ...] [--depth N] [--edges]
[--all-sources] [--name <pattern>] [--format text|json|csv] [--output <file>]`

- `--db` (repeatable): the index DB(s). Multi-store like `uses-report`.
- `--depth N` (default 3): BFS depth for the shortest-path computation (reused
  from `uses-report`'s `--depth`).
- `--edges`: emit the flat edge list instead of the rollup.
- `--all-sources`: consider every unit across every `--db` as a potential source
  (default: only the first DB's files are treated as "project" sources -- mirrors
  `uses-report`'s `--all-sources` semantics).
- `--name <pattern>`: restrict the project-unit sources to those matching the
  pattern (substring, case-insensitive), like `uses-report --name`.
- `--format text|json|csv` (default `text`): output format. `--output <file>`
  writes to a file (default stdout).

### Rollup output (default)

One entry per external unit:

| field | meaning |
|-------|---------|
| `unit`          | the external unit's verbatim name |
| `group`         | RTL / DevExpress / Spring4D / ... / unknown (decision 3) |
| `resolved`      | true if it resolved to a library file; false if not-indexed |
| `used_by_count` | number of DISTINCT project units that import it |
| `used_by`       | the importing project units (capped list -- see Caps) |
| `shortest_path` | the shortest project-unit -> ... -> this-unit uses-chain |
| `sections`      | which sections it's used in (interface / implementation) |

Plus a **summary**: total external units, total external edges, per-group
counts ("DevExpress: 42 units used by 87 project units"), and a count of
unresolved/not-indexed externals.

- **text:** a grouped, human-readable report (group headers, then units sorted
  by `used_by_count` desc), ending with the summary.
- **json:** `{ "summary": {...}, "externals": [ {...per-unit...} ] }`.
- **csv:** one row per external unit with the scalar columns
  (`unit,group,resolved,used_by_count,shortest_path`); the `used_by` list is
  joined with `|` in a single column (mirrors how `uses-report` flattens lists).

### `--edges` output (flat)

One row per (project-unit -> external-unit) edge:
`source_unit, external_unit, group, section, resolved` (+ `line` where the edge
row carries it). text = aligned columns; json = an array; csv = the columns.

## Architecture / components

- **New unit `src/report/DRagLint.Report.Deps.pas`** (new `src/report/` dir --
  keeps the growing CLI thin; `uses-report` stays where it is, but the NEW report
  is a focused unit). It exposes a pure engine:
  - `TDepsReport = record` with the rollup + edge data + summary (plain records,
    no I/O).
  - `function BuildDepsReport(const AStores: TArray<ISymbolStore>; const AOpts:
    TDepsOptions): TDepsReport;` -- opens nothing (borrows stores), walks
    `unit_uses`, classifies external vs project (decision 1), groups (decision
    3), computes `used_by` + shortest path (BFS, reusing the `uses-report`
    approach), and returns the record. NO printing.
  - `TDepsOptions` carries depth, edges-vs-rollup, all-sources, name filter.
  - Classification helpers: `IsExternalUnit` (unresolved OR library-path) and
    `ClassifyGroup` (path-root then name-prefix). `IsLibraryPath` is promoted
    from the CLI local into this unit (or a shared helper) so both the report and
    `find-unit` can use one definition -- **do NOT duplicate the heuristic**; if
    promoting it is awkward, the report unit gets its own copy with a comment
    pointing at the canonical one (prefer promotion).
- **CLI glue `DoDepsReport(const AArgs: TArgs): Integer`** in `DRagLint.CLI.pas`:
  parses the flags (add `--edges` to `TArgs`; reuse `--depth`/`--all-sources`/
  `--name`/`--format`/`--output`/`--db`), opens the stores (reuse the
  `OpenStores` pattern), calls `BuildDepsReport`, then renders text/json/csv.
  Register the verb in the dispatch + usage banner (mirror `uses-report`'s
  registration + `--help` line).

Data flow: `DoDepsReport` (I/O + format) -> `BuildDepsReport` (pure engine over
`ISymbolStore.unit_uses`) -> `TDepsReport` (records) -> renderers. The engine is
unit-testable without the CLI.

## Caps & determinism

- `used_by` lists are capped (default 20) with a `(+N more)` trailer -- same
  convention as AutoDoc's Called-from cap. The `used_by_count` is the FULL count
  (not capped). Note the cap in output so truncation is never silent.
- Deterministic ordering: groups alphabetical; within a group, units by
  `used_by_count` desc then unit name asc; `used_by` lists sorted by unit name.
  (No reliance on hash-map iteration order.)
- Shortest path: BFS from any project-unit source to the external unit, capped at
  `--depth`; if unreachable within depth, emit the depth-1 direct edge (a direct
  import is depth 1) -- an external unit only appears if at least one project unit
  imports it (directly or transitively within depth), so there is always a path.

## Testing & verification

Headless-testable end to end (unlike the Batch B IDE work). TDD:

- **`tests/autotest/run_deps_report.ps1`:** a fixture with a small project unit
  graph that imports (a) a genuinely unresolved external unit (not in the index),
  (b) an indexed-but-library unit (a file placed under a `\dcc\` or
  `\embarcadero\`-style path so `IsLibraryPath` fires), and (c) a normal project
  unit (must NOT appear as external). Index it; run `deps-report --json`; assert:
  the two externals appear with correct `group`/`resolved`, the project unit does
  NOT, `used_by_count` matches the fixture, the shortest path is correct, and
  `--edges` emits the flat rows. Include a `--csv` assertion (columns present,
  list joined with `|`) and a determinism check (two runs byte-identical).
- Reuse the `run_doc_returns.ps1` harness conventions ($Exe absolutize, Check
  helper, PASS/FAIL exit codes).
- No regression: existing `uses-report`-adjacent behavior is untouched (the new
  verb is additive; `uses-report` is not modified).

## Scope / non-goals

- **In scope:** the new `deps-report` verb + the pure engine unit + the test +
  the `--help`/usage entry + a short docs mention (AI-USAGE / a README line).
- **Non-goals (this task):** no IDE UI (a future 5.x could add a dock report); no
  chart output (that is Track 5.3 architectural charts -- `--format json` here is
  the machine-readable bridge a future chart consumes); no change to
  `uses-report`; no new index schema (everything reads existing `unit_uses` +
  `files`). Grouping heuristics are best-effort and documented as such -- a
  wrong group label is cosmetic (the unit + resolved flag are always correct).

## Companion deliverable (v0.95): index schema documentation

Requested alongside 5.2 (user, 2026-07-08): publish the **index database schema
documentation** so other tools can consume the drag-lint SQLite index, and make
it clear **what is a project item vs an external/library item**. Two parts, both
shipped in v0.95:

### A. `docs/INDEX-SCHEMA.md` -- a hand-written reference (canonical, human-facing)

A published doc describing the index for external consumers: the schema version
(`SCHEMA_VERSION`, currently v15), each table with its columns + meaning + which
key resolves to what, and the "project vs external" story (below). Derived from
`src/storage/DRagLint.Storage.SQLite.pas` `SCHEMA_DDL` + `Migrate`, and
CROSS-CHECKED against a live DB's `sqlite_master` at authoring time so it matches
reality. Covers at least: `files`, `symbols` (+ `kind`/`kind_text`, visibility,
signature, impl-span), `refs`, `unit_uses` (+ `target_file_id` = the
project/external boundary), `type_ancestors`, `type_helpers`, `call_edges`,
`params`/`local_vars`, `schema_meta`, and the FTS text-index tables. Includes a
short "how to query the index from another tool" section (open the SQLite file
read-only; the tables are stable within a schema version; check
`schema_meta.schema_version` first).

### B. `drag-lint schema --db PATH [--json]` -- a self-documenting dump verb

A lightweight verb that dumps the LIVE schema of a given index: `schema_version`,
the table list with column names/types (from `PRAGMA table_info`), row counts per
table, and (with `--json`) a machine-readable structure a consuming tool can read
programmatically. This never drifts from the actual DB (it reads
`sqlite_master` / `PRAGMA`), so it complements the hand-written doc: the doc
explains MEANING, the verb reports the EXACT current shape. Small: one
`DoSchema` function + a `ISymbolStore` pragma pass-through (or a direct read-only
FireDAC query of `sqlite_master`/`PRAGMA table_info`). Register in the usage
banner. Add a `run_schema.ps1` smoke test (schema_version present; expected core
tables present; `--json` parses).

### Project vs external -- the boundary (the user's "what is in the project")

The index does NOT currently carry a boolean `is_external` column; the boundary
is DERIVED and this must be documented clearly so consumers get it right:
- A `unit_uses` row with a resolved `target_file_id` -> the used unit IS in the
  index (a `files` row exists). Whether that file is a PROJECT file or a LIBRARY
  file is a PATH judgment (`IsLibraryPath` -- under `\embarcadero\`,
  `\program files`, `\dcc\`). `target_file_id IS NULL` -> the unit is not indexed
  at all (external/unresolved).
- So "in the project" = resolved to a `files` row whose path is NOT a library
  path. `INDEX-SCHEMA.md` states this rule explicitly and points at the
  `deps-report` verb (this task) as the ready-made consumer that applies it.
- OPTIONAL (only if cheap + low-risk, decide in the plan): add a derived
  `files.is_library` column or expose it in the `schema`/`deps-report` output so
  consumers don't have to re-implement the path heuristic. Default: DOCUMENT the
  rule + expose it via `deps-report`; do NOT change the schema unless the plan
  finds it trivial (a schema change = version bump v15->v16 + migration, which is
  heavier than this task warrants -- lean toward documenting, not schema change).

## Commit / delivery shape

- New `deps-report` engine unit + CLI glue + `TArgs.--edges` -- one commit (or
  split engine/glue if cleaner).
- `deps-report` test -- its own commit.
- `schema` dump verb + `run_schema.ps1` -- its own commit.
- `docs/INDEX-SCHEMA.md` + AI-USAGE/README lines for both new verbs -- a docs
  commit.
- Then the v0.95 release cadence (VERSION bump + CHANGELOG + tag + GH release +
  CLI zips) -- separate release commit per the v0.94 convention (CLI.pas +
  CHANGELOG + BACKLOG only in the release commit; no BPL).
- Publish: this run cuts the v0.95 release autonomously (user pre-authorized).
