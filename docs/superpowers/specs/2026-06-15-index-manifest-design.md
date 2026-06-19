# Index Manifest + Settings + Win64 Engine - Design

Date: 2026-06-15
Status: Approved (brainstorm complete), ready for implementation plan
Branch: `feat/index-manifest`

## Problem

drag-lint produces SQLite index files, but which folders/projects map to which
database is defined ad-hoc on the command line (one `drag-lint index <folder>
--db <file>` per scope), or via the limited v0.42 `scan-all` command that builds
exactly **three fixed** dictionaries (`library` / `active-projects` /
`projects`) from a `"scan"` section. There is no declarative, user-editable
manifest of *named* databases, no file-glob excludes, no `.gitignore`/`.hgignore`
support, and no per-platform library separation. Consumers (CLI, LSP, MCP, IDE
plugin, graph tool) each need `--db` spelled out.

Two concrete pains motivated this:
1. **Out-of-memory.** Querying the ~1.4 GB whole-tree `drag-lint-all.sqlite`
   throws `ESQLiteNativeException: out of memory`. Root cause: the *deployed*
   scanner is **Win32** (PE32 i386, ~2 GB address-space ceiling) + one monolithic
   DB. A **Win64** build already exists at `third_party/dll-win64/drag-lint.exe`
   and queries the same 1.4 GB DB fine (verified 2026-06-15).
2. **Hidden per-platform library drift.** Merging all platforms into one
   `library.sqlite` hides the case where a folder is on the Win64 Library/Browsing
   search path but missing from Win32 (or vice-versa) - which silently compiles a
   wrong/missing unit. Per-platform DBs make this visible.

## Goals

- A declarative, named-database **manifest** in `.drag-lint.json` (`indexes`),
  plus a **`settings`** block, stored **next to the engine EXE/BPL** (with an
  optional discovered local `.drag-lint.json` override for back-compat).
- Each named DB = a list of **folders** (folder-tree mode) or **`.dproj`/`.dpr`**
  (compile-closure mode), with **glob excludes** (global + per-section),
  **`includeOnly`** allowlists, and **`.gitignore`/`.hgignore`** support.
- **Cross-section dedup** so no folder is indexed into more than one DB.
- **Per-platform library** DBs (`library-{platform}.sqlite`), auto-expanded from
  the registry, auto-adding new platforms.
- **Manifest-driven DB selection** by current platform for all consumers
  (engine, LSP, MCP, **graph tool**, IDE plugin) - no explicit `--db` needed.
- **Win64 engine canonical**; the OOM is solved by Win64 + scoped DBs + a size
  guard. Interface BPLs (plugin + graph handoff) build Win32 **and** Win64;
  all EXEs are Win64.
- Clean **seams** for the two follow-on sub-projects (visual configurator,
  registry watcher).

## Non-goals (separate sub-projects / backlog)

- **Visual configurator** UI (point at a tree, auto-assign folders to DBs, show
  what is covered/excluded elsewhere). Follow closely; consumes this engine.
- **Registry watcher** that detects Library/Browsing path changes and triggers a
  reindex/reselect. Follow closely.
- **dproj/dpr reconciler** tool: rewrite `.dpr`/`.dproj` to add used-but-unlisted
  non-Library units so the member list matches the real compile closure (and the
  resurfaced stale file is noticed). Separate tool.
- **Platform-diff** report ("this unit is only on Win64's path"). Future, enabled
  by per-platform library DBs.
- Byte-exact `git check-ignore` parity (we implement a practical subset).

## Architecture decisions (locked in brainstorm)

### 1. Config format & location
- Format: **JSON**, extending the existing `.drag-lint.json` (the tool already
  discovers it cwd->parents and reads `scan`/`docs`).
