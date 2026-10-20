# dump-call-edges

Diagnostic that dumps every resolved call edge in the index as
`ref_id|target_qname|confidence` rows. Reach for it when you need to inspect
the raw call-resolution output behind `callgraph`, `find-callees`, or
`call-path`.

## Running it from the CLI
```
drag-lint dump-call-edges --db PATH
```
No further flags are documented in the usage line.

This is labeled a "diagnostic" in the CLI banner -- it is a troubleshooting
tool, not a daily driver.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint dump-call-edges --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would print every resolved call edge in the index as
`ref_id|target_qname|confidence` rows.
