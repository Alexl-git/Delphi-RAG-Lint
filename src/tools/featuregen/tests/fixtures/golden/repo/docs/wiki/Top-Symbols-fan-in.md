# Top Symbols (fan-in)

Ranks indexed symbols by fan-in -- how many places reference them. Reach for
it to see the most depended-upon symbols before refactoring one of them.

## Running it from the CLI
```
drag-lint top --db <file.sqlite> [--by fanin] [--limit N] [--json]
```
`--by fanin` selects the ranking metric (the only value shown in the usage
banner); `--limit` caps how many rows are returned; `--json` emits JSON.

## Reaching it in the IDE
drag-lint > Code Quality > Top Symbols (fan-in)...

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint top --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --by fanin --limit 20
```
This would list `MyApp`'s 20 highest fan-in symbols.
