---
id: document-unit
title: Document unit
summary: Generates or repairs managed DocInsight comments for every public declaration in the unit represented by a Structure-tree node (facts-only)
product: DL
group: documentation
order: 40007
since: 0.90.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Document unit

Generates or repairs managed DocInsight comments for every public declaration in the unit represented by a Structure-tree node (facts-only).

Read this when a whole unit needs documentation, not just one symbol. Right-click the unit in the Structure form and choose Document unit to generate or repair managed DocInsight comments for its public declarations.

## How to run it

Full flag list: [document in the CLI reference](../cli.md#document).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--migrate-pure` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* Right-click in the Structure form: **Document unit**

## Details

Generates or repairs managed DocInsight comments for every public
declaration in the unit represented by a Structure-tree node (facts-only).
Reach for it when a whole unit needs documentation, not just one symbol.

### Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Document unit".

### Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the whole-unit form:

```text
drag-lint document --unit <file.pas> [--apply|--json|--no-backup|--include-accessors] [--db PATH]
```

Documents every public declaration in the unit (facts-only). Trivial
Get*/Set* accessors are skipped unless `--include-accessors` is given.

### What it needs

Optional, per the feature map's Index column.

### Example

Illustrative:

```text
drag-lint document --unit C:\Projects\MyApp\Unit1.pas --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write managed DocInsight comments onto every public declaration
in `Unit1.pas`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
