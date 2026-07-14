# Fresh Compiler Findings -- design

Status: **approved (brainstorm complete)**, not yet planned/implemented.
Date: 2026-07-14.

## Problem

drag-lint is meant to replicate the Delphi compiler's (DCC) hints / warnings /
errors alongside its own lint rules. Today it does -- but only for units that are
actually (re)compiled. The compile it runs is **incremental** (`msbuild /t:Make`,
`dcc` without `-B`; see `DRagLint.Diagnostics.CompileCheck.pas`), so a unit whose
`.dcu` is already up to date is **skipped**, and DCC does not re-emit that unit's
hints/warnings. A clean, unchanged unit therefore shows **no** compiler findings
even though the compiler *would* report (for example) `H2219 Private symbol
'DoHandleException' declared but never used`.

Concretely verified on `C:\Projects\DB\ORM3\CLIENT\uMain.pas`: the Delphi LSP
(Embarcadero's own continuous analysis) shows `H2219` at line 74; drag-lint's
`check-unit` returns `[]` because `uMain.dcu` is current and the incremental
compile skips it. The `compiler_findings` table has 0 rows for ORM3.

The distinction: Embarcadero's LSP runs its OWN always-on semantic analysis and
emits the hint immediately, independent of DCU freshness. drag-lint replicates
the *compiler's* output, which only reappears when the unit is recompiled.

## Goal

Keep the `compiler_findings` table fresh so drag-lint reliably surfaces every DCC
hint/warning/error for the current source, including for clean/unchanged units --
without taxing the (often RAM-constrained, 32-bit) IDE process.

## Core insight

Track a per-unit **compilation timestamp**. A clean unit with zero findings still
records "compiled at time T". Compare that against the unit's save time to decide
staleness, and recompile only what is stale. A *changed* unit will be recompiled
by an incremental `/t:Make` anyway (so its hint reappears); only fall back to a
full build when many units are stale (first scan / branch switch).

## Section 1 -- Data model (one schema change)

Add ONE column to the existing `files` table:

- **`files.last_compiled_unix INTEGER`** -- Unix time of the last successful
  compile that covered this file. `NULL` = never compiled.

Rationale:
- Every indexed file already has a `files` row with `mtime_unix` (save time) and
  `sha256`.
- A clean unit (no `compiler_findings` rows) is still recorded via its stamped
  `last_compiled_unix` -- this closes today's gap where clean units are invisible.
- **Staleness rule:** a file is stale iff
  `last_compiled_unix IS NULL OR last_compiled_unix < mtime_unix`.
- Change signal is the file **save mtime** (`files.mtime_unix`) -- simplest, matches
  the intent ("compilation newer than unit save"). (sha256-based confirmation is a
  possible future refinement to ignore no-op touches; out of scope here.)

No other schema change. `compiler_findings` keeps its columns
(`file_id, raw_path, code, severity, line_no, col_no, message, imported_at`).

## Section 2 -- Freshness engine (new CLI verb)

New verb in `drag-lint.exe`:

```
drag-lint refresh-findings --project <X.dproj> --db <db>
                           [--platform win32|win64] [--full] [--json]
```

Algorithm:
1. Resolve the project's compile closure; query `files` for **stale** units
   (staleness rule from Section 1), scoped to that closure.
2. Decide compile mode by the count of stale units:
   - **>= 2 stale** -> **full build** (`msbuild /t:Build` / `dcc -B`). Interpretation:
     the project was never fully scanned -- in normal editing only one file is dirty
     at a time, so 2+ stale means catch-up is needed. Captures hints for ALL units.
   - **exactly 1 stale** -> **incremental** (`/t:Make`). DCC recompiles that unit
     (+ dependents) and re-emits its hints.
   - **0 stale** -> no-op, fast exit.
   - `--full` forces a full build regardless (backs the user "Full sweep" menu).
3. Run the compile OUT-OF-PROCESS (reuse `CompileCheck.Run`, which already spawns
   `cmd.exe -> rsvars -> dcc/msbuild` and parses `Hint|Warning|Error|Fatal` +
   `[HWEF]\d+` codes).
4. Update the store TRANSACTIONALLY. Determine the **covered set** = the files
   this compile is authoritative for:
   - **full build** (`>= 2 stale` or `--full`): the covered set is EVERY file in
     the project's compile closure. A full `-B` build re-checks all units, so any
     unit that emitted no finding is genuinely clean -- safe to clear + stamp all.
   - **incremental** (`1 stale`): the covered set is exactly {the one stale file}
     plus any file that appeared in the compiler output. (`/t:Make` only reports
     for recompiled units; a clean recompiled unit emits no line, so we cannot
     infer the full dependent set from output alone. We therefore stamp only the
     file we KNOW was targeted + any file with emitted findings; untouched
     dependents keep their prior state and will be picked up if they later go
     stale. This is safe: it never marks a file compiled that we did not compile.)
   For each file in the covered set:
   - delete that file's existing `compiler_findings` (NEW: a per-file clear --
     today `ClearCompilerFindings` is whole-DB `DELETE FROM compiler_findings`),
   - insert the freshly parsed findings for that file,
   - stamp `files.last_compiled_unix = now`.
   Files NOT in the covered set are left untouched (their prior findings +
   timestamp stand).
   If the compile FAILS (fatal error, no valid output): do NOT stamp
   `last_compiled_unix` (so the file stays stale and is retried), but DO store the
   error findings so the user sees them -- errors, unlike hints, are always
   emitted by an incremental compile.

