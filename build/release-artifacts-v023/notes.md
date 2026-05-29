## v0.23.0-alpha -- 2026-05-29

### Added (editor reactivity)

- **Custom completion popup form** (`DragLint.Plugin.CompletionForm`).
  Borderless `fsStayOnTop` TListBox popup replaces `ShowMessage` for
  Show Completion. Parses LSP completion items into glyph-prefixed rows
  (M/f/C/F/v/T/I/U/p/e/R for LSP CompletionItemKind values), Enter or
  double-click inserts via `IOTAEditWriter.Insert`, ESC and deactivate
  close, 30s timer fallback.

- **Custom signatureHelp popup form** (`DragLint.Plugin.SignatureForm`).
  Borderless single-line TLabel popup. Shows full signature with the
  active param index appended as `[arg N]`. ESC/deactivate/30s-timer close.

- **Background reindex on file save** (`DragLint.Plugin.SaveNotifier`).
  `TDragLintSaveNotifier` implements `IOTAModuleNotifier` (NOT
  `IOTAIDENotifier.ofnFileSaved` — that enum value doesn't exist in
  Delphi 13's ToolsAPI). `AfterSave` per-module; checks the
  `AutoReindexOnSave` setting + extension whitelist (.pas/.dpr/.dpk/.inc/
  .dfm) + cached project DB path, then spawns `drag-lint.exe index <file>
  --db <projdb>` detached. Cache `GLastProjectDb` is set by the existing
  project-open hook.

- **New setting `AutoReindexOnSave`** (REG_DWORD, default 1). Toggle in
  Tools → drag-lint → Settings dialog.

### Notes

- True incremental `textDocument/didChange` remains deferred — we still
  treat on-disk file as source of truth.
- IOTAOptionsForm (proper Tools → Options integration) still deferred.
