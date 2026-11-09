---
id: export-graph-dot
title: Export Graph (DOT)
summary: Uses graph to export the indexed call/reference graph in DOT format, whole or rooted at a name substring; json and html add the Markdown text nodes
product: DL
group: graphs-reports
order: 70010
since: 0.6.0-alpha
status: shipped
updated: 1.48.0-alpha
---

# Export Graph (DOT)

Uses graph to export the indexed call/reference graph in DOT format, whole or rooted at a name substring; json and html add the Markdown text nodes.

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
drag-lint graph --db <file.sqlite> [--format dot|mermaid|json|html] [--name <root-substr>] [--output <file>]
```
`--format` selects `dot`, `mermaid`, `json` (`drag-lint.graph/1`: an edges list of from/to/weight) or `html` (one self-contained page). `json` and `html` also carry the **Markdown text nodes** of the index: `text_nodes` (one per heading, paragraph or list item of the `.md` files beside the project file: `id`, `file`, `path`, `line`, `kind` md-heading|md-text, `section`, `text`) and `text_edges` (`from` a node `to` the unit declaring a `` `backticked` `` name it mentions, with that `name`; a name declared in more than one file, or in none, makes no edge). In `html` the text nodes are DRAWN as well as listed: one note box per node, a dashed line from each note to the unit box it mentions, a legend (note box = Markdown text node, dashed line = mentions by name, box = unit declaring the name) and a "Show text nodes" checkbox, on by default, that hides or shows the whole layer (pure CSS, no script). An index with no Markdown gets neither the layer nor the checkbox. `--name` roots the graph at a
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
