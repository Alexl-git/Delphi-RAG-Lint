---
id: query-ancestors
title: query ancestors
summary: Resolves the transitive class/interface hierarchy of a type
product: DL
group: search-navigation
order: 20018
since: 0.1.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# query ancestors

Resolves the transitive class/interface hierarchy of a type.

Read this to see everything a class or interface descends from, or to check whether it descends from one specific ancestor. The answer comes straight from the index.

## How to run it

Full flag list: [query in the CLI reference](../cli.md#query).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<type>` |  |  |
| `--of` | `<ancestor>` |  |  |
| `--db` |  |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Inspect Symbol > Ancestors of Type (full chain)...**
   1. Needs an index of the project
   2. drag-lint > Inspect Symbol > Ancestors of Type (full chain)...
   3. Enter the type; its ancestor chain is listed

## Details

Resolves the transitive class/interface hierarchy of a type. Reach for it
to see everything a type descends from -- or to check whether it descends
from one specific ancestor -- read straight from the index.

### Running it from the CLI

```text
drag-lint query ancestors --name <type> [--of <ancestor>] [--db ...] [--json]
```

`--name` is the type to resolve. `--of <ancestor>` narrows the query to a
specific ancestor.

### What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example

Illustrative:

```text
drag-lint query ancestors --name TMyForm --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would list `TMyForm`'s full transitive ancestor chain.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
