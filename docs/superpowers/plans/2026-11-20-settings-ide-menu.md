# Plan: SETTINGS-IDE + SETTINGS-READERS (1.53.1) -- Project Manager menu, readers onto the store

Spec: `docs\superpowers\specs\2026-11-20-settings-store-design.md` (D7, D11, criteria I1-I3, R1).
Depends on SETTINGS-CORE (store unit `src\project\DRagLint.Project.Settings.pas`) merged.
Two lanes, file-disjoint; model: sonnet for READERS, session model for IDE (live-IDE behaviour,
`C:\Projects\Delphi_IDE_OptionsPage_HOWTO.md` traps). Not in the 1.53.0 run (PLAN section 2 "Not in this run").

## Lane SETTINGS-READERS (sonnet)

Fence: `src\project\DRagLint.Project.Settings.pas` (catalog flags only), `src\charts\DRagLint.Charts.Snapshot.pas`,
`src\cli\DRagLint.CLI.Repo.pas`, `tests\autotest\run_v1531_SETTINGS_READERS.ps1`, wiki `project-settings.md`.

1. RED guard: fixture `P\App.dproj`, `P\_D-RAG\`; project file `reportsDir: "rp"`, local file `reportsDir: "rl"`
   (written by hand -- the catalog still refuses `--local` for it). Check that the snapshot folder a
   `compare --save` (or the cheapest verb that calls `DRagLint.Charts.Snapshot` folder resolution --
   find it with `query find-callers --name ReadReportsDirKey`) uses is `P\rl`; same for `fieldRepository`
   via `repo info --project P\App.dproj --json` (`path` field). RED: both use the project value.
2. Catalog: `reportsDir` and `fieldRepository` `LocalAllowed:= True`.
3. `Charts.Snapshot.ReadReportsDirKey` callers and `CLI.Repo.ProjectConfigRepo`: replace the hand JSON read
   with `TProjectSettings.Create(Anchor)` + `AsString(key)` in a try/finally; keep their existing
   "missing / malformed = default" behaviour (catch `ESettingsError` -> default, as today).
4. `ownRoots`, `excludeRoots`, `popupForms`, `checkInit` readers stay as they are (project-only by D7/D8).
5. GREEN, the 1.53.0 guards still pass, lint the changed units, wiki row update, REPORT.

## Lane SETTINGS-IDE (session model)

Fence: `src\delphi-plugin\DragLint.Plugin.ProjectMenu.pas`, NEW `src\delphi-plugin\DragLint.Plugin.ProjectSettingsDlg.pas`
+ `.dfm`, `src\delphi-plugin\dclDragLintWizard.dpk` (+ `.dproj`) contains, registry entry `project-settings`, wiki.

1. Package: add `DRagLint.Project.OwnRoots` and `DRagLint.Project.Settings` to the dpk `contains` (check
   `OwnRoots`'s own uses are already in the package or the `requires`; a missing one is the W1033 trap in the
   HOWTO). Build the BPL (Debug, IDE CLOSED -- HOWTO rule).
2. Menu: a second `TDLProjectRulesMenu`-style item in `DragLint.Plugin.ProjectMenu` (same creator,
   `TDLProjectMenuCreator.AddMenu` adds both), caption `drag-lint: Project Settings...`, position after
   `drag-lint: Project Rules...`. `Execute` resolves the project file of the right-clicked node (the
   way `TDLProjectRulesMenu.Execute` does) and opens the dialog modally.
3. Dialog `TDLProjectSettingsDlg` (form WITH a .dfm -- HOWTO `EResNotFound` trap): a `TListView` (vsReport:
   Key, Value, Source, Description) filled from `TProjectSettings.List`; an editor row under it: for bool a
   `TComboBox` (true / false / default), else a `TEdit`; a `TRadioGroup` "Scope: This project (shared) /
   This machine only" enabled only when `Def.LocalAllowed`; buttons Apply, Reset to default, Close.
   Non-settable rows: editor disabled (I3). Apply -> `SetValue`, Reset -> `Unset`; `ESettingsError` ->
   `MessageDlg` with its text, nothing written. After a `lint.*`/`taint.*` change, ask the live-diagnostics
   unit to re-lint the active file (find the entry point with `query find-callers` on the save hook).
4. Test I2 without the IDE: a console harness `tests\autotest\fixtures\settingsdlg\SettingsStoreParity.dpr`
   that links ONLY `DRagLint.Project.Settings`, applies the same three changes the guard applies through the
   CLI to a second fixture copy, and the guard `run_v1531_SETTINGS_IDE.ps1` compares the two files byte for
   byte (the dialog itself only forwards to `SetValue`/`Unset`, so parity of the store calls is the testable
   part). The live dialog = owner test page step (skill owner-test-page): click path
   Project Manager > right-click project > drag-lint: Project Settings... > pick `taint.envSource` > false >
   This project > Apply -> `_D-RAG\drag-lint-project.json` contains `"envSource": false`.
5. Registry: add `--surface "ide-context:Project Manager > drag-lint: Project Settings..."` (host
   `Project Manager`, caption `drag-lint: Project Settings`), steps as in 4. `featuregen verify --id project-settings --by ENGINE`.
6. REPORT: BPL build log result, guard counts, owner-test steps written.
