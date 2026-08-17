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
