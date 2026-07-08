# Batch B -- IDE Configuration Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate all drag-lint IDE configuration into four native Tools->Options sub-pages plus a Project-menu "Project Rules" entry, retire the duplicate settings modal, fix the never-called Options-page teardown, and refresh all user- and AI-facing docs to match.

**Architecture:** Split the single `TDragLintOptionsFrame`/`TDragLintOptions` (`INTAAddInOptions`) into four frames + four registration instances with dotted captions (`drag-lint.General|Indexer|Linter|Editor`) that share the existing registry round-trip (`LoadSettings`/`SaveSettings`). Add a supported `IOTAProjectMenuItemCreatorNotifier` that activates the clicked project then opens the existing Lint Options dock tab. Wire all new registrations (4 pages + notifier) into the existing `Wizard.Destroyed`/`finalization` teardown cascade -- fixing the pre-existing `UnregisterDragLintOptions`-never-called leak.

**Tech Stack:** Delphi 13 (RAD Studio 37 / Florence), VCL, Open Tools API (`INTAAddInOptions`, `INTAEnvironmentOptionsServices`, `IOTAProjectManager`, `IOTAProjectMenuItemCreatorNotifier`, `IOTAProjectGroup`), Win32 IDE BPL. Non-UI logic (`max_return_cases` <-> manifest) touches `TManifestIO` (`System.JSON`) and is CLI-testable. PowerShell `run_*.ps1` autotests for the one automatable check.

## Global Constraints

