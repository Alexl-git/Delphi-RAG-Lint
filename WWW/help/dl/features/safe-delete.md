---
id: safe-delete
title: safe-delete
summary: Deletes a symbol if and only if it has zero references in the index
product: DL
group: refactoring
order: 50011
since: 0.69.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# safe-delete

Deletes a symbol if and only if it has zero references in the index.

Read this when you want to remove dead code without breaking a live caller: safe-delete deletes a symbol only if the index shows zero references to it.

## How to run it

Full flag list: [safe-delete in the CLI reference](../cli.md#safe-delete).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<QName>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |
| `--db` | `<db>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Safe Delete Symbol...**

**Needs:** index

## Details

Deletes a symbol if and only if it has zero references in the index. Reach
for it to remove dead code with a guarantee against breaking a live caller.

### Running it from the CLI

```text
drag-lint safe-delete --name <QName> [--json|--apply|--no-backup] --db <db>
```

`--name` is the qualified symbol name to delete. `--db` is required (not
bracketed in the usage line). The usage line lists `--apply` as a flag;
whether omitting it produces a dry run is not documented in the help text
for this verb.

### Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative:

```text
drag-lint safe-delete --name Unit1.TMyClass.OldHelper --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would delete `TMyClass.OldHelper` only if the index shows zero
references to it.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
