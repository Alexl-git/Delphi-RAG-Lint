# dproj/dpr Reconciler - Design

Date: 2026-06-15
Status: Approved (brainstorm), ready for implementation plan
Branch: `feat/index-manifest` (follow-on sub-project)

## Problem

A Delphi `.dpr`/`.dproj` "member list" (the `.dpr` `uses` clause + the `.dproj`
`<DCCReference>` entries) can drift from what the project actually compiles: a
unit reached transitively via `uses` that lives on the project's search path is
compiled even if it is not an explicit project member. This hides two things:
(1) the real set of project files, and (2) the case where an **old/excluded
version of a file is still pulled in via `uses`** and silently compiled. The
reconciler makes the member list honest and surfaces those stale inclusions.

## Goal

A CLI tool that, for a given `.dpr`/`.dproj`:
- **adds** used-but-unlisted project-local units to BOTH the `.dpr` and `.dproj`,
- **reports** listed-but-unused members (never auto-removed),
- **loudly flags** "stale" used units (old-version/backup/copy patterns or
  manifest-excluded), naming the unit that `uses` each one,
- is **dry-run by default**, writes only with `--apply` (with `.bak` backups).

## Non-goals
- Auto-removing unused members (a unit can be needed for initialization/side
  effects). Extras are reported only.
- IFDEF/platform-aware closure (the closure scans all conditional branches; see
  Limitations).
- `.groupproj` multi-project reconciliation (single project per invocation).
- Form-name metadata in added `<DCCReference>` entries (the IDE still recognizes
  a bare `Include="..."`).

## Command

```
drag-lint reconcile-project <App.dpr|App.dproj> [--apply] [--json] [--config <path>]
```
- Default: **dry-run** -- prints the report, writes nothing.
- `--apply`: write changes to `.dpr` + `.dproj` after backing up each as `.bak`.
- `--json`: machine-readable report (for a future IDE/visual integration).
- `--config <path>`: explicit `.drag-lint.json` for the stale-exclude globs
  (else discovered cwd..parents / beside the engine, like other consumers).

## Behavior

### Analyze (read-only)
1. **Compile closure** via the existing `TClosureResolver` (member units +
   transitive project-local `uses` + `{$I}` includes, excluding any file under a
   registry Library/Browsing root). Closure entries carry the using-unit (for
   stale attribution).
2. **Listed members**: parse the `.dpr` `uses` clause (units, with optional
   `in 'file'`) and the `.dproj` `<DCCReference Include="...pas">` entries.
   Compare case-insensitively by resolved absolute file path AND by unit name.
3. **Sets:**
   - **Missing** = closure files that are project-local and NOT in the listed
     members. (These get added on `--apply`.)
   - **Extra** = listed members whose file is NOT in the closure (unreached).
     Reported only.
   - **Stale** = closure/used units whose file NAME matches a stale rule:
     built-in heuristics OR the resolved manifest's `exclude` globs. Each stale
     entry includes the using-unit. A Stale unit that is also Missing is still
     added (it is compiled) but flagged for investigation.

### Stale heuristics (built-in), matched on the file's base name:
`*_OLD*`, `* - Copy*`, `*-Copy*`, `*BACKUP*`, `*-bad*` via `TGlob.Matches`, plus
a date-stamp suffix `_` + 8 digits (e.g. `_20230828`) detected via
`TRegEx.IsMatch(BaseName, '_\d{8}')` (replaces the old non-functional
`*_20######*` glob -- `TGlob` treats `#` as a literal character, not a digit
wildcard). PLUS the nearby manifest's `indexes.exclude` globs when a config is
found.

### Report (dry-run and the summary of `--apply`)
- `MISSING (N) - used but not listed (will be added):` unit -> relative file.
- `EXTRA (N) - listed but never reached via uses (review):` unit -> file.
- `STALE (N) - used but looks stale (investigate):` unit -> file  (used by X).
- Footer: `Run a full project build to verify after --apply.`

### Apply
- `.dpr`: for each Missing unit, insert `UnitName in 'relative\path.pas'` into the
  program/library `uses` clause, before its closing `;`, preserving existing
  indentation/line style. Paths are relative to the project directory.
- `.dproj`: add `<DCCReference Include="relative\path.pas"/>` inside the existing
  `DCCReference` `ItemGroup` (create one if none exists).
- Back up `App.dpr` -> `App.dpr.bak` and `App.dproj` -> `App.dproj.bak` BEFORE
  writing. Never remove anything. Re-running after `--apply` reports 0 Missing.

## Components

- New unit `src/index/DRagLint.Index.Reconcile.pas`:
  ```pascal
  type
    TReconcileItem = record
      UnitName: string;
      FilePath: string;    // absolute
      RelPath:  string;    // relative to project dir (for .dpr/.dproj edits)
      UsedBy:   string;    // the using unit (for stale/missing attribution)
    end;
    TReconcileResult = record
      Missing: TArray<TReconcileItem>;
      Extra:   TArray<TReconcileItem>;
      Stale:   TArray<TReconcileItem>;
    end;
    TProjectReconciler = class
    public
      constructor Create(const ALibraryRoots, AStaleGlobs: TArray<string>);
      /// <summary>Read-only analysis of a .dpr/.dproj.</summary>
      function Analyze(const AProjectFile: string): TReconcileResult;
      /// <summary>Apply Missing additions to the .dpr + .dproj (.bak backups).</summary>
      procedure Apply(const AProjectFile: string; const AResult: TReconcileResult);
    end;
  ```
  Reuses `TClosureResolver` (closure + using-unit), `TGlob` (stale match),
  `TProjectResolver` (library roots), `TManifestIO` (exclude globs). Registered in
  BOTH `src/cli/drag-lint.dpr` and `drag-lint.dproj`.
- `DRagLint.CLI.pas`: `DoReconcileProject(const AArgs): Integer`; register the
  `reconcile-project` command in `Run` dispatch + `PrintHelp`; a `selftest`
  reconcile hook for fast unit testing.

## Testing

Fixture under `tests/fixtures/reconcile/`:
- `App.dpr` listing `uMain` only (with `in 'uMain.pas'`).
- `uMain.pas` `uses uHelper;` ; `uHelper.pas` `uses uFoo_OLD_20230828;` ;
  `uFoo_OLD_20230828.pas` (stale-named, used but unlisted) ; `uOrphan.pas`
  listed in a DCCReference but used by nothing (Extra).
- `App.dproj` with `<DCCReference Include="uMain.pas"/>` and
  `<DCCReference Include="uOrphan.pas"/>`.

Smoke (`tests/autotest/run_reconcile.ps1`, or extend `run_manifest.ps1`):
- `reconcile-project App.dpr` (dry-run): MISSING lists `uHelper` and
  `uFoo_OLD_20230828`; EXTRA lists `uOrphan`; STALE lists `uFoo_OLD_20230828`
  (used by `uHelper`); exit 0; writes nothing.
- `--apply`: creates `App.dpr.bak` + `App.dproj.bak`; `App.dpr` now contains
  `uHelper` and `uFoo_OLD_20230828`; `App.dproj` has matching DCCReferences;
  a second dry-run reports 0 Missing. `uOrphan` is untouched (still Extra).
- `--json`: parseable; has `missing`/`extra`/`stale` arrays.

## Limitations (documented in help + report footer)
- Closure is IFDEF/platform-agnostic: on a cross-OS project it may propose a unit
  only used under another platform's `{$IFDEF}`. Review additions there.
- `.dproj` edits are text-based (regex/string), not a full MSBuild XML model;
  they target the `DCCReference` ItemGroup and preserve the rest of the file.
