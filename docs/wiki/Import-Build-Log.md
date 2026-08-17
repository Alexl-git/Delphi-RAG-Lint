# Import Build Log

Parses an external dcc or msbuild build log and folds its errors and
warnings into drag-lint's stored findings. Reach for it to bring
diagnostics from a build that ran outside drag-lint (for example a CI
build) into the index.

## Running it from the CLI
```
drag-lint import-log <logfile> --db <file.sqlite>
```
`<logfile>` is the dcc/msbuild log to parse; `--db` is the index database
to write the findings into.

## Reaching it in the IDE
drag-lint > Import Build Log...

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint import-log C:\Projects\MyApp\build.log --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would parse `build.log` and add its errors and warnings to
`MyApp.sqlite`'s stored findings.
