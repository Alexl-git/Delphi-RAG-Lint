# Document unit

Generates or repairs managed DocInsight comments for every public
declaration in the unit represented by a Structure-tree node (facts-only).
Reach for it when a whole unit needs documentation, not just one symbol.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Document unit".

## Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the whole-unit form:

```
drag-lint document --unit <file.pas> [--apply|--json|--no-backup|--include-accessors] [--db PATH]
```

Documents every public declaration in the unit (facts-only). Trivial
Get*/Set* accessors are skipped unless `--include-accessors` is given.

## What it needs

Optional, per the feature map's Index column.

## Example

Illustrative:

```
drag-lint document --unit C:\Projects\MyApp\Unit1.pas --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write managed DocInsight comments onto every public declaration
in `Unit1.pas`.
