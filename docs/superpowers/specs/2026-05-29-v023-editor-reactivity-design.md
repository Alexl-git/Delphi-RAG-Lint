# v0.23 — Editor Reactivity

**Date:** 2026-05-29
**Status:** Design approved, ready for plan
**Branch:** `v0.23-editor-reactivity` off `main`

## 1. Goal

Three features that move the plugin from "menu-invoked tool" toward
"editor reacts to you as you work." Each pushed to GitHub immediately
after it lands.

## 2. Features

### 2.1 Custom completion popup form

Mirror v0.22's hover popup pattern for `Show Completion`:

- `TDragLintCompletionForm` — borderless `fsStayOnTop` VCL form
- `TListView` filling client area (or TListBox for v0.23 simplicity)
- Populated from LSP `textDocument/completion` items: each row shows
  `kind icon` (text glyph for v0.23 — '/M' for method, '/F' for
  function, etc.) + `label` + truncated `detail`
- Arrow keys navigate; Enter inserts the item's `insertText` into the
  editor via `IOTAEditWriter.Insert`; ESC cancels
- Positioned just below caret screen coords

### 2.2 Custom signatureHelp popup form

Same pattern for `Show Signature Help`:

- `TDragLintSignatureForm` — borderless `fsStayOnTop` single-line popup
- TLabel renders the signature text with the active parameter in bold
- Closes on `)`, ESC, or cursor moved past closing paren
- Positioned just below caret

### 2.3 Background reindex on file save

When user saves a .pas/.dpr/.dpk/.dfm file in the editor, the plugin:

1. Identifies the file via `IOTAEditViewNotifier.BeforeSave` or
   `IOTAEditorServices.AddNotifier` watching for save events
2. Spawns `drag-lint.exe index <file> --db <projectdb>` async
3. The Indexer's existing v0.4 incremental skip handles unchanged files
   cheaply; only the saved file actually gets re-parsed

Honors a new settings toggle `AutoReindexOnSave` (default ON).

## 3. Schema impact

None.

## 4. New units

- `src/delphi-plugin/DragLint.Plugin.CompletionForm.pas` — TDragLintCompletionForm
- `src/delphi-plugin/DragLint.Plugin.SignatureForm.pas` — TDragLintSignatureForm
- `src/delphi-plugin/DragLint.Plugin.SaveNotifier.pas` — file-save watcher + spawn

## 5. Modified units

- `DragLint.Plugin.Editor.pas` — `InvokeCompletion` and `InvokeSignatureHelp`
  parse the LSP response and call into the new forms
- `DragLint.Plugin.Settings.pas` — add `AutoReindexOnSave: Boolean` (default True)
- `DragLint.Plugin.SettingsForm.pas` — add corresponding checkbox

## 6. Settings additions

```
HKCU\Software\drag-lint\DelphiPlugin\
  AutoReindexOnSave REG_DWORD 1
```

## 7. Stop criteria

### Auto-verifiable

1. BPL compiles clean with all 3 new units registered.
2. Test fixtures (T32, T33, T34) compile standalone.

### Manual (user verifies after install)

3. `Ctrl+Alt+C` on an identifier prefix shows the new completion popup;
   selecting an item inserts it into the editor.
4. `Ctrl+Alt+S` after `(` shows the new signature popup with bold active
   parameter.
5. Saving a .pas file triggers a background `drag-lint index` (visible
   via Process Explorer or the on-disk .sqlite mtime).

## 8. Out of scope (deferred)

- True incremental `didChange` (we still re-read from disk on save —
  closer-to-realtime updates need v0.24+)
- Snippet expansion in completion items
- Fuzzy match in completion (only prefix in v0.23)
- IOTAOptionsForm (proper Tools → Options page) — Settings dialog
  stays as Tools → drag-lint → Settings... menu entry

## 9. Push cadence

After each feature lands and tests pass, `git push origin
v0.23-editor-reactivity`. Final tag + GitHub release after Feature 3.
