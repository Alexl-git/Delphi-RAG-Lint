# Type at Cursor

Resolves the static type of the expression under the editor caret. Reach
for it when you are not sure what type an expression evaluates to.

## Reaching it in the IDE
drag-lint > Inspect Symbol > Type at Cursor

No keyboard shortcut is documented for this menu item.

## Running it from the CLI
```
drag-lint typeat <file>:<line>:<col> [--db <file.sqlite>] [--format text|json]
```
The position is given as `<file>:<line>:<col>`; `--format` selects text or
JSON.

When the index holds a stored type for the reference at that position (the
`ref_types` table, from 1.44), the answer adds it: a `StaticType:` line in
text, `static_type` and `static_type_via` in JSON. `Resolved:` names the symbol,
`StaticType:` the type the reference has: on `TThing.Create` the resolved symbol
may be an inherited `TBase.Create` while the static type is `TThing`. An older
index has no such table and gets the rest of the answer unchanged. See
[schema](schema).

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint typeat C:\Projects\MyApp\Orders.pas:42:15 --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would report the static type of the expression at line 42, column 15
of `Orders.pas`.