- Canonical location: a global config at the **engine install dir** (beside
  `drag-lint.exe`; the BPL resolves it via the engine path it launches). An
  optional discovered local `.drag-lint.json` in a project tree **overrides /
  merges over** the global one (back-compat with today's loader).
- Two top-level blocks: `settings` (user preferences) and `indexes` (the
  manifest of named databases).

### 2. `settings` block
```jsonc
"settings": {
  "currentProjectsIndexing": "perProject", // perProject | perGroup | single
  "defaultPlatform": "Win32",              // fallback when no active platform
  "sizeGuardMB": 1500,                     // warn if a 32-bit process opens a bigger DB
  "enginePath": "auto",                    // auto = dll-win64 beside this config
  "maxJobs": 0                             // parallel section builds; 0 = auto (min CPU, sections)
}
```
- `currentProjectsIndexing` is a **selection + scaffolding** preference, NOT
  engine logic. The engine always builds whatever explicit `sections` exist.
  - `perProject` (default): each project its own DB; switching the active project
    selects that project's DB.
  - `perGroup`: the active `.groupproj` maps to one combined DB (built from its
    member projects' closures); switching groups switches DB.
  - `single`: one combined "Current" DB for all working projects, always selected.

### 3. `indexes` block (the manifest)
```jsonc
"indexes": {
  "outDir": "C:\\Projects\\.drag-lint",      // default dir for DBs given by bare name
  "exclude": ["*BACKUP*", "*_OLD*.pas", "* - Copy.pas"],  // GLOBAL excludes
  "sections": [
    { "name": "ORM3", "db": "C:\\Projects\\DB\\ORM3\\drag-lint.sqlite",
      "include": ["...\\CLIENT\\Micronite2027.dproj",
                  "...\\SERVER\\MicroniteMW1Service.dproj"],
      "useIgnoreFiles": true },
    { "name": "Loader", "db": "Loader.sqlite",
      "include": ["C:\\Projects\\Loader2019\\Loader2025.dproj"] }, // closure skips "- Copy"
    { "name": "SQL", "db": "C:\\Projects\\DB\\SQL\\drag-lint-sql.sqlite",
      "include": ["C:\\Projects\\DB\\SQL"], "includeOnly": ["MS*.SQL"] },
    { "name": "TableTools",        "include": ["C:\\Projects\\TableTools"] },
    { "name": "Delphi-RAG-lint",   "include": ["C:\\Projects\\Delphi-RAG-lint"] },
    { "name": "Delphi-RAG-Lint-Graph", "include": ["C:\\Projects\\Delphi-RAG-Lint-Graph"] },
    { "name": "OCRPDF",            "include": ["C:\\Projects\\OCRPDF"] },
    { "name": "Library", "source": "registry-libraries",
      "platforms": "all", "db": "library-{platform}.sqlite" },
    { "name": "AllProjects", "db": "C:\\Projects\\drag-lint-all.sqlite",
      "include": ["C:\\Projects"], "dedupAgainst": "*" }
  ]
}
```

**Per-section fields**
| Field | Meaning |
|---|---|
| `name` | Section name; also default DB filename (`<outDir>\<name>.sqlite`) if `db` omitted. |
| `db` | Explicit DB path; bare filename resolves under `outDir`; supports `{platform}` token. |
| `include[]` | Folders **or** `.dproj`/`.dpr` paths; entry kind picks the mode. |
| `source` | Default `"include"`; `"registry-libraries"` = registry/platform-driven library section. |
| `platforms` | Library sections: `"all"` (auto-discover) or list e.g. `["Win32","Win64"]`. |
| `exclude[]` | Wildcard globs (added to global `exclude`). |
| `includeOnly[]` | Hard allowlist globs; only matching files index (e.g. SQL -> `["MS*.SQL"]`). |
| `useIgnoreFiles` | Default `true`; honor `.gitignore` AND `.hgignore` (and `.scanignore`) in folder-tree mode. |
| `dedupAgainst` | `"*"` or `["Section", ...]`; subtract those sections' resolved roots. |

### 4. Include resolution modes
- **Folder path -> folder-tree mode:** recursive walk (existing `IndexFolder`);
  apply built-in prunes, then global excludes, then section excludes, then
  `includeOnly` allowlist, then local ignore files; incremental skip
  (mtime+sha256) unchanged.
- **`.dproj`/`.dpr` -> compile-closure mode:** start from dpr/dproj unit members;
  resolve their `uses` to **project-local** files (NOT on any registry Library
  path), transitively; add `{$I}`/`{$INCLUDE}` files; index exactly that set.
  Loose folder files are NOT indexed. Ignore files are NOT consulted (closure
  membership wins). Global/section excludes STILL apply: if an excluded file is
  found in the closure (referenced via `uses`), it IS indexed but a **warning**
  is emitted naming the using unit (the "resurrected stale file" signal).

### 5. Exclude / ignore precedence (folder-tree mode), low -> high
1. Built-in prunes (always): `__history`, `__recovery`, `.git`, `.svn`, `.hg`,
   `node_modules`, `*backup*` folders, `.scanignore` marker.
2. Global `indexes.exclude` globs.
3. Section `exclude` globs.
4. Section `includeOnly` (hard allowlist; only matching files pass).
5. Local `.gitignore` / `.hgignore` (deeper file wins; leading `!` re-includes
   against layers 1-3; does not widen past `includeOnly`).

Glob semantics: `*`, `?`, `**`; matched against file AND folder names; a folder
match prunes the subtree. Practical `.gitignore` subset: per-line glob, trailing
`/` = dir-only, leading `!` = un-ignore, nested files apply to their subtree.

### 6. Cross-section dedup
- Computed from each section's **resolved include-roots** (order-independent).
- `dedupAgainst: "*"` subtracts every other section's roots; a list subtracts the
  named sections' roots. Implemented through the existing
  `AddExcludeRoot`/`ShouldPruneDir` prune path.

### 7. Per-platform libraries
- Library section expands `{platform}` -> one DB per platform from the registry
  (`ReadLibraryPaths(APlatforms)` already reads `Search Path` + `Browsing Path`
  per platform across HKCU/HKLM x 32/64 views).
- `platforms: "all"` auto-discovers every registry platform subkey; new platforms
  get their own DB on the next run. Project DBs stay single (Win32/Win64 share
  source; tree-sitter indexes both `{$IFDEF}` branches anyway). Per-platform
  *project* indexing is a future opt-in for cross-OS-family targets.

### 8. Consumer DB selection (no explicit `--db`)
- When `--db` is omitted, the engine, LSP, MCP, and the **graph tool** read the
  global config and assemble the DB set = *all project-section DBs* + *the one
  `library-<platform>` DB for the active platform*.
- Platform source: `--platform <p>` (CLI) or the IDE active platform via OTAPI
  (plugin), defaulting to `settings.defaultPlatform`.
- Reuses/extends `DragLint.Plugin.DbResolver`. The graph tool gains the same
  resolution so it no longer needs explicit `--db` arguments.

### 9. Reload events (IDE plugin)
- Two triggers, one mechanism: **platform change** (swap `library-<platform>`)
  and **active-project / group change** (re-select per `currentProjectsIndexing`).
  Both re-resolve the `--db` set and re-point the LSP client. Engine guarantees
  deterministic resolution from `(config, platform, active project/group,
  strategy)`. OTAPI wiring lands in the IDE-plugin follow-on; the contract is
  fixed here.

### 10. CLI surface
- `index --all` - build every section.
- `index --only ORM3,SQL` - subset by name.
- `--platform <p>` - scan/select a platform.
- `--dry-run` - print resolved plan (roots in, roots subtracted, target DB, est.
  file count) without indexing.
- `--json` - machine-readable plan/result (for the visual tool).
- `--jobs N` - build up to N sections concurrently (see decision 12). `0`/omitted
  uses `settings.maxJobs` (auto).
- `scan-all` kept as a back-compat alias mapping its three fixed DBs onto the
  model.
- **Size guard:** on opening a DB larger than `settings.sizeGuardMB` from a
  32-bit process, print a clear message instead of an opaque OOM.

### 11. Bitness / distribution
- **Engine EXE: Win64 only** (make `dll-win64/drag-lint.exe` canonical; add a
  launcher/path resolution that prefers it; update the `C:\Projects\CLAUDE.md`
  drag-lint exe default).
- **Interface BPLs follow the IDE bitness:** the main plugin BPL and the graph
  tool's source-handoff BPL build **Win32 AND Win64**. The 32-bit RAD Studio IDE
  (kept for BDE/Paradox) loads the Win32 BPL, which spawns the Win64 engine over
  pipes (`CreateProcessW` + `CreatePipe`, already how `TDragLintLspClient`
  works - cross-bitness IPC needs no client-DLL shim).
- **All standalone EXEs (engine, graph viewer): Win64.**

### 12. Parallel reindex (`--jobs N`)
- **Across-section parallelism** is the primary win: every section writes its own
  SQLite file, so there is no write contention. `index --all --jobs N` builds up
  to N sections at once. The per-platform **library** scans (the long poles) and
  the many medium working-set sections parallelize cleanly.
- **Implementation = worker child processes**, not threads: the orchestrator
  (`DoIndexAll`) computes the full plan (resolved roots, dedup, target DBs),
  then launches up to N child `drag-lint` single-section index processes
  (throttled), waits, and aggregates timing/results. Multi-process sidesteps any
  tree-sitter / FireDAC thread-safety questions (each child owns its own parser
  and DB connection) and reuses the existing single-section `index` path. A
  hidden `index-section` subcommand (resolved folders + db + excludes already
  computed) is the child entry point so the parent does the resolution once.
- **Dedup is path-based and computed upfront**, so a `dedupAgainst:"*"` section
  (e.g. AllProjects) can run in parallel with the sections it subtracts - it
  only needs their *paths*, not their completion.
- `maxJobs`/`--jobs`: `0` = auto (`min(CPU count, section count)`), capped to a
  sane max; `1` = sequential (today's behavior).
- **Intra-section parallelism** (parallel file parsing within one DB, for the
  multi-hour AllProjects scope) is a **future** enhancement (SQLite single-writer
  + per-thread parser batching); out of scope here.

## Code placement
- New unit `DRagLint.Index.Manifest.pas`: load/save/validate the `settings` +
  `indexes` config; merge global + local; resolve sections -> a build plan;
  expand `{platform}`; compute dedup roots. Models on `DRagLint.Workspace.Config`.
- New unit (or extend Project.Resolver) for **compile-closure** resolution:
  parse `.dpr`/`.dproj` members, resolve project-local `uses` transitively,
  collect `{$I}` includes, exclude registry-Library files.
- New unit for the **ignore-file** engine (`.gitignore`/`.hgignore` practical
  subset, nested, `!`).
- `DRagLint.CLI.pas`: generalize `DoScanAll` -> `DoIndexAll`; `scan-all`
  delegates; add `--all/--only/--platform/--dry-run/--json` parsing; size guard
  on DB open. Consumer DB-selection helper shared by CLI/LSP/MCP.
- Graph tool repo (`Delphi-RAG-Lint-Graph`): read the same global config +
  platform to pick its DBs.
- Reuse `TProjectResolver` (library paths, dproj parsing) and the indexer's
  `AddExcludeRoot`/`ShouldPruneDir`.

## Testing
- Fixture global config + fixture tree under `tests/fixtures/`.
- `index --all --dry-run --json` golden assertions:
  - section enumeration and target DB paths (incl. `{platform}` expansion);
  - dedup subtraction (`dedupAgainst:"*"` and explicit list);
  - `includeOnly` allowlist (SQL section keeps only `MS*.SQL`, drops `.pas`);
  - exclude precedence incl. global vs section vs local ignore file `!`;
  - compile-closure membership (members + transitive project-local `uses` +
    `{$I}`), exclusion of loose files, and the excluded-but-in-closure warning;
  - consumer selection: `(config, platform)` -> ordered `--db` list.
- Extend `tests/autotest/run_smoke.ps1` (or a new `run_manifest.ps1`).

## Deliverables for visual verification (end of implementation)
- Rebuilt **Win64 engine** EXE.
- **Win32 BPL** (`dclDragLintWizard.bpl`) installable in the 32-bit IDE.
- Updated **`docs/TEST-PLAN-IDE-FULL.md`** with a manifest/settings/platform
  section so the whole feature can be exercised together in the IDE.
- **Post-build reindex:** after the engine + BPLs are built, run
  `drag-lint index --all --jobs 0` to (re)build every DB the manifest defines
  (ORM3, Loader, SQL, the working-set sections, `library-<platform>` per platform,
  AllProjects) so the indexes match the new scanner and the new config.

## Open items (defaulted; flag to change)
- `currentProjectsIndexing` default = `perProject`.
- `defaultPlatform` = `Win32`.
- `sizeGuardMB` = `1500`.
- Working-set sections seeded: ORM3, Loader (Loader2025.dproj), SQL, TableTools,
  Delphi-RAG-lint, Delphi-RAG-Lint-Graph, OCRPDF, Library, AllProjects.
