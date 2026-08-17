# Rename Symbol...

Renames a symbol across the whole indexed project. Reach for it instead of
a text find/replace when a symbol appears in many units, so every
reference is updated together.

## Reaching it in the IDE
drag-lint > Rename Symbol...

Keyboard shortcut: Ctrl+Alt+R.

## Running it from the CLI
The feature map's Mechanism column marks this row "delegates" -- the menu
item runs the CLI `rename` verb rather than an in-process edit:
```
drag-lint rename --kind symbol --name <QName> --to <New> [--json|--apply|--no-backup] --db <db>
```
Two related forms also exist: `--kind param --file <F> --line <L> --col <C>
--to <New> [...]` for a routine-local parameter/var rename, and
`--qname <Foo.TBar.Baz> --to <NewName> [--db PATH] [--dry-run] [--no-backup]`.
Without `--apply` (or with `--dry-run`), the run is a preview only.

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint rename --kind symbol --name CustomerOrder.TCustomerOrder.Total --to GrandTotal --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --apply
```
This would rename `Total` to `GrandTotal` everywhere it is referenced in
the index.
