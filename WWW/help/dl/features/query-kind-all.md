---
id: query-kind-all
title: query --kind --all
summary: Lists every symbol of one kind -- every unit, every class, every enum -- with no name, no doc clause and no row cap
product: DL
group: search-navigation
order: 20021
since: 1.19.1-alpha
status: shipped
updated: 1.36.0-alpha
---

# query --kind --all

Lists every symbol of one kind -- every unit, every class, every enum -- with no name, no doc clause and no row cap.

Read this when you need the complete set of one kind of symbol, for example every unit in a project or library index to fill a picker. It lists them all with no name and no row cap.

## How to run it

Full flag list: [query in the CLI reference](../cli.md#query).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<symbol-name>` |  |  |
| `--db` |  |  |  |
| `--json` |  |  |  |
| `--case-sensitive` |  |  |  |
| `--exact` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Pitfalls

* a project DB IS the compile closure, so a hit is membership and a MISS is non-membership.
* STRING LITERALS, DFM, SQL *and COMMENT PROSE* -- // { } (* *) and ///. Filter with --kind: literal|const|resourcestring|format|comment|doc|dfm-prop|sql-exception. --kind literal is what this returned before comments were indexed.

## Details

Lists every symbol of one kind -- every unit, every class, every enum -- with
no name, no doc clause and no row cap. Reach for it when you need the complete
set, for example every unit in a project or library index to fill a picker.

### Running it from the CLI

```text
drag-lint query --kind <kind> --all [--public] [--db ...] [--json]
```

`--kind` is required (`unit`, `class`, `interface`, `record`, `enum`,
`procedure`, `function`, `method`, `property`, `field`, ...). `--public` keeps
only symbols usable from other units. `--json` prints one object per symbol
with its file.

Do not use `query find --no-docs --kind unit` for this: `--no-docs` is a
FILTER that keeps only UNDOCUMENTED symbols. On a library index it listed
2,103 of 5,646 units. `sql` works too, but its default row cap is 200.

### What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example

Illustrative:

```text
drag-lint query --kind unit --all --json --db C:\Projects\.drag-lint\library-Win64.sqlite
```

This would print every unit the Win64 platform library index holds.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
