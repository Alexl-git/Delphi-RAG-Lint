# doc-drift

Diagnostic that computes deterministic doc-vs-code drift findings for one
symbol. Reach for it to see exactly why `document`/autodoc considers a
symbol's existing doc comment out of date.

## Running it from the CLI
```
drag-lint doc-drift --qname X --db PATH [--json]
```
`--qname X` is the symbol to check. `--json` emits machine-readable output.

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
drag-lint doc-drift --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would report the specific drift findings between `Total`'s current doc
comment and its code.
