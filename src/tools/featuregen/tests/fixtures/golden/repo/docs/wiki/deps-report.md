# deps-report

Produces a third-party dependency rollup from an index: which external
units/libraries an indexed codebase depends on. Reach for it when auditing
external dependencies across a project.

## Running it from the CLI

```
drag-lint deps-report --db <file.sqlite> [--db ...] [--depth N] [--edges] [--all-sources] [--name <pat>] [--format text|json|csv] [--output <file>]
```

`--db` may be repeated to roll up dependencies across more than one index.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint deps-report --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format csv --output deps.csv
```

This would write `MyApp`'s third-party dependency rollup to `deps.csv`.
