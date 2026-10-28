---
id: serve
title: serve
summary: Starts the MCP (Model Context Protocol) stdio server, for AI clients such as Claude or Cursor to query a drag-lint index
product: DL
group: editor-integration
order: 110019
since: 0.4.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# serve

Starts the MCP (Model Context Protocol) stdio server, for AI clients such as Claude or Cursor to query a drag-lint index.

Read this when you want an AI assistant such as Claude or Cursor to query a drag-lint index: serve starts an MCP stdio server over the database you give it. The IDE does not use it; the IDE uses lsp.

## How to run it

Full flag list: [serve in the CLI reference](../cli.md#serve).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

**Needs:** index

## Details

Starts the MCP (Model Context Protocol) stdio server, for AI clients such as
Claude or Cursor to query a drag-lint index.

`serve` is DIFFERENT from `lsp`: `lsp` is the LSP stdio server that the IDE
plugin itself starts, and nothing in the IDE uses `serve`. If you are wiring
drag-lint into an AI assistant, this is the verb; if you are wiring it into
the RAD Studio IDE, it is `lsp` instead.

### Running it from the CLI

```text
drag-lint serve --db <file.sqlite>
```

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative only:

```text
drag-lint serve --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would start the MCP stdio server over `MyApp`'s index, for an AI client
to connect to.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
