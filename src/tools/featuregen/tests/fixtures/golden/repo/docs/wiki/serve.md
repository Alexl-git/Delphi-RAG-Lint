# serve

Starts the MCP (Model Context Protocol) stdio server, for AI clients such as
Claude or Cursor to query a drag-lint index.

`serve` is DIFFERENT from `lsp`: `lsp` is the LSP stdio server that the IDE
plugin itself starts, and nothing in the IDE uses `serve`. If you are wiring
drag-lint into an AI assistant, this is the verb; if you are wiring it into
the RAD Studio IDE, it is `lsp` instead.

## Running it from the CLI

```
drag-lint serve --db <file.sqlite>
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint serve --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would start the MCP stdio server over `MyApp`'s index, for an AI client
to connect to.
