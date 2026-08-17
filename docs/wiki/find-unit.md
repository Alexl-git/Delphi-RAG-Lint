# find-unit

Finds which indexed unit declares a symbol, and adds that unit to a file's
`uses` clause. Reach for it when a symbol is undeclared and you want the fix
looked up straight from the index.

## Running it from the CLI

```
drag-lint find-unit --name <Symbol> --in <file> [--json|--apply|--no-backup] --db <db>
```

`--name` is the undeclared symbol; `--in` is the file to add the `uses`
entry to. `--db` is required (not bracketed in the usage line). The usage
line lists `--apply` as a flag; whether omitting it produces a dry run is
not documented in the help text for this verb.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature. It is NOT the same as the
IDE's [Quick-Fix: Add Unit for Undeclared at
Cursor](Quick-Fix-Add-Unit-for-Undeclared-at-Cursor-Ctrl-Alt-U) (Ctrl+Alt+U).
The quick-fix parses a COMPILER DIAGNOSTIC, so it needs a prior build and a
message that already names the unit. `find-unit --name <Symbol>` answers
straight from the index instead, with no prior compile and no existing
diagnostic message required -- it is strictly more capable here.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative:

```
drag-lint find-unit --name TStringList --in C:\Projects\MyApp\Unit1.pas --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would look up which indexed unit declares `TStringList` and add it to
`Unit1.pas`'s `uses` clause.
