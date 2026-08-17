# Class Surface...

Shows the public surface of a class: its members and signatures, without
the method bodies. Reach for it to see what a class exposes without
reading the whole unit.

## Reaching it in the IDE
drag-lint > Inspect Symbol > Class Surface...

No keyboard shortcut is documented for this menu item.

## Running it from the CLI
```
drag-lint surface --qname <Foo.TBar> [--db <file.sqlite>] [--include-impl] [--all-visibility] [--format text|json]
```
`--qname` is the fully qualified class; `--include-impl` adds
implementation-only members; `--all-visibility` includes non-public
members; `--format` selects text or JSON.

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint surface --qname CustomerOrder.TCustomerOrder --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would print the public surface of `TCustomerOrder`.
