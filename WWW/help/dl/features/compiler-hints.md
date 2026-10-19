---
id: compiler-hints
title: Compiler Hints
summary: Uses query hints to surface compiler hint/warning findings that have been imported into the index, filtered by code or severity
product: DL
group: search-navigation
order: 20003
since: 0.1.0-alpha
status: shipped
updated: 0.1.0-alpha
---

# Compiler Hints

Uses query hints to surface compiler hint/warning findings that have been imported into the index, filtered by code or severity.

## How to run it

Full flag list: [query in the CLI reference](../cli.md#query).

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Compiler Hints...**

**Needs:** index

## Details

Uses `query hints` to surface compiler hint/warning findings that have been
imported into the index, filtered by code or severity. Reach for it to
review compiler-reported issues without re-running a build.

### Running it from the CLI
```text
drag-lint query hints --db <file.sqlite> [--name <code>] [--rule <severity>]
```
`--name` filters by hint code; `--rule` filters by severity.

### Reaching it in the IDE
drag-lint > Code Quality > Compiler Hints...

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint query hints --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --rule warning
```
This would list warning-severity compiler hints recorded in `MyApp`'s index.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