Exit codes: 0 = success (fresh); 2 = usage / no readable db / project not found.
`--json` emits a summary (mode chosen, units compiled, findings added/removed).

## Section 3 -- IDE trigger (RAM-safe, debounced)

The IDE plugin (BPL) does only the lightweight part -- it SPAWNS the child exe.
This matches the existing live-diagnostics design (`DRagLint.Plugin.LiveDiagnostics.pas`
header: "Everything runs out-of-process (drag-lint.exe), debounced").

- On **save** (existing `AutoCompileOnSave` hook) and on **idle** (existing
  `GHOST_IDLE_MS = 3500` debounce), the plugin spawns:
  `drag-lint.exe refresh-findings --project <activeproj> --db <db>`,
  preferring the **Win64 exe** (the plugin already prefers Win64 -- see
  `DRagLint.Plugin.Editor.pas` DragLintExe resolution) so the compile + parse run
  in a 64-bit child address space, NOT the 32-bit IDE.
- The child updates the DB; the IDE then reads the refreshed `compiler_findings`
  and republishes diagnostics via the existing `BuildDiagnostics(ALinter, AFile,
  AStore)` path (which already merges compiler findings -- LSP.Completion.pas:566,
  LSP.Server.pas:1163; plugin DiagnosticCache union at DiagnosticCache.pas:191).
- **RAM cost to the IDE: one CreateProcessW call.** No DCC output, no findings
  parsing, no compile buffers in the IDE's address space.
- **Debounce / concurrency:** reuse the existing idle timer and the existing
  single-in-flight "busy" guard; do not add a new timer. Only one refresh at a
  time.

## Section 4 -- User-invoked Full Sweep (menu)

A menu item **"drag-lint: Full Compile Sweep"** runs
`refresh-findings --project <X> --full` -- a complete `/t:Build` so every unit's
hints are captured at once. On demand only (not automatic). This is the safety
valve when the incremental timestamp DB should not be trusted (e.g. after a large
branch switch or an external build). Mirrors the existing pattern of drag-lint
menu items that shell out to the CLI exe.

## Section 5 -- Scope boundaries (YAGNI)

Deliberately OUT of this feature:
- **No persisted lint-rule findings.** Only *compiler* findings get freshness
  tracking. drag-lint's own rules stay computed-on-demand (cheap AST queries; no
  compile involved).
- **No periodic automatic sweep.** The timestamp DB makes it unnecessary; the
  manual Full Sweep menu covers the rare catch-up case.
- **No cross-project awareness.** One active project at a time (matches the
  plugin's current model).
- **No sha256-based staleness** (mtime only) in v1; a possible later refinement.

## Testing

- **Headless / CLI (TDD):** a fixture project with a unit containing a deliberate
  `H2219` (a private method declared but never called). Cases:
  1. Fresh DB -> `refresh-findings` -> (all stale) full build -> the H2219 finding
     is stored AND `files.last_compiled_unix` is stamped for every unit.
  2. Touch that unit's mtime -> `refresh-findings` -> exactly 1 stale -> incremental
     compile -> the unit's findings are refreshed, timestamp re-stamped.
  3. Touch two units -> `refresh-findings` -> >= 2 stale -> full build path.
  4. No changes -> `refresh-findings` -> 0 stale -> no-op (fast, no compile).
  5. `--full` -> forces full build regardless of stale count.
  The whole engine is CLI, so all of this is headless-testable.
- **IDE plugin trigger:** OTA UI is not headless-testable; live smoke only
  (save/idle spawns the child; findings appear; Full Sweep menu works). BPL build
  is the only compile-time gate.

## Key implementation touch-points (for the plan)

- `src/storage/DRagLint.Storage.SQLite.pas`: add `files.last_compiled_unix`
  (migration + schema_version bump); add a **per-file** clear
  (`ClearCompilerFindingsForFile(AFileId)`); add getters/setters for the compile
  timestamp; a "stale files for project" query.
- `src/diagnostics/DRagLint.Diagnostics.CompileCheck.pas`: reused as-is (add a
  `-B`/full-build mode selector if not already parameterizable).
- `src/cli/DRagLint.CLI.pas`: new `refresh-findings` verb wiring the above.
- `src/delphi-plugin/*`: spawn the verb on the existing save/idle hooks; add the
  Full Sweep menu item. (BPL rebuild; live smoke.)
