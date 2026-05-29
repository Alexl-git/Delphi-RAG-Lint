# v0.30 — Structure Pane + Native Options Page

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.30-structure-options` off `main`

## 1. Goal

Two distinct IDE integrations:

1. **Structure pane integration** — populate the IDE's Structure pane
   (View → Structure) with two node trees per active file:
   - **Diagnostics** — flat list of errors/warnings/info/hints (clickable, jumps to line)
   - **Code Elements** — class/method/property hierarchy from our symbol index
2. **Native Tools → Options page** — replace the modal Settings dialog
   with a proper IDE-native Options panel under Tools → Options → drag-lint.
   The old menu entry stays as a shortcut.

## 2. Structure pane

### OTAPI surface

The Structure pane is populated via `IOTAStructurePane` (legacy) or via
the newer `IOTAStructureView` interface. In Delphi 13 (37.0) the active
mechanism is `INTAStructurePane` (in ToolsAPI.pas) — registers a
provider that supplies nodes.

For drag-lint v0.30 we won't try to REPLACE the IDE's default structure
provider. Instead, we add a sibling tab/section titled "drag-lint" that
holds two child sections.

If sibling-tab registration is not possible without custom-window
hosting, fall back to:
- Add a single root node "drag-lint" injected via the existing structure
  visitor pattern.
- Children: "Diagnostics", "Code Elements".

### Data sources

- Diagnostics: `TDragLintDiagnosticCache.GetForFile` (from v0.29)
- Code Elements: shell out to `drag-lint surface --qname <UnitName>` and
  parse the result. Or query the project's `.drag-lint.sqlite` directly
  for symbols where `file_id = <current-file's id>`.

For v0.30 simplicity: shell out to `drag-lint surface` once per file
activation. Cache the result in `TDragLintStructureCache` (module-level
TDictionary) keyed by file path.

### Click behavior

Each node has an associated `(file, line, col)`. When clicked, the
Structure pane fires an event → our handler calls
`IOTAEditorServices.TopView.GotoLine(line)` or similar.

### Implementation note

OTAPI's Structure pane integration is poorly documented. There are two
viable paths:

1. **Implement `INTAStructureProvider`** — register via the editor's
   structure-pane bus. Cleanest but version-fragile.
2. **Custom dockable form** named "drag-lint Structure" — independent
   of the IDE's Structure pane. Less integrated but more reliable.

v0.30 ships **path 2** (custom dockable form). The form is wired up as
a Tools menu entry: `Tools → drag-lint → Show Structure`. v0.31 may
revisit native pane injection.

### New unit

`src/delphi-plugin/DragLint.Plugin.StructureForm.pas`:

- VCL form with TTreeView, dockable via TDockableForm (use existing
  `IOTADockableForm` mechanism)
- Toolbar: Refresh, Filter (Errors only / All)
- TreeView contents:
  - "Diagnostics (N)" root → child per diagnostic with severity icon +
    message
  - "Code Elements (M)" root → unit → class → method tree

## 3. Native Tools → Options page

### OTAPI mechanism

`INTAAddInOptions` interface (in ToolsAPI.pas). Register via:
```pascal
(BorlandIDEServices as INTAEnvironmentOptionsServices)
  .RegisterAddInOptions(TDragLintOptions.Create);
```

Methods:
- `GetCaption: string` — "drag-lint" (appears in left tree)
- `GetArea: string` — "" (top-level), or "User Options" / "Translation Tools"
  (sub-area)
- `GetFrameClass: TCustomFrameClass` — our TFrame
- `FrameCreated(AFrame: TCustomFrame)` — called once when the user
  opens the page
- `DialogClosed(Accepted: Boolean)` — called when user clicks OK/Cancel;
  if Accepted, commit settings
- `ValidateContents: Boolean` — return False to block close on validation
  error
- `GetHelpContext: Integer` — context for F1 help

### TFrame

`src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas`:

TFrame hosting the existing settings controls (mirrors what
`DragLint.Plugin.SettingsForm.pas` shows in its modal). Difference:
- Layout uses TGroupBox containers
- Save happens only on `DialogClosed(Accepted: True)`, not on field-level
  changes

The Tools → drag-lint → Settings... menu entry remains as a shortcut
that opens the IDE Options dialog at the drag-lint page (call
`(BorlandIDEServices as IOTAServices).GetEnvironmentOptions ...` →
specifically `INTAEnvironmentOptionsServices.DialogShow`).

### Register

In `DragLint.Plugin.Wizard.Register`:
```pascal
(BorlandIDEServices as INTAEnvironmentOptionsServices)
  .RegisterAddInOptions(TDragLintOptions.Create);
```

In wizard teardown, unregister.

## 4. New units

- `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` (custom dockable)
- `src/delphi-plugin/DragLint.Plugin.StructureCache.pas` (shells `surface`)
- `src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas` (TFrame)
- `src/delphi-plugin/DragLint.Plugin.Options.pas` (INTAAddInOptions impl)

## 5. Modified

- `DragLint.Plugin.Editor.pas` — new menu entry "Show Structure", "Show
  Options" (shortcut to IDE Options at our page)
- `DragLint.Plugin.Wizard.pas` — register/unregister Options page
- `dclDragLintWizard.dpk` + `.dproj` — register 4 new units

## 6. Stop criteria

### Auto-verifiable

1. BPL compiles clean with all 4 new units.
2. T49 — StructureCache smoke test (calls drag-lint surface, parses).
3. T50 — Options frame instantiation smoke test (TFrame creates).
4. All prior tests still PASS.

### Manual

5. In RAD Studio after install, `Tools → drag-lint → Show Structure`
   opens a dockable form with current file's diagnostics + code
   elements.
6. Clicking a diagnostic node jumps the editor to that line.
7. Tools → Options shows a "drag-lint" entry in the left tree.
8. Editing the path field + clicking OK persists to registry.

## 7. Out of scope (carried to v0.31+)

- True native Structure pane injection (sibling tab vs custom dockable)
- Mouse-hover tooltip in editor (still keyed to Ctrl+Alt+I from v0.29)
- Find-usages tree view (v0.31)
- Workspace mode / multi-project (v0.31+)
- Pre-built MSI installer

## 8. Push cadence

Spec → push. Each feature lands → push. Tag + release after both.
