# v0.22 — IDE Polish

**Date:** 2026-05-29
**Status:** Design approved, ready for plan
**Branch:** `v0.22-ide-polish` off `main` (post-v0.21)

## 1. Goal

Turn v0.21's "Tools menu with ShowMessage dialogs" into something a user would
actually adopt in daily Delphi work. Four concrete deliverables, each pushed
to GitHub right after it lands.

## 2. Features

### 2.1 Auto-index on project open

Plugin hooks `IOTAIDENotifier.FileNotification` (or `IOTAProjectNotifier`).
When a `.dproj` opens:

1. Resolve the project source directory.
2. Compute the project-database path: `<projdir>\.drag-lint.sqlite`.
3. Spawn `drag-lint.exe index <projdir> --db <projdir>\.drag-lint.sqlite`
   asynchronously (don't block the IDE).
4. Emit progress to the Messages pane.
5. On success, automatically re-point the active LSP client to the new DB
   (call `workspace/didChangeConfiguration` notification with the new path).

### 2.2 Settings UI (Tools → Options → drag-lint)

A simple settings page surfacing:

- `drag-lint.exe` path (text + browse button; default: next to BPL or PATH)
- Project database path template (default: `<projdir>\.drag-lint.sqlite`)
- Auto-index on project open (toggle, default ON)
- Auto-reindex on file save (toggle, default OFF — v0.23 scope)
- Toggle each feature: Hover / Completion / SignatureHelp / Diagnostics

Storage: `HKCU\Software\drag-lint\DelphiPlugin\*` registry keys.

### 2.3 Keystroke bindings

Map the four Tools-menu actions to keystrokes via `IOTAKeyboardServices.AddKeyboardBinding`:

- `Ctrl+Alt+H` — Hover at cursor
- `Ctrl+Alt+C` — Show Completion (Ctrl+Space is owned by IDE Code Insight)
- `Ctrl+Alt+S` — Show Signature Help
- `Ctrl+Alt+D` — Run Diagnostics

Keys are configurable via Settings UI (deferred to v0.23 if scope creeps).

### 2.4 Custom popup form for hover

Replace `ShowMessage` with `TDragLintHoverForm` — a borderless `TForm` with:

- `TPanel` background, single-pixel border
- `TMemo` (or `TRichEdit`) rendering the Markdown content as plain text
- Auto-sized to content (max 600x400)
- Positioned just below the caret
- Auto-closes on: cursor moved, ESC pressed, click outside

Completion + signatureHelp continue to use ShowMessage in v0.22 — their
custom forms become v0.23 work to keep this version shippable.

## 3. Settings storage schema

```
HKCU\Software\drag-lint\DelphiPlugin\
  ExePath         REG_SZ      "C:\...\drag-lint.exe"
  DbPathTemplate  REG_SZ      "<projdir>\.drag-lint.sqlite"
  AutoIndex       REG_DWORD   1
  EnableHover     REG_DWORD   1
  EnableCompletion REG_DWORD  1
  EnableSignature REG_DWORD   1
  EnableDiagnostics REG_DWORD 1
```

## 4. Storage additions

None. v0.22 is purely IDE-side polish.

## 5. CLI additions

None. The auto-index calls existing `drag-lint index`.

## 6. New units

- `src/delphi-plugin/DragLint.Plugin.Settings.pas` — TDragLintSettings (singleton; registry IO; defaults)
- `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` — TDragLintSettingsForm (VCL form for Tools → Options page) plus `IOTAOptionsForm` adapter
- `src/delphi-plugin/DragLint.Plugin.ProjectNotifier.pas` — TDragLintProjectNotifier (IOTAIDENotifier hook + async index spawn)
- `src/delphi-plugin/DragLint.Plugin.HoverForm.pas` — TDragLintHoverForm (borderless popup)
- `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` — keystroke binding registration

## 7. Stop criteria (auto-verifiable)

1. BPL compiles clean with all new units.
2. Registry read/write smoke test (`tests/fixtures/T28_settings.dpr`) round-trips a config.
3. Project-notifier unit standalone test (`tests/fixtures/T29_notifier.dpr`) parses a .dproj filename and computes the expected DB path.

## 8. Stop criteria (manual)

4. Open a project in IDE → drag-lint index runs in background → Messages pane shows "drag-lint: indexing complete (N files)".
5. Tools → Options → drag-lint shows the settings page; changing the exe path persists across IDE restarts.
6. `Ctrl+Alt+H` on an identifier triggers the new hover popup (not ShowMessage).
7. The hover popup auto-closes on ESC / cursor move / click outside.

## 9. Out of scope (deferred to v0.23+)

- Auto-reindex on file save (background)
- Completion + signatureHelp custom popups (v0.23)
- Incremental `didChange` updates
- Pre-D13 IDE versions
- macOS RAD Studio
- Index-status panel (separate dockable form)
- Telemetry-off badge

## 10. Push cadence

User wants frequent pushes. After each of the 4 features lands and tests
pass, immediately `git push origin v0.22-ide-polish` so users can preview
work-in-progress. Final v0.22.0-alpha tag + release page after Feature 4.
