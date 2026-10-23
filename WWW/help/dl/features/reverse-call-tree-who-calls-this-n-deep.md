---
id: reverse-call-tree-who-calls-this-n-deep
title: Reverse Call Tree (who calls this, N-deep)
summary: Builds the tree of callers of a chosen symbol, transitively, to a chosen depth
product: DL
group: graphs-reports
order: 70015
since: 0.96.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Reverse Call Tree (who calls this, N-deep)

Builds the tree of callers of a chosen symbol, transitively, to a chosen depth.

Read this before changing a routine and you want to know how far the change could ripple back through its callers: it builds the tree of callers to the depth you choose, or the callees with --direction callees.

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

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)...**
   1. Put the caret on the routine in the editor
   2. Choose drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)...
   3. Pick the depth and read the tree of callers
   4. From a shell: `drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N]`

**Needs:** index

## Details

Builds the tree of callers of a chosen symbol, transitively, to a chosen
depth. Reach for it to see how far a change to one routine could ripple
backward through its callers.

### Running it from the CLI
```text
drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...]
```
Default direction is `callers` (who calls X); `--direction callees` instead
shows what X calls. `--depth` bounds the tree; `--format` selects text, json,
dot, or mermaid output. The command is cycle-guarded.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)...

### What it needs
An index IS required -- `reverse-calltree` reads the project's index
database. The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`; run `drag-lint resolve-dbs --project <X.dproj>` if you are
unsure which one.

### Example
Illustrative only:
```text
drag-lint reverse-calltree --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --depth 2
```
This would show, up to 2 levels deep, who calls the `Total` member of
`TCustomerOrder`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
