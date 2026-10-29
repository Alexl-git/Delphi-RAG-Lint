---
id: purge-locals
title: purge-locals
summary: "A size escape hatch for an index database that has grown too large: it drops local-variable and parameter symbols and runs VACUUM to reclaim space"
product: DL
group: indexing
order: 10006
since: 0.91.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# purge-locals

A size escape hatch for an index database that has grown too large: it drops local-variable and parameter symbols and runs VACUUM to reclaim space.

Read this when an index database has grown larger than you want and you do not need per-local symbol lookups right now. It drops local-variable and parameter symbols and runs VACUUM; the call graph is unchanged and the symbols return on the next index.

## How to run it

Full flag list: [purge-locals in the CLI reference](../cli.md#purge-locals).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Index & Maintenance > Shrink Index (purge locals)...**
   1. drag-lint > Index & Maintenance > Shrink Index (purge locals)...
   2. It runs as a queued job with the LSP stopped; the next index run restores the dropped rows

**Needs:** index

## Details

A size escape hatch for an index database that has grown too large: it drops
local-variable and parameter symbols and runs VACUUM to reclaim space. Reach
for it when a DB file is bigger than you want and you don't need per-local
symbol lookups right now.

No data is lost for good: the call graph is unchanged, and the dropped
local-variable/parameter rows are simply re-inflated the next time you
index.

### Running it from the CLI

```text
drag-lint purge-locals --db PATH [--json]
```

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative only:

```text
drag-lint purge-locals --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```

This would drop `MyApp`'s local-variable/parameter symbol rows and VACUUM
the database, without touching the call graph.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
