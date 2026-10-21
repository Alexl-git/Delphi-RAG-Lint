---
id: show-in-call-graph
title: Show in Call Graph
summary: Opens the call graph rooted at the symbol represented by a Structure-tree node
product: DL
group: graphs-reports
order: 70017
since: 0.96.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Show in Call Graph

Opens the call graph rooted at the symbol represented by a Structure-tree node.

Read this when you are looking at a symbol in the Structure outline and want to see who calls it or what it calls: right-click the node to open the call graph rooted there.

## How to run it

Full flag list: [reverse-calltree in the CLI reference](../cli.md#reverse-calltree).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--direction` |  |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* Right-click in the Structure form: **Show in Call Graph**

**Needs:** index

## Details

Opens the call graph rooted at the symbol represented by a Structure-tree
node. Reach for it when you want to see who calls (or is called by) a
symbol you are already looking at in the Structure outline.

### Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Show in Call Graph".

### Running it from the CLI

The feature map lists the underlying verb as `reverse-calltree`. From the
usage banner:

```text
drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...]
```

callers = who calls X (default), callees = what X calls; cycle-guarded.

### What it needs

An index IS required -- `reverse-calltree` reads the project's index
database. The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`; run `drag-lint resolve-dbs --project <X.dproj>` if you are
unsure which one.

### Example

Illustrative:

```text
drag-lint reverse-calltree --qname Unit1.TMyClass.DoWork --direction callers --depth 2 --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format text
```

This would print the callers of `DoWork`, two levels deep.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
