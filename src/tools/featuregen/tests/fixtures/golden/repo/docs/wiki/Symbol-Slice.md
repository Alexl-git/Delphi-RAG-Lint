# Symbol Slice...

Shows the slice of code relevant to one symbol: its declaration, body, and
immediate context. Reach for it to see just what matters for a symbol
instead of the whole file.

## Reaching it in the IDE
drag-lint > Inspect Symbol > Symbol Slice...

No keyboard shortcut is documented for this menu item.

## Running it from the CLI
```
drag-lint slice --qname <Foo.TBar> [--db <file.sqlite>] [--format text|json]
```
`--qname` is the fully qualified symbol; `--format` selects text or JSON.

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint slice --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would print the declaration, body, and immediate context of the
`Total` member.
