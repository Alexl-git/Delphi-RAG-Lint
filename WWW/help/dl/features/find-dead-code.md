---
id: find-dead-code
title: Find Dead Code
summary: Scans the index for code with no references -- candidates to delete
product: DL
group: graphs-reports
order: 70011
since: 0.25.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Find Dead Code

Scans the index for code with no references -- candidates to delete.

Read this before a cleanup pass or before deleting something you suspect is unused: find-deadcode scans the index for symbols with no references and lists them as candidates. Filter with --kind, add --include-private for private members; also under drag-lint > Code Quality.

## How to run it

Full flag list: [find-deadcode in the CLI reference](../cli.md#find-deadcode).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--kind` |  |  |  |
| `--include-private` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Find Dead Code...**

## Details

Scans the index for code with no references -- candidates to delete. Reach
for it before a cleanup pass or before removing something you suspect is
unused.

### Running it from the CLI
```text
drag-lint find-deadcode [--kind method|function|...] [--include-private] [--db PATH]
```
`--kind` filters by symbol kind (for example `method` or `function`);
`--include-private` also considers private members.

### Reaching it in the IDE
drag-lint > Code Quality > Find Dead Code...

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint find-deadcode --kind method --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would list methods in `MyApp`'s index with no resolved references.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
