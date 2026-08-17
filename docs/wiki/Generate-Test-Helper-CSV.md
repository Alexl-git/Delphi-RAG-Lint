# Generate Test Helper CSV

Produces a CSV listing of a project's forms, one row per form, for use as
a test-helper navigation map. Reach for it when building or updating
automated UI test scaffolding that needs to enumerate a project's forms.

## Running it from the CLI
```
drag-lint forms-csv --project <X.dproj> --db <file.sqlite> [--out <f.csv>] [--root <TfrmMAIN>]
```
`--project` is the `.dproj` to enumerate forms for; `--db` is the
project's index database; `--out` sets the output CSV path; `--root` sets
the root form to start from.

## Reaching it in the IDE
drag-lint > Generate Test Helper CSV...

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint forms-csv --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --out C:\Projects\MyApp\forms.csv --root TfrmMain
```
This would write one CSV row per form in `MyApp.dproj`, starting from
`TfrmMain`, to `forms.csv`.
