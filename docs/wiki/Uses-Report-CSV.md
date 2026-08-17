# Uses Report (CSV)

Exports the project's unit-dependency data as a CSV file. Reach for it when
you need the `uses` graph outside the IDE -- in a spreadsheet or another tool.

## Running it from the CLI
```
drag-lint uses-report --output <out.csv> [--db ...] [--depth N] [--include-external] [--all-sources] [--name <pattern>]
```
`--output` is where the CSV is written; `--depth` bounds how far the report
follows dependencies; `--include-external` adds units outside the project;
`--all-sources` and `--name <pattern>` broaden or filter the scope.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Uses Report (CSV)...

## What it needs
Optional. An index is not required per the feature map, but the report is
built from indexed data, so results depend on what has been indexed.

## Example
Illustrative only:
```
drag-lint uses-report --output C:\Projects\MyApp\uses-report.csv --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --depth 2
```
This would write a CSV of unit dependencies up to 2 levels deep, which could
include the unit that declares `TCustomerOrder`.
