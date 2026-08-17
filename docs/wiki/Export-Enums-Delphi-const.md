# Export Enums (Delphi const)

Uses `export enums` with `--format delphi-const` to dump indexed enum types
as Delphi const declarations. Reach for it to generate a const-based mirror
of an enum for interop or codegen.

## Running it from the CLI
```
drag-lint export enums --db <file.sqlite> [--format firebird-sql|csv|json|delphi-const]
```
`--format` selects the output flavor: `firebird-sql`, `csv`, `json`, or
`delphi-const`.

## Reaching it in the IDE
drag-lint > Generate & Export > Export Enums (Delphi const)...

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint export enums --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format delphi-const
```
This would print `MyApp`'s indexed enum types as Delphi const declarations.
