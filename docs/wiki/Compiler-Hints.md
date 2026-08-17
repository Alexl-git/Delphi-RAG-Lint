# Compiler Hints

Uses `query hints` to surface compiler hint/warning findings that have been
imported into the index, filtered by code or severity. Reach for it to
review compiler-reported issues without re-running a build.

## Running it from the CLI
```
drag-lint query hints --db <file.sqlite> [--name <code>] [--rule <severity>]
```
`--name` filters by hint code; `--rule` filters by severity.

## Reaching it in the IDE
drag-lint > Code Quality > Compiler Hints...

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint query hints --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --rule warning
```
This would list warning-severity compiler hints recorded in `MyApp`'s index.
