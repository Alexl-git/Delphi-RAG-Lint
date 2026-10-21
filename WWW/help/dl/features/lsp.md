---
id: lsp
title: lsp
summary: Starts the LSP (Language Server Protocol) stdio server
product: DL
group: editor-integration
order: 110009
since: 0.6.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# lsp

Starts the LSP (Language Server Protocol) stdio server.

Read this when you want hover, completion, go-to-definition and diagnostics in an editor other than RAD Studio. It starts the language server over stdio; the IDE plugin launches it by itself, and it is not the same as the MCP server (serve) used by AI clients.

## How to run it

Full flag list: [lsp in the CLI reference](../cli.md#lsp).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--stdio` |  |  |  |
| `--clientProcessId` |  |  |  |
| `--proxy` |  |  |  |
| `--delphi-lsp` | `<path>` |  |  |
| `--trace` | `<file>` |  |  |

**Needs:** index

## Details

Starts the LSP (Language Server Protocol) stdio server. This is what the IDE
plugin itself launches to get hover, completion, go-to-definition and
diagnostics inside the editor.

`lsp` is DIFFERENT from `serve`: `serve` is the MCP stdio server for AI
clients such as Claude or Cursor, and nothing in the IDE uses `serve`. The
IDE plugin uses `lsp`.

### Running it from the CLI

```text
drag-lint lsp --db <file.sqlite>
```

### Reaching it in the IDE

CLI+internal: the plugin starts this process itself, from
`DragLint.Plugin.LspClient.pas:297`. There is no menu item -- the IDE
launches the `lsp` server automatically as a background stdio process, not
via a user-facing command.

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative only:

```text
drag-lint lsp --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This is the same command the plugin runs in the background to serve the
editor's language features for `MyApp`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
