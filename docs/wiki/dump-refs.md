# dump-refs

Diagnostic that dumps every ref in a file together with its
`enclosing_symbol_id` attribution. Reach for it when a reference-derived
answer (callers, doc facts, unused-symbol findings) looks wrong and you
need to see the raw ref rows and which symbol each one was attributed to.

## Running it from the CLI
```
drag-lint dump-refs <file> --db PATH
```
`<file>` is the source file to dump refs for. No further flags are
documented in the usage line.

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
drag-lint dump-refs C:\Projects\MyApp\CustomerOrder.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would print every ref found in `CustomerOrder.pas`, with the symbol ID
each one was attributed to.
