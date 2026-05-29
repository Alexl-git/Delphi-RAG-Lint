# v0.33 — Find Usages + Symbol Search

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.33-findusages` off `main`

## 1. Goal

Two navigation forms:

1. **Find Usages** — dockable form showing all callers of the symbol at
   cursor with file/line/context, clickable to navigate.
2. **Symbol Search** — fuzzy-search any symbol in the indexed project,
   keyboard-driven.

## 2. F1 — Find Usages

### Trigger

- `Tools → drag-lint → Find Usages` menu entry
- Keystroke `Ctrl+Alt+F` (we already own Ctrl+Alt+H/C/S/D/I/R)

### Behavior

1. Identifier at cursor (via existing `GetActiveEditorInfo` + line/col
   text extraction)
2. Shell out: `drag-lint query find-callers --name <ident> --context 3
   --db <projdb> --format json`
3. Parse JSON output — list of callers each with file/line/col/context
4. Show in `TDragLintUsagesForm` (TForm with TTreeView, grouped by file)
5. Double-click → jump editor to that line

### TDragLintUsagesForm

`src/delphi-plugin/DragLint.Plugin.UsagesForm.pas`:

- TForm, `fsStayOnTop`, non-modal
- Top: TLabel showing "Find usages of: <name>"
- TToolBar with Refresh + Copy-to-clipboard buttons
- TTreeView (full-client docked):
  - Root per file
  - Child per usage with `<line>:<col> <context-line>`
- Double-click handler navigates editor

## 3. F2 — Symbol Search

### Trigger

- `Tools → drag-lint → Symbol Search` menu
- Keystroke `Ctrl+Alt+T` (T for type/symbol; Ctrl+Alt+S is signature
  help)

### Behavior

1. Modal dialog with TEdit at top (search box)
2. TListView populated from `drag-lint query --name <text>` as user
   types (debounced 300ms)
3. Show top 30 fuzzy matches with qname + kind + file:line
4. Enter on selected row → jump editor to that location
5. ESC closes

### TDragLintSymbolSearchForm

`src/delphi-plugin/DragLint.Plugin.SymbolSearchForm.pas`:

- Modal TForm
- TEdit with OnChange handler triggering debounced query
- TListView showing matches
- Spawn `drag-lint query --name <text>` via existing
  `RunAndCaptureStdout` on each debounced query
- Parse output line-by-line (text format): `qname [kind] file:line`

## 4. New units

- `src/delphi-plugin/DragLint.Plugin.UsagesForm.pas`
- `src/delphi-plugin/DragLint.Plugin.SymbolSearchForm.pas`

## 5. Modified

- `src/delphi-plugin/DragLint.Plugin.Editor.pas` — 2 new menu entries +
  procedures
- `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` — 2 new keystroke
  bindings
- `dclDragLintWizard.dpk` + `.dproj` — register 2 new units

## 6. Stop criteria

### Auto-verifiable

1. Smoke tests for both new form units (T57 + T58).
2. BPL builds clean.
3. All prior tests pass.

### Manual

4. Ctrl+Alt+F on identifier opens Find Usages form with N matches.
5. Ctrl+Alt+T opens Symbol Search; typing filters results.
6. Double-click in either navigates the editor.

## 7. Out of scope (v0.34+)

- Workspace mode
- MSI installer
- Hover tooltip

## 8. Push cadence

Spec → push. Each form → push. Tag + release.
