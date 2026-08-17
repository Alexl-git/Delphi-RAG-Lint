# Doc Comment Stub (symbol)

Uses `generate-docs` to produce a doc-comment stub for one qualified symbol.
Reach for it to start a DocInsight comment on a specific method, type, or
property.

## Running it from the CLI
```
drag-lint generate-docs --qname <Foo.TBar.Baz> [--format xmldoc|pasdoc] [--db PATH]
```
`--qname` is the fully qualified symbol; `--format` selects `xmldoc` or
`pasdoc` output.

## Reaching it in the IDE
drag-lint > Generate & Export > Doc Comment Stub (symbol)...

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint generate-docs --qname MyApp.TCustomerOrder.Total --format xmldoc --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would produce a doc-comment stub for the `Total` member of
`TCustomerOrder`.
