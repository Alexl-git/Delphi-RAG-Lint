---
id: callgraph
title: callgraph
summary: Prints an N-deep resolved call tree for a symbol, in either direction
product: DL
group: graphs-reports
order: 70003
since: 0.91.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# callgraph

Prints an N-deep resolved call tree for a symbol, in either direction.

## How to run it

Full flag list: [callgraph in the CLI reference](../cli.md#callgraph).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--direction` |  |  |  |
| `--depth` | `N` |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

**Needs:** index

## Details

Prints an N-deep resolved call tree for a symbol, in either direction.
Reach for it to see who calls a routine or what a routine calls, several
levels deep, from the CLI.

### Running it from the CLI
```text
drag-lint callgraph --qname <X> [--direction callers|callees] [--depth N] --db PATH [--json]
```
`--qname <X>` is the symbol to root the tree on. `--direction` selects
`callers` or `callees` (which one is the default is not documented in the
usage line). `--depth N` bounds how deep the tree walks; the tree is
cycle-guarded. `--json` emits machine-readable output.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint callgraph --qname CustomerOrder.TCustomerOrder.Total --direction callers --depth 3 --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would print the 3-deep tree of everything that (transitively) calls
`Total`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
