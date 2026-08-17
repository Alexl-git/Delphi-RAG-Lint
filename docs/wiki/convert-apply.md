# convert-apply

Locates `.dfm` component instances that match a `#convert` rule from a
conversion-rules file and rewrites all five surfaces: declaration retype,
uses-add, `.dfm` re-emit, property/event access-site rewrite, and
runtime-creator retype/TODO markers. Reach for it to actually perform a
component-type conversion, after validating and scaffolding the rules file.

## Running it from the CLI
```
drag-lint convert-apply --unit <F.pas> --rules <file> --db PATH [--db ...] [--only Name1,Name2,...] [--apply] [--no-backup]
```
`--unit <F.pas>` is the unit to convert. `--rules <file>` is the
conversion-rules file. `--only Name1,Name2,...` restricts the conversion to
named component instances. Without `--apply` this is dry-run only: a preview
that writes nothing. `--apply` writes for real, with backups and a
`recovery.txt`, unless `--no-backup` is also given. `--db PATH` is required
and may be repeated.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
An index IS required -- `convert-apply` reads the project's index database.
The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`;
run `drag-lint resolve-dbs --project <X.dproj>` if you are unsure which one.

## Example
Illustrative only:
```
drag-lint convert-apply --unit C:\Projects\MyApp\frmOrders.pas --rules C:\Projects\MyApp\convert-rules\OvcTable-to-cxGrid.rules --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --only tblOrders
```
This would preview (no `--apply`) the conversion of the `tblOrders` component
in `frmOrders.pas` across all five surfaces, without writing any changes.
