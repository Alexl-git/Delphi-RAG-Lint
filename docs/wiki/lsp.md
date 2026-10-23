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
