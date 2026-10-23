---
id: top-symbols-fan-in
title: Top Symbols (fan-in)
summary: Ranks indexed symbols by fan-in -- how many places reference them
product: DL
group: graphs-reports
order: 70019
since: 0.6.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Top Symbols (fan-in)

Ranks indexed symbols by fan-in -- how many places reference them.

Read this before refactoring a heavily used symbol: top ranks indexed symbols by fan-in, meaning how many places reference them, so you see the most depended-upon ones first.

## How to run it

Full flag list: [top in the CLI reference](../cli.md#top).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--by` |  |  |  |
| `--limit` | `N` |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Top Symbols (fan-in)...**
   1. Choose drag-lint > Code Quality > Top Symbols (fan-in)...
   2. Read the ranking of symbols by number of references
   3. From a shell: `drag-lint top --db <file.sqlite> [--by fanin] [--limit N] [--json]`

**Needs:** index

## Details

Ranks indexed symbols by fan-in -- how many places reference them. Reach for
it to see the most depended-upon symbols before refactoring one of them.

### Running it from the CLI
```text
drag-lint top --db <file.sqlite> [--by fanin] [--limit N] [--json]
```
`--by fanin` selects the ranking metric (the only value shown in the usage
banner); `--limit` caps how many rows are returned; `--json` emits JSON.

### Reaching it in the IDE
drag-lint > Code Quality > Top Symbols (fan-in)...

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint top --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --by fanin --limit 20
```
This would list `MyApp`'s 20 highest fan-in symbols.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
