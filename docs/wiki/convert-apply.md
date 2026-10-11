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

## Cast links in code (1.27.0)
A `#link To <- From : Cast` converts the `.dfm` as before, but never rewrites
a `.pas` access site: a cast's `pas` template is a statement, and there is no
correct place to put a statement inside an expression such as
`pic1.Picture.Data := 'seed'`. Each such site is left as it is and reported
as a `cast-not-applied` warning naming the file, line, instance and cast --
"convert this access site by hand". The unit will not compile until you do;
that compile error is the signal.

## StripDB: dropping a Paradox .db (1.27.0)
`#link TableName <- TableName : StripDB` (with `--castlib` pointing at the
shipped `casts.castlib`) turns `'MET1.db'` into `'MET1'` -- in the `.dfm`, and
in code where the table name is assigned one plain string. Anything else in
code (a concatenation, a variable, a read) is left alone and listed as a
warning to check by hand. Values without `.db` are never touched.

## What is left to convert (1.27.0)
Every run also lists what the unit's code still uses: each member reached
through a converted instance, and each global from a unit the run removes.
JSON `pas_uses[]` gives one row per member with its kind, where it is declared,
its lines and a status -- `mapped`, `cast-refused`, `same-name` (the new type
has the same name, so it carries over), `unmapped` (no rule and no such member:
your work list) or `global-dangling`. Text mode prints a one-line count and
the unmapped members with their lines.

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
