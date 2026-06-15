# Library Drift Check - Design

Date: 2026-06-15
Status: Approved (concept), small follow-on
Branch: `feat/index-manifest`

## Problem
The per-platform library indexes (`library-Win32.sqlite`, `library-Win64.sqlite`,
...) are built from the IDE's registry Library/Browsing search paths at a point
in time. When a folder is later added to (or removed from) a platform's search
path, the index silently goes stale. The common failure: a folder is on the
Win64 path but was forgotten on Win32 (or added after the last index), so symbols
resolve on one platform and not the other. We want a fast, read-only check that
surfaces this drift.

## Goal
`drag-lint library-drift [--platform <p>] [--config <path>] [--json]` reports, per
platform, registry Library/Browsing roots that are **on the current path but have
no files in the index** (the "added/forgotten folder -> reindex needed" case).
Exit code 2 if any drift is found, 0 if clean (CI-friendly).

## Non-goals
- Precise "removed root" detection (a root indexed but no longer on the path).
  That needs the exact build-root list stored as metadata; deferred (see Future).
- File-level staleness (new/changed files within an already-indexed root). The
  incremental indexer's mtime+sha256 handles re-index freshness; drift is about
  ROOT-set changes.
- The live IDE auto-watch (trigger reindex on registry change) - that is the
  plugin/OTAPI half of the "registry watcher" follow-on; this is the CLI half.

## Behavior (read-only)
1. Resolve the manifest (`--config`, else engine-dir/cwd discovery via
   `TManifestIO.Load`). `ResolvePlan` -> the library plan items (one per platform),
   each with its `DbPath` and `Platform`.
2. Platform filter: `--platform <p>` restricts to one; otherwise every library
   platform whose DB file exists is checked.
3. For each (platform, dbPath) where the DB exists:
   - `CurrentRoots := TProjectResolver.ReadPlatformLibraryPaths(platform)`.
   - `IndexedPaths` := all file paths in the DB (`TSQLiteSymbolStore` enumerate).
   - For each `root` in `CurrentRoots`: it is **MISSING** if no indexed path is
     under it (case-insensitive prefix, normalized separators + trailing sep).
4. Report per platform: the MISSING roots. Summary line:
   `library-drift: <P> platforms checked, <M> roots missing from index`.
   Exit 2 if M > 0, else 0. `--json`:
   `{ "platforms": [ { "platform": "...", "db": "...", "missingRoots": [ ... ] } ] }`.

## Components
- New unit `src/index/DRagLint.Index.Drift.pas`:
  ```pascal
  type
    TPlatformDrift = record
      Platform: string;
      DbPath:   string;
      MissingRoots: TArray<string>;   // current registry roots with 0 indexed files
    end;
    /// <summary>Read-only: which of ACurrentRoots have no indexed file under them
    /// in the DB at ADbPath. ADbPath must exist.</summary>
    function AnalyzeLibraryDrift(const ADbPath: string;
      const ACurrentRoots: TArray<string>): TArray<string>;  // returns missing roots
  ```
  Uses `TSQLiteSymbolStore` (enumerate file paths, read-only) only. No registry
  dependency in the unit (caller passes roots) -> trivially testable.
- `DRagLint.CLI.pas`:
  - `DoLibraryDrift(const AArgs): Integer` - resolves manifest + plan, gets
    `ReadPlatformLibraryPaths` per platform, calls `AnalyzeLibraryDrift`, prints
    report / `--json`, returns 0/2. Registers `library-drift` in `Run` + `PrintHelp`.
  - `selftest drift --db <db> --root <r> [--root <r>...]` - calls
    `AnalyzeLibraryDrift(db, roots)` and prints `MISSING <root>` lines + `DRIFT-OK`
    / `DRIFT-MISSING <n>` so tests can assert without the real registry.
- Register the new unit in BOTH `src/cli/drag-lint.dpr` and `drag-lint.dproj`.

## Testing
`tests/autotest/run_drift.ps1` (or extend `run_manifest.ps1`):
- Build a tiny library-like DB: `index <fixtureRootA> --db drift.sqlite` where
  `fixtureRootA` has one `.pas`. (Reuse an existing small fixture folder.)
- `selftest drift --db drift.sqlite --root <fixtureRootA> --root <fixtureRootB>`
  where `fixtureRootB` is a different folder NOT indexed -> output lists
  `MISSING <fixtureRootB>` and NOT `<fixtureRootA>`; prints `DRIFT-MISSING 1`.
- `selftest drift --db drift.sqlite --root <fixtureRootA>` -> `DRIFT-OK` (no missing).
- Real smoke (manual, not asserted): `library-drift --platform Win32` against the
  built `library-Win32.sqlite` -> 0 missing (just reindexed), exit 0.

## Future
Add a `scan_meta(key,value)` table written at index time (resolved roots +
platform + timestamp) to enable precise removed-root detection and a "built-at"
age report. Out of scope here.
