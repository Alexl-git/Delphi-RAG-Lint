---
id: butterfly
title: butterfly
summary: Composes a symbol's callers (upward wing) and callees (downward wing) into one combined chart in a single command
product: DL
group: graphs-reports
order: 70001
since: 0.99.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# butterfly

Composes a symbol's callers (upward wing) and callees (downward wing) into one combined chart in a single command.

## How to run it

Full flag list: [butterfly in the CLI reference](../cli.md#butterfly).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--output` | `F` |  |  |
| `--db` | `PATH` |  |  |

**Needs:** index

## Details

Composes a symbol's callers (upward wing) and callees (downward wing) into
one combined chart in a single command. Reach for it when you want the full
two-directional call graph of a symbol without running two separate
queries.

### Running it from the CLI
```text
drag-lint butterfly --qname <X> [--depth N] [--format dot|mermaid|text|json] [--output F] --db PATH [--db ...]
```
`--qname <X>` is the symbol to center the chart on. `--depth N` bounds how
far each wing walks. `--format` selects `dot` (the default), `mermaid`,
`text`, or `json`. `--output F` writes the chart to a file instead of
stdout. `--db PATH` may be repeated.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature. The IDE's "Call Graph
(Butterfly)..." menu item does NOT call this verb: it runs
`reverse-calltree` twice instead (once plain for callers, once with
`--direction callees`) and composes the two results itself into the dock's
Call Graph tab. See [Call Graph (Butterfly)](call-graph-butterfly.md) for that
path.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint butterfly --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format dot
```
This would produce one DOT chart showing both who calls `Total` and what
`Total` calls.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
