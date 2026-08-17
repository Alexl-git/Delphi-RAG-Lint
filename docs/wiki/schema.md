# schema

Prints the live schema of an index database: schema_version, every table
and column, and row counts. Reach for it when you need to know exactly what
an index DB contains before querying it, or to check its schema_version.

## Running it from the CLI

```
drag-lint schema --db <file.sqlite> [--format text|json] [--output <file>]
```

Read-only.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint schema --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```

This would print `MyApp`'s index schema -- version, tables, columns, and row
counts -- as JSON.
