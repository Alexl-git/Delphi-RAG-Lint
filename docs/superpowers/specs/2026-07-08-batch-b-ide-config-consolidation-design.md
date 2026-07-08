# Batch B -- IDE Configuration Consolidation (Tools->Options pages, Project Rules menu, docs refresh) -- Design

**Date:** 2026-07-08
**Status:** Approved (brainstorm complete; ready for implementation plan)
**Supersedes framing of:** backlog items #4 (Tools->Options pages) and #5 (Editor->Language tabs)

## Background & premise correction

The original backlog framed Batch B as "add a Tools->Options page (#4)" and "add an Editor->Language
tab (#5)". Investigation of the live plugin + the RAD Studio 37 (Delphi 13 / Florence) Open Tools API
(`C:\Program Files (x86)\Embarcadero\Studio\37.0\source\ToolsAPI\ToolsAPI.pas`) overturned both premises:

1. **#4 already exists.** `DragLint.Plugin.Options.pas` (`TDragLintOptions`) already implements
   `INTAAddInOptions` and registers a native `Tools -> Options -> Third Party -> drag-lint` page showing
   `TDragLintOptionsFrame` (`DragLint.Plugin.OptionsFrame.pas`). There is nothing to *create* for #4 --
   the work is to *consolidate + enrich*.
2. **#5 as literally specified is not feasible.** The OTA has no interface to add a page under the
   built-in `Editor -> Language` branch. `INTAAddInOptions.GetArea` is a free-form string that reliably
   lands only under "Third Party" (Embarcadero explicitly recommends `GetArea=''`). Grafting into the
   Editor branch requires guessing an undocumented internal literal -- version-fragile, unsanctioned.
   `#5` is therefore reframed as "surface the linter/indexer knobs in dedicated Options sub-pages,"
   not a literal Editor->Language tab.
3. **A duplicate surface exists.** The same 26 registry settings (`TDragLintSettings`,
   `DragLint.Plugin.Settings.pas:6-37`) render in BOTH the native Options frame AND a hand-coded
   standalone modal `ShowSettingsDialog` (`DragLint.Plugin.SettingsForm.pas`, "Settings..." menu item).
   This violates single-source-of-truth.
4. **A real teardown bug exists.** `UnregisterDragLintOptions` (`DragLint.Plugin.Options.pas:105`) is
   fully implemented but **never called** (no `finalization` in `Options.pas`; not called from
   `Wizard.Destroyed` or the `UnregisterDragLintMenu` cascade). This leaves a dangling `INTAAddInOptions`
   interface registered after package unload -- a leak / AV-on-uninstall risk. Fixing it directly serves
   the user's "detach on uninstall AND deactivation" requirement.

## Goals

Consolidate **all** drag-lint configuration into proper IDE homes with correct scope semantics and clean
teardown, and refresh all published documentation (user-facing AND AI-facing) to match.

1. Split the registry-backed plugin settings into **four** `Tools->Options` sub-pages nested under one
   `drag-lint` node: **General, Indexer, Linter, Editor**.
2. Give `max_return_cases` (manifest `drag-lint.json` docs block; currently no UI) a home on the
   **Linter** page ("Doc generation" group).
3. Make per-project rules (`drag-lint-lint.json`) reachable via a **Project Manager right-click** entry
   "drag-lint: Project Rules..." that reuses the existing Lint Options dock tab.
4. **Retire the duplicate modal:** replace the "Settings..." menu item with "drag-lint Options..." that
   opens the IDE Tools->Options dialog. Native pages become the single source of truth.
5. **Fix teardown:** wire `UnregisterDragLintOptions` (all 4 pages) + the project-menu notifier
   unregister into the existing `Wizard.Destroyed` / `finalization` cascade. No orphaned registrations
   on uninstall/deactivation.
6. **Refresh docs** (verified against shipped code): user-facing README/INSTALL/USER-GUIDE + AI-facing
   AI-USAGE/AI-INDEX-FIRST, with a "Where to configure X" map and corrected indexer descriptions.
7. **Hand off YADF:** after all drag-lint work is done + verified, write detailed, implementation-ready
   porting instructions directly into the YADF repo so a YADF Opus session only implements + publishes.

Non-goals: no literal Editor->Language OTA page (infeasible); no changes to the CLI/engine config schema;
no new settings beyond surfacing `max_return_cases`; no edits to out-of-repo `CLAUDE.md` files.

## Verified OTA facts (grounding)

- **Multiple pages:** `INTAEnvironmentOptionsServices.RegisterAddInOptions` (ToolsAPI.pas:6771) accepts N
  distinct `INTAAddInOptions` instances. `GetCaption` with a dot nests: `GetArea=''` +
  `GetCaption='drag-lint.Indexer'` renders `Third Party / drag-lint / Indexer` (doc comment
  ToolsAPI.pas:6649-6660). => 4 instances, captions `drag-lint.General|Indexer|Linter|Editor`.
- **Project menu:** `IOTAProjectManager.AddMenuItemCreatorNotifier(notifier): Integer` +
  `RemoveMenuItemCreatorNotifier(index)` (ToolsAPI.pas:9920/9933). Implement
  `IOTAProjectMenuItemCreatorNotifier.AddMenu(...)` (9898) appending an `IOTAProjectManagerMenu` (10146).
  This is the supported route (`INTAProjectMenuCreatorNotifier` is deprecated at 9915).
- **Teardown contract:** each registration needs its matching unregister in `Wizard.Destroyed`
  (fires before the BPL vtable is dropped; the plugin's own comment at `Wizard.pas:52-59` documents AVs
  from dangling interfaces if skipped) and/or unit `finalization` as a secondary net.

## Architecture / components

### A. Four Options-page frames + registration objects (`src/delphi-plugin/`)

Refactor the single `TDragLintOptionsFrame`/`TDragLintOptions` into four `INTAAddInOptions` instances,
each with its own `TFrame` (`.dfm` or code-built, following the existing frame's convention) and a dotted
caption. All four share the existing registry round-trip (`LoadSettings`/`SaveSettings` in
`DragLint.Plugin.Settings.pas`): each frame loads the full record, displays its subset, and on
`DialogClosed(Accepted=True)` writes back its own fields (read-modify-write the whole record so no page
clobbers another's fields).

Field -> page mapping (all 26 fields from `DragLint.Plugin.Settings.pas:6-37`; each field appears on
exactly one page -- exhaustive, no field dropped or duplicated):

| Page (`GetCaption`)   | Fields |
|-----------------------|--------|
| `drag-lint.General`   | `ExePath`, `DbPathTemplate`, `EnableWorkspaceMode`, `AutoCompileOnSave`, `AutoCompileBuffer`, `AutoCompileOnStartup`, `AutoCompileOnSwitch`, `AutoJumpToDiagnostics` |
| `drag-lint.Indexer`   | `AutoIndex`, `AutoReindexOnSave`, `ScanLibraries`, `IndexDbs`, `AutoDiscoverDbs`, `IncludeLibraryDb` |
| `drag-lint.Linter`    | `EnableDiagnostics`, `AutoDiagnosticsOnSave`, `EnableInlineMarkers`, `ShowErrorsInline`, `ShowWarningsInline`, `ShowHintsInline`, `ShowInfoInline`, **+ `max_return_cases`** (manifest, see B2) |
| `drag-lint.Editor`    | `EnableHover`, `EnableHoverTooltip`, `EnableCompletion`, `EnableSignature`, `EnableCodeLens` |

Each page labels its scope ("Plugin settings -- this machine (registry)") so users understand these are
per-user, distinct from the per-project rules reached via the Project menu.

### B2. `max_return_cases` on the Linter page (the one non-registry field)

`max_return_cases` lives in the manifest `drag-lint.json` docs block (`TDocSettings`,
`DRagLint.Index.Manifest.pas`), NOT the registry and NOT `drag-lint-lint.json`. The Linter page's
"Doc generation" group reads/writes it via `TManifestIO` against the effective manifest (the same
`TManifestIO.Load(engineDir, cwd)` the CLI uses). Grouped + labelled separately so the different backing
store is visible. (If writing the manifest from the IDE proves awkward in the plan -- e.g. which manifest
file to target when multiple exist -- the fallback is to make this field read-only-with-a-note pointing at
the CLI; the plan resolves the exact target-file question. The primary intent is an editable field.)

### C. Project Manager menu (`IOTAProjectMenuItemCreatorNotifier`)

A new notifier adds "drag-lint: Project Rules..." to the project-node right-click menu. Its action:
1. Activate the clicked project (set it active via `IOTAProjectGroup.ActiveProject`), then
2. Open/focus the existing Lint Options dock tab (`ShowDragLintDock` -> select the "Lint Options" tab).

This sidesteps the current limitation that `TLintOptionsFrame` is hardwired to the ACTIVE project
(`GetActiveProjDir`, `LintOptionsFrame.pas:237-253`) and takes no path override: by activating the clicked
project first, the frame's active-project lookup resolves correctly. (A later enhancement could thread an
`AProjectDir` override through `Create`/`CreateEmbeddedLintOptions`/`CfgPath`; out of scope here --
activate-then-open is the minimal correct approach and reuses the working surface without duplication.)

### D. Retire the duplicate modal

Remove `ShowSettingsDialog` (`DragLint.Plugin.SettingsForm.pas`) and its "Settings..." menu wiring
(`Editor.pas:3808 InvokeSettings`). Replace with a "drag-lint Options..." menu item that opens the IDE
Tools->Options dialog (via the OTA if a focus-node API exists, else just opens the dialog; users navigate
to the drag-lint node). One source of truth.

### E. Teardown wiring (the "detach on uninstall/deactivation" requirement)

- `RegisterDragLintOptions` registers all 4 `INTAAddInOptions` instances (holding references for
  unregister). `UnregisterDragLintOptions` unregisters all 4. **Wire the unregister** into
  `Wizard.Destroyed` (primary) AND add an `Options.pas` `finalization` (secondary net) -- fixing the
  current gap where it is never called.
- The project-menu notifier: store the `Integer` index from `AddMenuItemCreatorNotifier`; call
  `RemoveMenuItemCreatorNotifier(index)` in `Wizard.Destroyed` / `finalization`.
- Verify (live smoke): after package unload, Tools->Options shows no orphan `drag-lint` node and no AV.

### F. Documentation refresh (verified against shipped code, at the end)

**User-facing (published, in-scope to edit):**
- `README.md` (root) -- update the "settings via INTAAddInOptions" line + quick-start plugin section.
- `docs/INSTALL.md` -- the "Settings (Tools -> Options -> Third Party -> drag-lint)" section (primary
  target) + the manifest/indexer section.
- `docs/USER-GUIDE.md` -- the "Settings..." menu walkthrough (now "drag-lint Options...") + Project Rules.
- `src/delphi-plugin/README.md` -- install/verify steps incl. the new pages + Project Rules menu.
- `rules/README.md` -- cross-reference the new Project Rules UI that edits `drag-lint-lint.json`.
- `docs/SCAN-DATABASES.md` -- review for staleness / hardcoded `C:\Projects\...` paths (correct if wrong).
- Add a **"Where to configure X" map**: setting -> page/menu -> backing file (registry /
  `drag-lint-lint.json` / manifest `drag-lint.json`).
- Correct indexer feature descriptions throughout (`ScanLibraries`, `AutoDiscoverDbs`, named-DB manifest).

**AI-facing (published, in-scope to edit):**
- `docs/AI-USAGE.md` (primary AI config/usage doc) -- add a section pointing at the GUI config surfaces
  (Indexer/Linter Options pages + Project Rules menu) alongside the CLI flags / JSON files.
- `docs/AI-INDEX-FIRST.md` -- note the Indexer Options page as a GUI path to configure/trigger scans.

**Out-of-repo (flag to user, do NOT edit):** parent `c:\Projects\CLAUDE.md`, global `~/.claude/CLAUDE.md`.

### G. YADF porting instructions (separate, after all else)

After all drag-lint work above is implemented + verified with no open surprises, write detailed,
implementation-ready instructions **directly into the YADF repo** (path to be supplied at that point) so a
YADF Opus session only has to implement + publish. Contents: the proven `INTAAddInOptions` recipe (single
or multi-page as YADF needs), the register/unregister lifecycle + teardown contract (Destroyed vs
finalization, the leak class we fixed here), how to move `YADFSetup`'s options into a YADFOT Options page,
and gotchas. Written keyed to the YADF Opus doing the repo-specific wiring (this session cannot see the
YADF repo, so YADF-specific file/field details are left as clearly-marked "verify in YADF" steps).

## Testing & verification

IDE OTA UI is not headless-testable (no CLI harness reaches `INTAAddInOptions` frames or the project menu).
Verification is therefore two-tier:

**Objective / automatable gate:**
- Clean **BPL build** (Win32, RAD Studio closed via `Get-Process bds`), 0 errors -- the build gate.
- Any non-UI logic gets a real check: the `max_return_cases <-> drag-lint.json` read/write path touches
  `TManifestIO`, so it can get a small CLI-level or unit assertion (round-trip a manifest, confirm the
  value) independent of the IDE.

**Live IDE smoke checklist (run by the user in the IDE after the BPL builds; mirrors the deferred v0.94
hover live-smoke pattern):**
1. Tools->Options shows a `drag-lint` node with 4 sub-pages: General, Indexer, Linter, Editor.
2. Each page shows its mapped fields; editing a field and clicking OK persists it (reopen -> value stuck).
3. `max_return_cases` on the Linter page round-trips to `drag-lint.json`.
4. Right-click a project node -> "drag-lint: Project Rules..." activates that project + opens the Lint
   Options dock tab scoped to it.
5. The old "Settings..." modal is gone; "drag-lint Options..." opens Tools->Options.
6. **Teardown:** uncheck the package in Install Packages (deactivate) -> no AV; reopen Tools->Options ->
   no orphan drag-lint node (proves unregister fired). Re-check -> pages return.

## Risks & mitigations

- **Multiple manifests for `max_return_cases`:** which `drag-lint.json` does the Linter page write? Mitigate:
  the plan defines the target (the effective manifest via `TManifestIO.Load`); fallback to read-only+note
  if ambiguous.
- **Project-menu scoping:** activate-then-open avoids the frame's active-project hardwiring; if activation
  has side effects, the plan re-checks (worst case: thread an `AProjectDir` override -- larger, deferred).
- **Frame refactor regressions:** splitting one frame into four must not drop a field or break the shared
  registry round-trip. Mitigate: the field->page table above is exhaustive (all 22 fields mapped); a
  live-smoke step confirms each field persists.
- **Teardown ordering:** unregister must run in `Wizard.Destroyed` before the vtable drops; secondary
  `finalization`. Mitigate: mirror the existing (working) notifier-teardown pattern exactly.
- **Docs drift:** docs updated at the END, verified against shipped code, so they describe what exists.

## Commit / delivery shape

- Source changes (frames, registration, project menu, modal removal, teardown) -- one commit per logical
  task per the plan.
- BPL/DCP binary rebuilt in a SEPARATE `build(plugin):` commit (v0.88 convention).
- Documentation refresh -- its own commit(s), after the code is verified.
- YADF instructions -- written into the YADF repo (not this repo), separately.
- Publish: user drives the push (convention).
