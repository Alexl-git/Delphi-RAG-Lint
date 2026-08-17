# Impact / Blast Radius (symbol)

Reports what would be affected if a chosen symbol changes -- the set of code
to retest. Reach for it before changing a widely-used method or type.

## Running it from the CLI
```
drag-lint impact --qname <Foo.Bar> [--db <file.sqlite>] [--depth N] [--format text|json]
```
`--qname` is the fully qualified symbol; `--depth` bounds how far impact is
traced; `--format` selects `text` or `json`.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Impact / Blast Radius (symbol)...

## What it needs
Optional. An index is not marked required, but the impact trace is read from
whatever has been indexed, so a stale or missing index gives an incomplete answer.

## Example
Illustrative only:
```
drag-lint impact --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --depth 3
```
This would report what is affected, up to 3 levels out, if the `Total`
member of `TCustomerOrder` changes.
