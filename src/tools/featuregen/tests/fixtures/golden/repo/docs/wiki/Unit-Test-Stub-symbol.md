# Unit Test Stub (symbol)

Uses `generate-test` to produce a unit-test skeleton for one qualified
symbol. Reach for it to scaffold a test file for a routine that has none.

## Running it from the CLI
```
drag-lint generate-test --qname <Foo.TBar.Baz> [--framework dunitx|dunit] [--db PATH]
```
`--qname` is the fully qualified symbol; `--framework` selects `dunitx` or
`dunit`.

## Reaching it in the IDE
drag-lint > Generate & Export > Unit Test Stub (symbol)...

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint generate-test --qname MyApp.TCustomerOrder.Total --framework dunitx --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would produce a DUnitX test stub targeting the `Total` member of
`TCustomerOrder`.
