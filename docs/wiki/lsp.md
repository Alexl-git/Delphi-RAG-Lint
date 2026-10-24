# lsp

Starts the LSP (Language Server Protocol) stdio server. This is what the IDE
plugin itself launches to get hover, completion, go-to-definition and
diagnostics inside the editor.

`lsp` is DIFFERENT from `serve`: `serve` is the MCP stdio server for AI
clients such as Claude or Cursor, and nothing in the IDE uses `serve`. The
IDE plugin uses `lsp`.

## Running it from the CLI

```
drag-lint lsp --db <file.sqlite>
```

### Proxy mode: merging drag-lint into DelphiLSP

```
drag-lint lsp --proxy [--delphi-lsp <path>] [--trace <file>] [--merge-diagnostics] [--merge-budget-ms <n>]
```

`--proxy` relays every LSP message between the IDE and RAD Studio's own
DelphiLSP, so the compiler front end keeps answering. The merge flags let
drag-lint add to those answers:

- `--merge-diagnostics` -- append drag-lint's lint findings to DelphiLSP's
  `textDocument/publishDiagnostics` (one notification, source-tagged). OFF by
  default; with every merge flag off the proxy relays DelphiLSP's bytes
  unchanged.
- `--merge-budget-ms <n>` -- the per-frame time budget of a merge handler
  (default 300). A handler that overruns it, raises, or cannot open the index
  makes the proxy forward DelphiLSP's original bytes untouched; merging fails
  open and never drops a message.

Status: the flags are accepted now; the diagnostics handler itself lands
with merge task A1. Until then every message is relayed unchanged.

## Document outline (textDocument/documentSymbol)

`lsp` answers `textDocument/documentSymbol` from the index as a hierarchical `DocumentSymbol[]` (the editor's outline, breadcrumbs and *Go to Symbol in File*): the unit's members at the top level, members nested under their type, locals and parameters left out, 0-based ranges, `selectionRange` on the name token. A file no index knows answers `[]`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.DocumentSymbol`); guard: `tests\autotest\run_lsp_document_symbol_guard.ps1`.

`lsp` answers `textDocument/codeLens` with one lens per routine declaration, titled from the index caller counts (`3 callers`, `1 caller`, `0 callers`), range zero-width at (line, 0), command `draglint.showCallers` with arguments `[uri, line]` (implemented by the editor extension). Capability `codeLensProvider: {resolveProvider: false}`; a file no index knows answers `[]`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.CodeLens`); guard: `tests\autotest\run_lsp_code_lens_guard.ps1`.

`lsp` answers `textDocument/implementation` and `textDocument/declaration` from the symbol under the cursor (the hover resolution). `declaration`: one Location at the interface-section declaration (the forward-declaration line for a forward-declared type). `implementation`: a routine's body line (character 0) and, for a method, the same-named method of every descendant of its owner type (body line, or the declaration when bodiless), ordered by file:line; nothing resolving answers `[]`. Capabilities `implementationProvider` and `declarationProvider` are `true`. Registered through the LSP feature registry (`DRagLint.LSP.Feature.ImplDecl`); guard: `tests\autotest\run_lsp_impl_decl_guard.ps1`.

## Reaching it in the IDE

CLI+internal: the plugin starts this process itself, from
`DragLint.Plugin.LspClient.pas:297`. There is no menu item -- the IDE
launches the `lsp` server automatically as a background stdio process, not
via a user-facing command.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint lsp --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This is the same command the plugin runs in the background to serve the
editor's language features for `MyApp`.

## Switching VS Code's Delphi MCP entry off and on

`drag-lint-switch --vscode --status|--on|--off [--workspace <dir>]` toggles
`servers["delphi-lsp"]` in `<dir>\.vscode\mcp.json` (default `<dir>` = current
directory). `--off` writes a whole-file backup `mcp.json.draglint-<yyyymmdd-hhmmss>.bak`
next to it and removes only that entry; `--on` restores the entry from the newest
backup, or from `--template <file>` (a JSON file holding the entry) when there is
none. Exit 0 = done, 1 = already in that state, 2 = VS Code (`Code.exe`) is running
(file untouched), 3 = failure (e.g. no backup and no template). Workspace file only:
the user-level registration in `state.vscdb` is not read or written. Guard:
`tests\autotest\run_lsp_switch_vscode_guard.ps1`.

Limits: a mcp.json containing comments (JSONC) cannot be parsed, so the tool exits 3 and leaves the file untouched. The rewritten file is JSON-equal to the original, not byte-equal (indentation is normalised to 2 spaces); the untouched original is kept in the .bak.
