---
id: uses-report-csv
title: Uses Report (CSV)
summary: Exports the project's unit-dependency data as a CSV file
product: DL
group: graphs-reports
order: 70019
since: 0.40.5-alpha
status: shipped
updated: 0.40.5-alpha
---

# Uses Report (CSV)

Exports the project's unit-dependency data as a CSV file.

## How to run it

Full flag list: [uses-report in the CLI reference](../cli.md#uses-report).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--output` | `<out.csv>` |  |  |
| `--db` |  |  |  |
| `--depth` | `N` |  |  |
| `--include-external` |  |  |  |
| `--all-sources` |  |  |  |
| `--name` | `<pattern>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Uses Report (CSV)...**

## Details

Exports the project's unit-dependency data as a CSV file. Reach for it when
you need the `uses` graph outside the IDE -- in a spreadsheet or another tool.

### Running it from the CLI
```text
drag-lint uses-report --output <out.csv> [--db ...] [--depth N] [--include-external] [--all-sources] [--name <pattern>]
```
`--output` is where the CSV is written; `--depth` bounds how far the report
follows dependencies; `--include-external` adds units outside the project;
`--all-sources` and `--name <pattern>` broaden or filter the scope.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Uses Report (CSV)...

### What it needs
Optional. An index is not required per the feature map, but the report is
built from indexed data, so results depend on what has been indexed.

### Example
Illustrative only:
```text
drag-lint uses-report --output C:\Projects\MyApp\uses-report.csv --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --depth 2
```
This would write a CSV of unit dependencies up to 2 levels deep, which could
include the unit that declares `TCustomerOrder`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
