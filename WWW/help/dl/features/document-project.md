---
id: document-project
title: Document project
summary: Generates or repairs managed DocInsight comments for every public declaration the project owns, starting from a Structure-tree node's project
product: DL
group: documentation
order: 40006
since: 0.90.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# Document project

Generates or repairs managed DocInsight comments for every public declaration the project owns, starting from a Structure-tree node's project.

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

* Right-click in the Structure form: **Document project**

## Details

Generates or repairs managed DocInsight comments for every public
declaration the project owns, starting from a Structure-tree node's
project. Reach for it when a whole project needs documentation coverage,
not just one unit or symbol.

### Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Document project".

### Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the whole-project form:

```text
drag-lint document --project <p.dpr|.dproj> [--stubs|--apply|--json|--no-backup|--include-accessors|--reindex|--document-third-party] [--db PATH]
```

Documents every public declaration the project owns (scope: the compile
closure restricted to the project's own roots). `--reindex` self-freshens
the index afterward so hover/LSP are correct immediately.

### What it needs

Optional, per the feature map's Index column.

### Example

Illustrative:

```text
drag-lint document --project C:\Projects\MyApp\MyApp.dproj --apply --reindex --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write managed DocInsight comments across the whole project and
refresh the index afterward.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
