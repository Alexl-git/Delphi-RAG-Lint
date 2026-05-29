# v0.29 — In-Editor Visual Diagnostics

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.29-inline-markers` off `main`

## 1. Goal

Visual paint of LSP diagnostics inside the RAD Studio editor view:
- Left-gutter glyphs per diagnostic line
- Wavy underlines (squiggles) across the diagnostic's column range
- Hover tooltip showing the message
- Respect the user's custom Editor → Color settings (read from registry)

## 2. Architecture

### Data flow

```
LSP publishDiagnostics notification (already arriving via v0.20+v0.26)
   |
   v
TDragLintDiagnosticCache.Update(uri, diagnostics)
   |
   v
TDictionary<filepath, TArray<TDiagnosticItem>>
   |
   v (paint callback)
TDragLintEditViewNotifier.PaintLine(view, line, ...)
   |  -> looks up diagnostics for current file at current row
   |  -> draws gutter glyph + wavy underline
   v
Editor canvas
```

### Components

1. **TDragLintDiagnosticCache** — module-level singleton. Receives the
   parsed `params` of every `publishDiagnostics` notification (already
   routed via `HandleNotification` in `DragLint.Plugin.Editor`).
   Stores per-file diagnostic items. Fires `InvalidateView` to force
   repaint when updated.

2. **TDragLintEditViewNotifier** — implements
   `IOTAEditViewNotifier`. Registered per opened edit view via
   `IOTAEditorServices.AddNotifier` or per-view via
   `IOTAEditView.AddNotifier`. Handles `PaintLine` callback.

3. **TDragLintRegistryColors** — reads
   `HKCU\Software\Embarcadero\BDS\37.0\Editor\Highlight\` to pull the
   user's configured colors:
   - `Syntax Error` → error color
   - `Warning` → warning color
   - `Hint` → hint color
   - `Information` (or fall back) → info color
   Each key has `Foreground Color`, `Background Color`, `Underline`,
   `Default Foreground`. Stored as `TColor` (clRed default if any
   missing).

4. **TDragLintMarkerSettings** — toggles per-severity show/hide,
   `EnableInlineMarkers` master switch. Stored in same registry tree
   as v0.22 settings.

## 3. Painting

### Gutter glyph

In `PaintLine` callback:
1. Get the view's left-gutter x range from the View's bounds.
2. Compute centerline of the row in screen y.
3. If line has any diagnostic, draw a small filled circle (6x6 px) in
   the gutter, color per max severity in this row.

### Wavy underline

For each diagnostic on the row:
1. Get the start column and end column.
2. Translate via `View.CharPosToPos` (or compute from font metrics).
3. Draw a sawtooth polyline along the bottom of the row at that x
   range, using the user's `Syntax Error` registry color (or fall back
   to clRed for errors, clOlive for warnings, clBlue for info).
4. Sawtooth pattern: alternating y-positions (`y_low` / `y_high`) every
   2 pixels. Polyline via `Canvas.Polyline`.

### Hover tooltip

Subclass approach is heavy. For v0.29 simplicity: when the mouse
hovers over a marked column range, show a `THintWindow` via
`Application.HintWindow.ActivateHint` with the diagnostic message.

The hover detection requires polling cursor position vs editor cell
coords — `IOTAEditView` has `CharPosToPos` and `CursorPos`.

For v0.29 even simpler: bind to `Ctrl+Alt+I` (Info) keystroke that
displays the diagnostic at the current cursor row. Defers true hover
to v0.30 if it proves heavier than expected.

## 4. Settings (added to v0.22 TDragLintSettings)

```pascal
TDragLintSettings = record
  ...existing fields...
  EnableInlineMarkers:     Boolean;  // default True
  ShowErrorsInline:        Boolean;  // default True
  ShowWarningsInline:      Boolean;  // default True
  ShowHintsInline:         Boolean;  // default True
  ShowInfoInline:          Boolean;  // default False (often noisy)
end;
```

Reg keys: `EnableInlineMarkers`, `ShowErrorsInline`, etc.

Settings dialog adds 5 new checkboxes after the existing v0.22 row.

## 5. New units

- `src/delphi-plugin/DragLint.Plugin.DiagnosticCache.pas`
- `src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas`
- `src/delphi-plugin/DragLint.Plugin.RegistryColors.pas`

## 6. Modified

- `src/delphi-plugin/DragLint.Plugin.Editor.pas` — HandleNotification
  routes to TDragLintDiagnosticCache.Update; register
  TDragLintEditViewNotifier per opened view via IOTAEditorServices
- `src/delphi-plugin/DragLint.Plugin.Settings.pas` — 5 new fields
- `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` — 5 new checkboxes
- `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` — Ctrl+Alt+I info key

## 7. Stop criteria

### Auto-verifiable

1. BPL compiles clean with all 3 new units.
2. T45 — registry color reader smoke test (reads HKCU keys, returns sane defaults if missing).
3. T46 — settings round-trip with 5 new fields.
4. All prior v0.16-v0.28 tests still pass.

### Manual

5. In RAD Studio, after install + index, errors produced by
   `Tools > drag-lint > Compile & Diagnose` paint red gutter dots
   and wavy red underlines on the matching lines.
6. Warnings paint yellow/olive; info paints blue/gray.
7. Ctrl+Alt+I on a marked line shows a hint with the diagnostic
   message.
8. Disabling `EnableInlineMarkers` removes all markers immediately on
   next repaint.
9. Custom user underline color (set via Tools → Options → Editor →
   Color → Syntax Error in the IDE) is honored.

## 8. Out of scope (carried to v0.30)

- Structure pane integration
- Native Tools → Options page (replaces our modal settings)
- Mouse-hover tooltip (Ctrl+Alt+I keystroke substitutes in v0.29)
- Theme switching detection (currently re-reads registry only on plugin load)
- Code-folding awareness (markers may shift when folds expand)

## 9. Push cadence

Spec → push. Each unit → push. Tag + release after all units land
and BPL compiles.