- **Encoding:** all `.pas`/`.dfm` files strict 7-bit ASCII, CRLF line endings, no BOM, no Unicode. (CLAUDE.md)
- **DocInsight (CDD):** every NEW public type/method/interface gets a `///` `<summary>`/`<param>`/`<returns>`/`<remarks>` spec-comment. Private helpers only when an invariant is non-obvious. (CLAUDE.md)
- **TDD where testable:** the ONLY headless-testable surface is the `max_return_cases` <-> `drag-lint.json` round-trip (via the CLI/`TManifestIO`) -- that gets a failing test first. The IDE OTA UI (frames, project menu, teardown) is NOT headless-testable; it is verified by the build gate + a live IDE smoke checklist (Task 9). Do not fake UI tests.
- **Build recipe:** use the `delphi-build` skill. IDE BPL = `src/delphi-plugin/dclDragLintWizard.dproj` Win32, RAD Studio CLOSED (check `Get-Process bds` is empty), via `_bpl_build.bat`. CLI (only if a task touches CLI/engine, i.e. Task 6's optional test) = `src/cli/drag-lint.dproj` Win64 Debug -> `src/cli/Win64/Debug/drag-lint.exe`.
- **Commit cadence:** one commit per task (source). BPL/DCP binaries go in a SEPARATE `build(plugin):` commit, never mixed with source (v0.88 convention).
- **Teardown contract (binding, the user's explicit requirement):** every OTA registration MUST have a matching unregister wired into `TDragLintWizard.Destroyed` (`DragLint.Plugin.Wizard.pas:50-65`) AND/OR a unit `finalization` -- so the plugin detaches cleanly on uninstall AND on package deactivation (unload). No orphaned `INTAAddInOptions` node or dangling notifier after unload.
- **No literal Editor->Language OTA page** (infeasible -- `GetArea` only reliably lands under Third Party). Do not attempt `GetArea` string-guessing.
- **Out-of-repo docs are OFF LIMITS:** do NOT edit `c:\Projects\CLAUDE.md` or `~/.claude/CLAUDE.md` -- flag them to the user only.
- **Implementation order:** Task 1 (shared frame base + field map) establishes the pattern the four pages reuse; Tasks 2-3 build on it; the project menu (4), modal retire (5), teardown (7) and docs (8) are largely independent; the BPL (6) comes after all source is in; docs (8) come LAST, verified against shipped code.

---

## File Structure

**New files:**
- `src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas` -- the four page frames (`TDLGeneralOptionsFrame`, `TDLIndexerOptionsFrame`, `TDLLinterOptionsFrame`, `TDLEditorOptionsFrame`), each a `TFrame` building its own controls in code and sharing the registry round-trip. (One unit, four small frames -- they change together.)
- `src/delphi-plugin/DragLint.Plugin.ProjectMenu.pas` -- the `IOTAProjectMenuItemCreatorNotifier` + its `IOTAProjectManagerMenu` item and register/unregister.
- `tests/autotest/run_docs_manifest_roundtrip.ps1` -- the one automatable check (manifest `max_return_cases` read/write via the CLI), for Task 6.

**Modified files:**
- `src/delphi-plugin/DragLint.Plugin.Options.pas` -- replace the single `TDragLintOptions` with four `INTAAddInOptions` instances (dotted captions); `RegisterDragLintOptions`/`UnregisterDragLintOptions` handle all four; add a `finalization`.
- `src/delphi-plugin/DragLint.Plugin.Wizard.pas` -- call `UnregisterDragLintOptions` + `UnregisterProjectMenu` in `Destroyed`; call `RegisterProjectMenu` in `Register`.
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` -- replace the "Settings..." menu item (`InvokeSettings`, :1990) with "drag-lint Options..." (opens Tools->Options); remove the `ShowSettingsDialog` call.
- `src/delphi-plugin/DragLint.Plugin.DockForm.pas` -- add an exported `ShowDragLintDockLintOptions` that shows the dock and selects the Lint Options tab.
- `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` -- retire `ShowSettingsDialog` (or reduce to nothing referenced).
- Docs: `README.md`, `docs/INSTALL.md`, `docs/USER-GUIDE.md`, `src/delphi-plugin/README.md`, `rules/README.md`, `docs/SCAN-DATABASES.md` (review), `docs/AI-USAGE.md`, `docs/AI-INDEX-FIRST.md`.

---

## Existing interfaces this plan consumes (verbatim)

```pascal
// DragLint.Plugin.Settings.pas -- the 26-field registry record + round-trip
TDragLintSettings = record
  ExePath, DbPathTemplate: string;
  AutoIndex, AutoReindexOnSave, AutoDiagnosticsOnSave, AutoCompileOnSave,
  AutoCompileBuffer, AutoCompileOnStartup, AutoCompileOnSwitch, AutoJumpToDiagnostics,
  EnableHover, EnableCompletion, EnableSignature, EnableDiagnostics, EnableInlineMarkers,
  ShowErrorsInline, ShowWarningsInline, ShowHintsInline, ShowInfoInline,
  ScanLibraries, EnableCodeLens, EnableWorkspaceMode, EnableHoverTooltip: Boolean;
  IndexDbs: TArray<string>;
  AutoDiscoverDbs, IncludeLibraryDb: Boolean;
end;
function LoadSettings: TDragLintSettings;
procedure SaveSettings(const ASettings: TDragLintSettings);

// DragLint.Plugin.Options.pas -- current single-page impl (to be split)
procedure RegisterDragLintOptions;    // Wizard.Register:95
procedure UnregisterDragLintOptions;  // EXISTS but NEVER CALLED (the leak to fix)

// INTAAddInOptions (ToolsAPI.pas) -- methods each page frame's registration implements:
//   GetArea: string;            // return '' (Third Party)
//   GetCaption: string;         // 'drag-lint.General' etc (dot nests)
//   GetFrameClass: TCustomFrameClass;
//   FrameCreated(AFrame); DialogClosed(Accepted); ValidateContents; GetHelpContext; IncludeInIDEInsight
// INTAEnvironmentOptionsServices.RegisterAddInOptions / UnregisterAddInOptions (one call each per instance)

// IOTAProjectManager (ToolsAPI.pas:~9890): AddMenuItemCreatorNotifier(N): Integer; RemoveMenuItemCreatorNotifier(Index)
// IOTAProjectMenuItemCreatorNotifier.AddMenu(Project; const IdentList: TStrings; const ProjectManagerMenuList: IInterfaceList; IsMultiSelect: Boolean)
// IOTAProjectManagerMenu (extends IOTALocalMenu): Caption, Verb, Execute(const MenuContextList: IInterfaceList) etc.

// DragLint.Plugin.DockForm.pas
procedure ShowDragLintDock;   // shows/focuses the tabbed dock (GForm singleton)
// FTabLintOptions: TTabSheet; FPages: TPageControl  (private on TDragLintDockFrame)

// DragLint.Plugin.Editor.pas
function GetActiveProjectFile: string;   // reads IOTAProjectGroup.ActiveProject:1364
// IOTAProjectGroup.ActiveProject is settable (to activate the clicked project)

// DRagLint.Index.Manifest.pas (CLI side, for the max_return_cases field + Task 6)
TDocSettings = record MaxReturnCases: Integer; class function Defaults: TDocSettings; static; end;
// TIndexManifest.Docs: TDocSettings; TManifestIO.Load(engineDir, startDir); ParseText; ToJson
```

---

## Task 1: Shared page-frame scaffolding + the 26-field page map

Establish the four-frame unit with the exhaustive field->page mapping and the shared read-modify-write registry round-trip. This is the foundation all four pages reuse; getting the map right here prevents any field being dropped or double-owned.

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas`
- Reference (read only): `src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas` (the existing single frame -- copy its control-building idiom + `Load`/`Save`), `src/delphi-plugin/DragLint.Plugin.Settings.pas:6-37`.

**Interfaces:**
- Produces:
  - `TDLPageFrame = class(TFrame)` -- abstract-ish base with `procedure Load; virtual;` and `procedure Save; virtual;` and a protected `FSettings: TDragLintSettings`. `Load` calls `LoadSettings` into `FSettings` then `LoadControls`; `Save` calls `LoadSettings` (re-read to avoid clobbering other pages' fields), applies this page's controls into that record via `SaveControls`, then `SaveSettings`. Subclasses override `BuildControls`/`LoadControls`/`SaveControls`.
  - Four subclasses: `TDLGeneralOptionsFrame`, `TDLIndexerOptionsFrame`, `TDLLinterOptionsFrame`, `TDLEditorOptionsFrame`.
- The page map (each field appears on EXACTLY one page):
  - **General:** `ExePath`, `DbPathTemplate`, `EnableWorkspaceMode`, `AutoCompileOnSave`, `AutoCompileBuffer`, `AutoCompileOnStartup`, `AutoCompileOnSwitch`, `AutoJumpToDiagnostics`
  - **Indexer:** `AutoIndex`, `AutoReindexOnSave`, `ScanLibraries`, `IndexDbs`, `AutoDiscoverDbs`, `IncludeLibraryDb`
  - **Linter:** `EnableDiagnostics`, `AutoDiagnosticsOnSave`, `EnableInlineMarkers`, `ShowErrorsInline`, `ShowWarningsInline`, `ShowHintsInline`, `ShowInfoInline` (+ `max_return_cases` added in Task 3)
  - **Editor:** `EnableHover`, `EnableHoverTooltip`, `EnableCompletion`, `EnableSignature`, `EnableCodeLens`

- [ ] **Step 1: Read the existing frame's control idiom**

Read `DragLint.Plugin.OptionsFrame.pas` in full: note how `BuildControls` creates `TGroupBox`/`TCheckBox`/`TEdit` in code (no `.dfm`), how `Load`/`Save` map controls <-> `TDragLintSettings`, and the `IndexDbs` `|`-join/one-per-line-edit handling. The four new frames MUST reuse this exact idiom (code-built controls, ANSI, no `.dfm`).

- [ ] **Step 2: Write the base frame + `TDLGeneralOptionsFrame`**

Create `DragLint.Plugin.OptionsFrames.pas`. Define `TDLPageFrame` with the shared round-trip:

```pascal
type
  /// <summary>Base for the four drag-lint Tools->Options page frames. Each page
  /// shows a SUBSET of TDragLintSettings; Load/Save re-read the whole record so a
  /// page only writes its own fields and never clobbers another page's.</summary>
  TDLPageFrame = class(TFrame)
  protected
    FSettings: TDragLintSettings;
    /// <summary>Create this page's controls (code-built, no .dfm). Called once.</summary>
    procedure BuildControls; virtual; abstract;
    /// <summary>Copy FSettings -> this page's controls.</summary>
    procedure LoadControls; virtual; abstract;
    /// <summary>Copy this page's controls -> ASettings (only this page's fields).</summary>
    procedure SaveControls(var ASettings: TDragLintSettings); virtual; abstract;
  public
    constructor Create(AOwner: TComponent); override;   // calls BuildControls
    /// <summary>Read the registry into FSettings and populate this page.</summary>
    procedure Load;
    /// <summary>Re-read the registry, apply this page's controls, write back.</summary>
    procedure Save;
  end;
```
`Load`: `FSettings := LoadSettings; LoadControls;`
`Save`: `var S := LoadSettings; SaveControls(S); SaveSettings(S);`
Then implement `TDLGeneralOptionsFrame` (BuildControls creates the 8 General controls; LoadControls/SaveControls map them). Give each public frame class + the base a DocInsight `<summary>`.

- [ ] **Step 3: Implement `TDLIndexerOptionsFrame`, `TDLLinterOptionsFrame`, `TDLEditorOptionsFrame`**

Each overrides `BuildControls`/`LoadControls`/`SaveControls` for its fields per the map. Linter's `max_return_cases` field is added in Task 3 (leave a `// Task 3: max_return_cases here` marker in the Linter frame's BuildControls). `IndexDbs` on the Indexer page reuses the existing one-path-per-line `TMemo`/`TEdit` + `|`-split idiom from the old frame.

- [ ] **Step 4: Build the IDE BPL to verify it compiles** (delphi-build skill, `dclDragLintWizard.dproj` Win32, RAD Studio CLOSED).

Expected: `Build succeeded`, 0 Error(s). (The new frames aren't registered yet -- Task 2 wires them; this step just proves they compile.) If the frames aren't in the `.dproj`, add the unit to the project's file list first (mirror how `OptionsFrame` is listed).

- [ ] **Step 5: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "feat(plugin): four drag-lint Options page frames sharing the registry round-trip"
```
(End every commit message with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.)

---

## Task 2: Register the four pages as nested INTAAddInOptions instances

Replace the single Options registration with four instances so Tools->Options shows `Third Party / drag-lint / {General,Indexer,Linter,Editor}`.

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Options.pas` (full rewrite of the registration; keep the same two public procs `RegisterDragLintOptions`/`UnregisterDragLintOptions`)

**Interfaces:**
- Consumes: the four frame classes from Task 1.
- Produces: `RegisterDragLintOptions` registers 4 `INTAAddInOptions`; `UnregisterDragLintOptions` unregisters all 4. Same signatures as today (callers unchanged).

- [ ] **Step 1: Rewrite `Options.pas` with a parameterized options class**

Generalize `TDragLintOptions` to carry a caption + frame class:

```pascal
type
  TDragLintOptionsPage = class(TInterfacedObject, INTAAddInOptions)
  private
    FCaption   : string;
    FFrameClass: TCustomFrameClass;
    FFrame     : TDLPageFrame;
  public
    constructor Create(const ACaption: string; AFrameClass: TCustomFrameClass);
    function GetArea: string;            // ''
    function GetCaption: string;         // FCaption e.g. 'drag-lint.Indexer'
    function GetFrameClass: TCustomFrameClass;   // FFrameClass
    procedure FrameCreated(AFrame: TCustomFrame);  // FFrame := ...; FFrame.Load;
    procedure DialogClosed(Accepted: Boolean);     // if Accepted then FFrame.Save; FFrame := nil;
    function ValidateContents: Boolean;  // True
    function GetHelpContext: Integer;    // 0
    function IncludeInIDEInsight: Boolean;// True
  end;
```
Keep a module-level `GOptions: array of INTAAddInOptions;`.

- [ ] **Step 2: Register the four instances + add a finalization**

```pascal
procedure RegisterDragLintOptions;
var Svc: INTAEnvironmentOptionsServices;
  procedure Add(const ACap: string; AFC: TCustomFrameClass);
  var O: INTAAddInOptions;
  begin O := TDragLintOptionsPage.Create(ACap, AFC); Svc.RegisterAddInOptions(O);
        GOptions := GOptions + [O]; end;
begin
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then Exit;
  Add('drag-lint.General', TDLGeneralOptionsFrame);
  Add('drag-lint.Indexer', TDLIndexerOptionsFrame);
  Add('drag-lint.Linter' , TDLLinterOptionsFrame );
  Add('drag-lint.Editor' , TDLEditorOptionsFrame );
end;

procedure UnregisterDragLintOptions;
var Svc: INTAEnvironmentOptionsServices; O: INTAAddInOptions;
begin
  if Length(GOptions) = 0 then Exit;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then
    for O in GOptions do try Svc.UnregisterAddInOptions(O); except end;
  SetLength(GOptions, 0);
end;

initialization
finalization
  UnregisterDragLintOptions;  // secondary net; Wizard.Destroyed is primary (Task 7)
end.
```

- [ ] **Step 3: Build the BPL (Win32, RAD Studio closed), expect 0 errors.**

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Options.pas
git commit -m "feat(plugin): register four nested drag-lint Options pages + finalization unregister"
```

---

## Task 3: max_return_cases field on the Linter page (manifest-backed)

Add the one non-registry field. It reads/writes the manifest `drag-lint.json` docs block via `TManifestIO`, not the registry.

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas` (the Linter frame -- add the `max_return_cases` control + a manifest read/write in its Load/Save)

**Interfaces:**
- Consumes: `TManifestIO.Load(AEngineDir, AStartDir)`, `TManifestIO.ParseText`/`ToJson`, `TIndexManifest.Docs.MaxReturnCases` (from `DRagLint.Index.Manifest` -- add that unit to the plugin's uses/search path if not present; it's a CLI unit -- confirm it's reachable from the plugin project, else read/write the JSON directly with `System.JSON` targeting the `docs.max_return_cases` key).

- [ ] **Step 1: Decide the target manifest file + read it in the Linter frame**

The Linter page edits the EFFECTIVE manifest. Use the same resolution the CLI uses: `TManifestIO.Load(ExePathDir, ActiveProjectDir)` -- but writing a merged manifest is wrong (Load merges global+local). For WRITE, target the LOCAL project `.drag-lint.json` if a project is open (so the edit is per-project, matching where `max_return_cases` belongs), else the global config beside the exe. Implement a small helper in the Linter frame:
- `ManifestPathForWrite: string` -> active project dir + `\.drag-lint.json` if a project is open (via `GetActiveProjectFile` -> its dir), else the exe-dir `drag-lint.json`.
- On `Load`: read that file (if it exists) via `TManifestIO.ParseText(TFile.ReadAllText(path), dir)` and show `Docs.MaxReturnCases`; if no file, show the default 20.
- On `Save`: read-modify-write the target file's `docs.max_return_cases` ONLY (preserve all other keys -- parse the existing JSON, set/insert `docs.max_return_cases`, write back; do NOT emit a full `ToJson` that would drop unrelated keys). Use `System.JSON` to load the object, ensure a `docs` object, set the number, write with `TFile.WriteAllText(path, json, TEncoding.ANSI)`.

> NOTE: if `DRagLint.Index.Manifest` is NOT linkable into the Win32 plugin BPL (it may pull CLI-only deps), fall back to direct `System.JSON` manipulation of the `docs.max_return_cases` key -- that's self-contained and avoids the dependency. Verify at build time; prefer the direct-JSON route if the unit doesn't link cleanly.

- [ ] **Step 2: Add the control to the Linter frame BuildControls**

Add a `TLabel` "Max return cases (docs):" + a `TSpinEdit` (or `TEdit` with numeric validation) `FEdMaxReturnCases` in a "Doc generation (drag-lint.json)" group, clearly labelled as project/manifest-scoped (distinct from the registry checkboxes above). LoadControls sets it from the manifest read; SaveControls (for THIS field only) triggers the manifest write (since it's not part of `TDragLintSettings`, keep its persistence separate from the registry `Save` -- the Linter frame's `Save` does BOTH: the registry round-trip for its checkboxes AND the manifest write for this field).

- [ ] **Step 3: Build the BPL (Win32, RAD Studio closed), 0 errors.**

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.OptionsFrames.pas
git commit -m "feat(plugin): max_return_cases field on Linter page (manifest drag-lint.json read/write)"
```

---

## Task 4: Project Manager "drag-lint: Project Rules..." menu

Add a supported project-node right-click entry that activates the clicked project and opens the Lint Options dock tab.

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.ProjectMenu.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.DockForm.pas` (add `ShowDragLintDockLintOptions`)

**Interfaces:**
- Consumes: `IOTAProjectManager`, `IOTAProjectMenuItemCreatorNotifier`, `IOTAProjectManagerMenu`, `IOTAProjectGroup.ActiveProject` (settable), `ShowDragLintDock` (existing).
- Produces: `procedure RegisterProjectMenu;` / `procedure UnregisterProjectMenu;` (called from Wizard in Task 7); `procedure ShowDragLintDockLintOptions;` in DockForm.

- [ ] **Step 1: Add `ShowDragLintDockLintOptions` to DockForm.pas**

`ShowDragLintDock` uses a module `GForm` singleton but the tab-holding frame (`FPages`/`FTabLintOptions`) is private on `TDragLintDockFrame`. Add a module-level ref to the created frame instance in DockForm (set it where the dockable form's frame is created), and:

```pascal
/// <summary>Shows the drag-lint dock and selects the Lint Options tab. Used by the
/// Project Manager "Project Rules..." action so a right-click lands on rules.</summary>
procedure ShowDragLintDockLintOptions;
begin
  ShowDragLintDock;
  if (GDockFrame <> nil) and (GDockFrame.FPages <> nil) and (GDockFrame.FTabLintOptions <> nil) then
    GDockFrame.FPages.ActivePage := GDockFrame.FTabLintOptions;
end;
```
(Expose `FPages`/`FTabLintOptions` as read-only properties or make the helper a method on the frame that the module proc calls -- pick whichever keeps encapsulation; the frame already has these as private fields, so add public read accessors or a `SelectLintOptionsTab` method on `TDragLintDockFrame` and call it.) Give it DocInsight.

- [ ] **Step 2: Write the project-menu notifier**

Create `DragLint.Plugin.ProjectMenu.pas`:

```pascal
type
  /// <summary>The right-click menu item: activates the clicked project then opens
  /// the Lint Options dock tab scoped to it.</summary>
  TDLProjectRulesMenu = class(TInterfacedObject, IOTALocalMenu, IOTAProjectManagerMenu)
    // Caption='drag-lint: Project Rules...'; Verb='DragLint.ProjectRules'; Position; etc.
    // Execute(const MenuContextList): set the clicked project active, then ShowDragLintDockLintOptions.
  end;

  /// <summary>Creator notifier: adds TDLProjectRulesMenu to a project node's context menu.</summary>
  TDLProjectMenuCreator = class(TInterfacedObject, IOTANotifier, IOTAProjectMenuItemCreatorNotifier)
    procedure AddMenu(const Project: IOTAProject; const IdentList: TStrings;
      const ProjectManagerMenuList: IInterfaceList; IsMultiSelect: Boolean);
  end;

procedure RegisterProjectMenu;    // ProjMgr.AddMenuItemCreatorNotifier -> store GIndex
procedure UnregisterProjectMenu;  // ProjMgr.RemoveMenuItemCreatorNotifier(GIndex)
```
In `AddMenu`: only add the item when a single project node is selected (`not IsMultiSelect` and `IdentList` indicates a project). In the menu item's `Execute`: resolve the clicked `IOTAProject` (from the `Project` passed to `AddMenu`, captured into the menu item), set it active via `(BorlandIDEServices as IOTAProjectGroup).ActiveProject := Proj` (guard for nil group), then call `DragLint.Plugin.DockForm.ShowDragLintDockLintOptions`. Store the `AddMenuItemCreatorNotifier` return index in a module `GIndex: Integer` (init `-1`); `UnregisterProjectMenu` calls `RemoveMenuItemCreatorNotifier(GIndex)` when `GIndex >= 0` then resets to `-1`. Add a `finalization` calling `UnregisterProjectMenu` (secondary net).

> Verify the exact `IOTAProjectManagerMenu`/`IOTALocalMenu` method set against `ToolsAPI.pas` (Caption/Verb/Checked/Enabled/Help/Name/Position/Execute) and implement all -- an incomplete interface won't compile.

- [ ] **Step 3: Build the BPL (Win32, RAD Studio closed), 0 errors.**

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.ProjectMenu.pas src/delphi-plugin/DragLint.Plugin.DockForm.pas src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "feat(plugin): Project Manager 'drag-lint: Project Rules...' opens the Lint Options dock"
```

---

## Task 5: Retire the duplicate Settings modal

Remove the hand-coded modal; replace its menu item with "drag-lint Options..." opening Tools->Options.

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (`InvokeSettings` :1990; the menu registration `AddWrappedItem(..., InvokeSettings)`)
- Modify: `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` (retire `ShowSettingsDialog`)

**Interfaces:**
- Consumes: nothing new. Produces a menu item "drag-lint Options..." that opens the IDE options dialog.

- [ ] **Step 1: Repoint the menu item**

Find the `AddWrappedItem(RootMenu, 'Settings...', InvokeSettings)` registration (grep `InvokeSettings` in `RegisterDragLintMenu`) and change the caption to `'drag-lint Options...'` and the handler to a new `InvokeOptionsDialog`. Implement `InvokeOptionsDialog`:

```pascal
/// <summary>Opens the IDE Tools->Options dialog (drag-lint pages live under
/// Third Party > drag-lint). Replaces the retired hand-coded settings modal.</summary>
procedure InvokeOptionsDialog(Sender: TObject);
var Svc: INTAEnvironmentOptionsServices;
begin
  // Prefer a focused-open if the OTA exposes one; else the generic action.
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then
    // Svc has no direct "show dialog focused on caption" in all versions;
    // fall back to executing the IDE's Tools|Options action:
    ;
  // Robust fallback: invoke the named IDE action 'ToolsOptionsCommand' if present,
  // else ShowMessage a one-line hint pointing to Tools > Options > Third Party > drag-lint.
end;
```

> NOTE: verify whether `INTAEnvironmentOptionsServices` (or another OTA service) exposes a "show Options dialog on this page" call in Studio 37 (grep ToolsAPI.pas for `EditOptions`, `ShowOptions`, `ExecuteAction`). If a clean focused-open exists, use it. If NOT, the fallback is: execute the IDE main-menu "Tools > Options" action by locating that `TMenuItem` and calling `.Click`, OR (simplest, always works) `ShowMessage('drag-lint settings are under Tools > Options > Third Party > drag-lint.')`. Choose the cleanest that reliably works; do not leave the proc empty.

- [ ] **Step 2: Retire `ShowSettingsDialog`**

Remove `ShowSettingsDialog` from `SettingsForm.pas` (and the unit from `Editor.pas` uses if now unused). If other code references it, repoint them to `InvokeOptionsDialog` or delete dead refs. If the whole `SettingsForm.pas` becomes unused, remove it from the `.dproj` too.

- [ ] **Step 3: Build the BPL (Win32, RAD Studio closed), 0 errors.**

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas src/delphi-plugin/DragLint.Plugin.SettingsForm.pas src/delphi-plugin/dclDragLintWizard.dproj
git commit -m "feat(plugin): retire duplicate Settings modal; 'drag-lint Options...' opens Tools->Options"
```

---

## Task 6: Automatable check -- max_return_cases manifest round-trip (headless)

The one piece of Batch B logic that ISN'T IDE-UI: reading/writing `docs.max_return_cases` in `drag-lint.json`. Lock it with a CLI/manifest-level test so a regression is caught headlessly (the frame reuses the same read/write semantics).

**Files:**
- Create: `tests/autotest/run_docs_manifest_roundtrip.ps1`

**Interfaces:**
- Consumes: the built `src/cli/Win64/Debug/drag-lint.exe` (already has manifest parse/emit from Batch A). This test exercises the CLI's manifest handling as the proxy for the frame's read/write contract (both must agree that `docs.max_return_cases` round-trips and is preserved alongside other keys).

- [ ] **Step 1: Write the failing test**

```powershell
# docs.max_return_cases must round-trip through drag-lint.json without dropping other keys.
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
      [string]$WorkDir = "$env:TEMP\drag-lint-docs-roundtrip")
$ErrorActionPreference='Stop'; $script:Failed=$false
function Check($n,$ok,$d=''){ $s=if($ok){'PASS'}else{'FAIL'}; $c=if($ok){'Green'}else{'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $s,$n,$d) -ForegroundColor $c; if(-not $ok){$script:Failed=$true} }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir){Remove-Item -Recurse -Force $WorkDir}; New-Item -ItemType Directory $WorkDir|Out-Null

# A drag-lint.json with a docs.max_return_cases AND an unrelated settings key.
$cfg = "$WorkDir\drag-lint.json"
'{ "settings": { "sizeGuardMB": 1500 }, "docs": { "max_return_cases": 7 } }' | Set-Content $cfg -Encoding ascii

# The CLI must READ 7 (prove via a verb that surfaces the cap's effect, e.g. the returns
# enumeration honoring cap=7, OR a manifest-dump if one exists). If no dump verb: index a
# tiny fixture, document a function with >7 return cases, assert exactly 7 Observed cases.
# (Reuse the Batch A run_doc_returns fixture/approach; key the assertion to the cap effect.)
# Minimal proxy assertion that the file is VALID + parseable (the frame writes this shape):
Check 'config file present + valid json' (Test-Path $cfg)
# ... (fill with the real cap-effect assertion mirroring run_doc_returns Scenario B, cap=7)

Write-Host ''
if($script:Failed){Write-Host 'FAIL' -ForegroundColor Red;exit 1}else{Write-Host 'PASS' -ForegroundColor Green;exit 0}
```

> The definitive assertion reuses Batch A's proven approach (`run_doc_returns.ps1` Scenario B): write `docs.max_return_cases: N` locally, run `document` from that dir, assert exactly N Observed cases. Since Batch A already proves the CLI honors the cap, THIS test's unique job is the round-trip + key-preservation the FRAME relies on: write a config with `docs` + an unrelated key, have the CLI consume it, and (if a manifest-dump/emit verb exists via `resolve-dbs`/`--json`) assert the unrelated key survives. If no emit verb surfaces `docs`, this test degrades to the cap-effect check (still valid) -- note that in the test comment.

- [ ] **Step 2: Run it, expect PASS** (build the CLI Win64 first if the exe is stale: delphi-build, `src/cli/drag-lint.dproj`, Win64).

Run: `pwsh -File tests/autotest/run_docs_manifest_roundtrip.ps1`
Expected: `PASS`.

- [ ] **Step 3: Commit**

```bash
git add tests/autotest/run_docs_manifest_roundtrip.ps1
git commit -m "test(docs): manifest docs.max_return_cases round-trip + key-preservation (headless)"
```

---

## Task 7: Wire teardown -- the user's "detach on uninstall/deactivation" requirement

Wire all new registrations into `Wizard.Destroyed`. This ALSO fixes the pre-existing bug where `UnregisterDragLintOptions` was never called.

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Wizard.pas` (`Register` :91-102 adds `RegisterProjectMenu`; `Destroyed` :50-65 adds `UnregisterDragLintOptions` + `UnregisterProjectMenu`)

**Interfaces:**
- Consumes: `RegisterProjectMenu`/`UnregisterProjectMenu` (Task 4), `UnregisterDragLintOptions` (Task 2).

- [ ] **Step 1: Register the project menu at startup**

In `Register` (after `RegisterDragLintOptions;` at :95), add `RegisterProjectMenu;` (wrap in `try ... except end` like the dockable registrations). Add `DragLint.Plugin.ProjectMenu` to the unit's `uses`.

- [ ] **Step 2: Unregister both in `Destroyed`**

In `TDragLintWizard.Destroyed` (:50-65), ADD to the existing `try ... except end` cascade:
```pascal
  try UnregisterDragLintOptions; except end;
  try UnregisterProjectMenu;     except end;
```
(These are idempotent -- also safe alongside the `finalization` nets in Options.pas/ProjectMenu.pas. `Destroyed` is the PRIMARY teardown; it fires before the vtable drops.)

- [ ] **Step 3: Build the BPL (Win32, RAD Studio closed), 0 errors.**

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Wizard.pas
git commit -m "fix(plugin): unregister Options pages + Project menu in Wizard.Destroyed (clean detach on unload)"
```

---

## Task 8: Documentation refresh (user-facing + AI-facing), verified against shipped code

Update all published docs to describe the new config surfaces; correct indexer descriptions. Do this LAST so docs match what actually shipped.

**Files:**
- Modify: `README.md`, `docs/INSTALL.md`, `docs/USER-GUIDE.md`, `src/delphi-plugin/README.md`, `rules/README.md`, `docs/AI-USAGE.md`, `docs/AI-INDEX-FIRST.md`; review `docs/SCAN-DATABASES.md`.

**Interfaces:** none (docs).

- [ ] **Step 1: Add the "Where to configure X" map**

In `docs/INSTALL.md` (the doc that already has a "Settings (Tools -> Options -> Third Party -> drag-lint)" section), replace/expand that section with the four sub-pages (General/Indexer/Linter/Editor -- list what each holds) and a table: setting -> location (which page or the Project Rules menu) -> backing file (registry / project `drag-lint-lint.json` / manifest `drag-lint.json`). Mention "drag-lint: Project Rules..." right-click for per-project rules, and `max_return_cases` on the Linter page.

- [ ] **Step 2: Update README.md + plugin README + USER-GUIDE + rules README**

- `README.md`: update the "settings via INTAAddInOptions" line to "four pages (General/Indexer/Linter/Editor) under Tools > Options > Third Party > drag-lint" and note the Project Rules right-click.
- `src/delphi-plugin/README.md`: install/verify steps -- after installing the BPL, the four Options pages + the Project Rules menu appear; note the clean-uninstall behavior.
- `docs/USER-GUIDE.md`: the old "Settings..." menu walkthrough becomes "drag-lint Options..." -> Tools->Options; add the Project Rules entry.
- `rules/README.md`: add a note that `drag-lint-lint.json` is now editable via the IDE "drag-lint: Project Rules..." right-click (in addition to hand-editing).

- [ ] **Step 3: Correct indexer descriptions + review SCAN-DATABASES.md**

Verify the indexer feature descriptions across the docs match reality (`ScanLibraries`, `AutoDiscoverDbs`, `IncludeLibraryDb`, named-DB manifest `index --all`). Fix any stale/wrong claims. Review `docs/SCAN-DATABASES.md` for hardcoded `C:\Projects\...` paths / staleness; correct or add a "paths are examples" note.

- [ ] **Step 4: Update AI-facing docs**

- `docs/AI-USAGE.md`: add a short section "Configuring drag-lint (GUI)" pointing at the four Options pages + the Project Rules menu as the GUI companion to the CLI flags / `drag-lint-lint.json` / manifest.
- `docs/AI-INDEX-FIRST.md`: note the Indexer Options page as a GUI path to configure/trigger scans (alongside `scan-all`).

- [ ] **Step 5: Commit**

```bash
git add README.md docs/INSTALL.md docs/USER-GUIDE.md src/delphi-plugin/README.md rules/README.md docs/AI-USAGE.md docs/AI-INDEX-FIRST.md docs/SCAN-DATABASES.md
git commit -m "docs: document the four Options pages + Project Rules menu; correct indexer descriptions (user + AI docs)"
```

---

## Task 9: Final BPL build + live-smoke checklist + BACKLOG + YADF instructions

Produce the deployable BPL, write the live-smoke checklist (the real UI verification, run by the user), record the resume, and write the YADF porting instructions into the YADF repo.

**Files:**
- Build: `src/delphi-plugin/dclDragLintWizard.bpl` + `.dcp` -> `third_party/dll-win32/`
- Create: `.superpowers/sdd/batch-b-ide-smoke-checklist.md` (or `docs/lint/`) -- the live IDE smoke checklist.
- Modify: `docs/lint/BACKLOG.md` -- LATEST-29 resume block.
- Create (in the YADF repo, path supplied by the user at this step): the YADF options-page porting instructions.

- [ ] **Step 1: Rebuild the IDE BPL (Win32, RAD Studio CLOSED) and confirm deploy**

`Get-Process bds` empty -> run `src/delphi-plugin/_bpl_build.bat` via PowerShell `Start-Process cmd -Wait` + log. Confirm `Build succeeded`, 0 Error(s). Auto-deploys to `third_party/dll-win32/`.

- [ ] **Step 2: Write the live-smoke checklist**

Create the checklist covering: 4 pages nested under drag-lint; each page's fields persist (edit -> OK -> reopen); `max_return_cases` round-trips to `drag-lint.json`; right-click project -> "drag-lint: Project Rules..." activates that project + opens the Lint Options dock; "Settings..." gone / "drag-lint Options..." opens Tools->Options; TEARDOWN: uncheck the package in Install Packages -> no AV, no orphan drag-lint Options node, re-check restores.

- [ ] **Step 3: Commit source/test/docs then the BPL separately**

```bash
git add .superpowers/sdd/batch-b-ide-smoke-checklist.md docs/lint/BACKLOG.md
git commit -m "docs(backlog): LATEST-29 -- Batch B implemented, awaiting live IDE smoke"
git add third_party/dll-win32/dclDragLintWizard.bpl third_party/dll-win32/dclDragLintWizard.dcp
git commit -m "build(plugin): rebuild Win32 BPL for Batch B config consolidation"
```

- [ ] **Step 4: Write YADF porting instructions into the YADF repo**

ASK the user for the YADF repo path (and the `YADFSetup`/`YADFOT` unit locations if known). Then write a self-contained instruction doc there containing: the proven `INTAAddInOptions` recipe (single or multi-page), the register/unregister lifecycle + the Destroyed-vs-finalization teardown contract (cite the leak class fixed here in Task 7), how to move `YADFSetup`'s options into a YADFOT Options page, and gotchas. Mark YADF-repo-specific file/field steps as "verify in YADF" since this session can't see that repo. Do NOT commit in the YADF repo unless the user directs -- leave it for the YADF Opus session to review + implement + publish.

- [ ] **Step 5: Publish (user drives)**

Report the branch state; the user runs `git push origin main`. Do not push automatically.

---

## Final verification (before publish)

- [ ] All BPL builds in Tasks 1-7 succeeded (0 errors); the final BPL (Task 9) deployed to `third_party/dll-win32/`.
- [ ] `run_docs_manifest_roundtrip.ps1` PASS.
- [ ] No headless regression: run the Batch A doc batteries (`run_doc_returns.ps1`, `run_manifest.ps1`) -- still PASS (this batch shouldn't touch them, but confirm).
- [ ] `git status` clean of unintended changes; BPL/DCP only in the dedicated `build(plugin):` commit.
- [ ] The live-smoke checklist exists and is handed to the user (the UI is verified by the user in-IDE, not by this session).
- [ ] YADF instructions written into the YADF repo (path from the user).

---

## Notes for the executor

- **IDE OTA UI is not headless-testable.** Do not fabricate UI tests. The build gate + Task 6's manifest test are the automatable checks; everything else is the live-smoke checklist the user runs. This is expected and by design.
- **Teardown is the load-bearing requirement.** The user explicitly wants clean detach on uninstall AND deactivation. `Wizard.Destroyed` is primary; unit `finalization` is the net. Mirror the existing (working) notifier-teardown pattern in `Wizard.Destroyed` exactly.
- **Encoding:** every `.pas`/`.dfm` stays 7-bit ASCII + CRLF. Code-built frames (no `.dfm`) match the existing `OptionsFrame` idiom.
- **Manifest linkability:** if `DRagLint.Index.Manifest` won't link into the Win32 plugin BPL, use direct `System.JSON` for `max_return_cases` (Task 3 NOTE). Verify at build time.
- **Do NOT edit out-of-repo CLAUDE.md files.** Flag `c:\Projects\CLAUDE.md` + global to the user.
- **When a frame field can't be mapped or a menu interface won't compile:** STOP and report (systematic-debugging), don't guess -- the field map (Task 1) and the interface method sets are exact; a mismatch means an anchor drifted.
