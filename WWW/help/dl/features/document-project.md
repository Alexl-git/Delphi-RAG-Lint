---
id: document-project
title: Document project
summary: Generates or repairs managed DocInsight comments for every public declaration of the active project, started from the Structure form right-click menu
product: DL
group: documentation
order: 40006
since: 0.90.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# Document project

Generates or repairs managed DocInsight comments for every public declaration of the active project, started from the Structure form right-click menu.

Read this when a whole project needs documentation coverage. Right-click anywhere in the Structure form and choose Document project to generate or repair managed DocInsight comments for every public declaration of the active project (it runs document --project --apply).

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
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click a node in the tree
   3. Choose Document project; managed DocInsight comments are generated or repaired for every public declaration the project owns

## Details

Generates or repairs managed DocInsight comments for every public
declaration the project owns, starting from a Structure-tree node's
project. Reach for it when a whole project needs documentation coverage,
not just one unit or symbol.

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
