---
id: export-graph-dot
title: Export Graph (DOT)
summary: Uses graph to export the indexed call/reference graph in DOT format, either whole or rooted at a name substring
product: DL
group: graphs-reports
order: 70009
since: 0.6.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# Export Graph (DOT)

Uses graph to export the indexed call/reference graph in DOT format, either whole or rooted at a name substring.

Read this when you want a picture of the indexed call/reference graph in Graphviz or Mermaid. drag-lint graph writes DOT (or Mermaid) for the whole index or rooted at a name substring; also on the IDE Generate & Export menu.

## How to run it

Full flag list: [graph in the CLI reference](../cli.md#graph).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--name` | `<root-substr>` |  |  |
| `--output` | `<file>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Export Graph (DOT)...**
   1. Choose drag-lint > Generate & Export > Export Graph (DOT)...
   2. Optionally give a root name substring
   3. The call/reference graph is exported in DOT format

**Needs:** index

## Details

Uses `graph` to export the indexed call/reference graph in DOT format,
either whole or rooted at a name substring. Reach for it to visualize
dependency structure with Graphviz.

### Running it from the CLI
```text
drag-lint graph --db <file.sqlite> [--format dot|mermaid] [--name <root-substr>] [--output <file>]
```
`--format` selects `dot` or `mermaid`; `--name` roots the graph at a
substring match; `--output` writes to a file instead of stdout.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint graph --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format dot --name TCustomerOrder --output order.dot
```
This would write a DOT graph rooted around `TCustomerOrder` to `order.dot`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
