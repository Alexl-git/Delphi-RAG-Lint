# Document project

Generates or repairs managed DocInsight comments for every public
declaration the project owns, starting from a Structure-tree node's
project. Reach for it when a whole project needs documentation coverage,
not just one unit or symbol.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Document project".

## Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the whole-project form:

```
drag-lint document --project <p.dpr|.dproj> [--stubs|--apply|--json|--no-backup|--include-accessors|--reindex|--document-third-party] [--db PATH]
```

Documents every public declaration the project owns (scope: the compile
closure restricted to the project's own roots). `--reindex` self-freshens
the index afterward so hover/LSP are correct immediately.

## What it needs

Optional, per the feature map's Index column.

## Example

Illustrative:

```
drag-lint document --project C:\Projects\MyApp\MyApp.dproj --apply --reindex --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write managed DocInsight comments across the whole project and
refresh the index afterward.
