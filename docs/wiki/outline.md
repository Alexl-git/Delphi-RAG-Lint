# outline

Prints the file-scoped symbol outline for one Pascal unit. Reach for it when
you want a unit's symbol list outside the IDE, or want to understand what
feeds the Structure tree.

## Running it from the CLI
```
drag-lint outline --file <path.pas> [--db <path>] [--format text|json]
```
`--file <path.pas>` is the unit to outline. `--db <path>` is optional;
without it the exe falls back to its own default DB resolution. `--format`
selects `text` or `json`.

## Reaching it in the IDE
No menu item calls this directly. The plugin's structure cache
(StructureCache.pas:338) shells out to this verb to populate the Structure
form/tree used by "Show Structure" and the drag-lint Panel (dockable),
caching the result per file.

## What it needs
Optional, per the feature map's Index column.

## Example
Illustrative only:
```
drag-lint outline --file C:\Projects\MyApp\frmOrders.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```
This would print the symbol outline of `frmOrders.pas` as JSON -- the same
data the Structure form displays as a tree.
