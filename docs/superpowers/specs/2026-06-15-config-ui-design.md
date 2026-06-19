# drag-lint Visual Configurator (standalone) - Design

Date: 2026-06-15
Status: Approved (brainstorm), follow-on #3
Branch: `feat/index-manifest`

## Problem / Goal
Editing the index manifest (`.drag-lint.json`) by hand is opaque. Provide a
standalone Win64 VCL app, `drag-lint-config.exe`, that is the single visual hub
for drag-lint configuration: manage the named-database sections, SEE per-folder
coverage (which DB indexes a folder / excluded / unassigned), edit settings,
preview the resolved plan, and trigger (re)index / drift runs. Architected so the
logic is reusable and the UI can later be re-hosted inside the IDE plugin.

## Architecture
- **Standalone Win64 VCL app.** The forms are a thin shell; ALL logic lives in
  reusable, UI-free units (existing: `DRagLint.Index.Manifest`/`Plan`/`DbSelect`,
  `DRagLint.Project.Resolver`, `DRagLint.Index.Drift`, `DRagLint.Index.Reconcile`,
  `DRagLint.Index.Glob`, `DRagLint.Index.IgnoreFiles`; new: `DRagLint.Index.Coverage`).
- **Single source of truth:** reads/writes the unified `.drag-lint.json` beside
  the engine via `TManifestIO` (load/merge/validate/`ToJson`/save). Save =
  `Validate` then `TManifestIO.Save`.
- **Long index runs shell out** to `drag-lint.exe` (streamed into a log panel) via
  a small `TEngineRunner` (CreateProcess + pipe read; lift the graph viewer's
  `SpawnCaptureStdout`). The app never indexes in-process.
- **Multi-tab** shell so more config areas (plugin settings, lint rules) slot in later.
- **Future IDE move:** re-host the same logic units + a BPL form; no logic rewrite.

## v1 scope (tabs)
1. **Indexes** - section editor + coverage tree + plan preview + build/drift log.
2. **Settings** - JSON-backed engine/indexer settings + `docs` options.
Deferred (clearly out of v1): plugin BPL settings (auto-index/hover/reindex-on-save)
- unify when moved to the IDE; a **Lint rules** tab - later.

## New logic unit: `DRagLint.Index.Coverage` (headless, testable)
```pascal
type
  TCoverageKind = (ckIndexed, ckExcluded, ckLibrary, ckUnassigned, ckOverlap);
  TCoverageItem = record
    Folder:   string;          // absolute child folder
    Kind:     TCoverageKind;
    Detail:   string;          // section name(s) / exclude rule / 'library'
  end;
  /// <summary>For each immediate child folder of ARoot, classify how the manifest
  /// covers it: indexed by exactly one section (ckIndexed, Detail=section),
  /// by more than one (ckOverlap, Detail=names), excluded by a built-in prune /
  /// section exclude / dedup (ckExcluded, Detail=rule), under a registry library
  /// path (ckLibrary), or not covered by anything (ckUnassigned). Read-only,
  /// filesystem + manifest only (no DB).</summary>
  function ComputeCoverage(const AManifest: TIndexManifest; const ARoot: string;
    AResolver: TProjectResolver): TArray<TCoverageItem>;
```
Classification reuses `ResolvePlan` (resolved section roots + dedup) + `TGlob`
(exclude globs) + the built-in prune names. Lives in `src/index/` so the CLI can
expose `selftest coverage --config <f> --root <dir>` for headless testing, and
the GUI links the same unit.

## Indexes tab - layout
- Left: **Sections list** (DB names) + Add / Delete.
- Center: **Section editor** for the selected section -- Name, Db (with `{platform}`),
  Source (folders/dproj | registry-libraries), Platforms (for library), Include
  list with **+Folder** / **+dproj** / remove, Exclude globs, includeOnly,
  dedupAgainst, useIgnoreFiles, sqlOnlyMS.
- Bottom: a `TPageControl` with **Coverage**, **Plan preview**, **Build log**.
  - **Coverage:** a `TTreeView` of a chosen root; each folder node colored/tagged
    by `ComputeCoverage` (indexed=green+section, overlap=orange, excluded=grey+rule,
    library=blue, unassigned=red). Actions on a node: **Assign -> <existing DB>**
    (adds the folder to that section's Include) or **New DB from folder** (creates
    a section). Edits update the in-memory manifest (Save persists).
  - **Plan preview:** read-only view of the resolved plan (sections, target DBs,
    roots, dedup-excluded roots, `{platform}` expansion). Refreshes on edit.
  - **Build log:** memo that streams engine output.
- Bottom buttons: **Build All** (`index --all`), **Build Selected**
  (`index --all --only <names>`), **Library Drift** (`library-drift`),
  **Save**, **Reload**.

## Settings tab
Controls bound to `TIndexSettings`: `currentProjectsIndexing` (combo
perProject/perGroup/single), `defaultPlatform` (combo from
`EnumRegistryPlatforms`), `sizeGuardMB`, `maxJobs`, `maxParseFileKB` (spin/edits),
`enginePath` (path edit; 'auto' default), plus the `docs` options if present.
Save writes back through `TManifestIO`.

## Components / files
- `src/config/drag-lint-config.dpr` + `.dproj` (VCL, Win64).
- `src/config/Config.MainForm.pas` + `.dfm` (TPageControl with the two tab frames).
- `src/config/Config.IndexesFrame.pas` + `.dfm`, `src/config/Config.SettingsFrame.pas` + `.dfm`.
- `src/config/Config.EngineRunner.pas` (`TEngineRunner.Run(args, onLine)` via CreateProcess+pipe).
- `src/index/DRagLint.Index.Coverage.pas` (logic; registered in BOTH the engine
  `.dpr`/`.dproj` AND the config app project).
- CLI: `selftest coverage --config <f> --root <dir>` in `DRagLint.CLI.pas`.

## Testing
- **Headless (asserted):**
  - `selftest coverage` over a fixture manifest + fixture tree -> classifies a
    folder as indexed/excluded/unassigned/overlap correctly (`tests/autotest/run_coverage.ps1`).
  - Manifest IO / plan / drift / reconcile already covered by existing suites.
  - **Build smoke:** `drag-lint-config.dproj` compiles Win64 (msbuild exit 0) and
    the EXE file is produced (`tests/autotest/run_config_build.ps1` or folded into
    a build step). GUI runtime is NOT headlessly asserted.
- **Manual (you):** a new `docs/TEST-PLAN-CONFIG.md` with click-through steps:
  load manifest, edit a section, coverage tree colors + assign/new-DB, plan
  preview refresh, settings round-trip (save->reload->values persist), Build
  Selected on a small section, Library Drift, Save writes valid JSON
  (`index --all --dry-run` still parses it).

## Limitations
- The GUI's visual correctness/interaction is verified by you (the manual plan);
  automated tests cover the logic units + that it compiles.
- Coverage classifies IMMEDIATE child folders of the chosen root (one level),
  expandable on demand; it does not pre-walk the whole tree (perf).
- v1 edits only JSON-backed config; plugin BPL settings come with the IDE move.
