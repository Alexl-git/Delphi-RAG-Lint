# usages

Finds usage sites of a named symbol, with a choice of report width. Reach for
it when you want a usages listing outside the IDE, or want to understand what
backs the "Usages" search kind in the Symbol Search dialog.

## Running it from the CLI
```
drag-lint usages --name <X> [--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json]
```
`--name <X>` is the symbol to search for. `--width` controls report width
(`narrow`, `wide`, or `very-wide`). `--depth N` is in the usage line with no
further description -- not documented. `--format json` is the only format the
usage line lists.

## Reaching it in the IDE
No main-menu item calls this directly. The "Symbol Search..." dialog
(drag-lint > Symbol Search...) has a "Kind" dropdown with Symbol, Text, and
Usages options; choosing "Usages" and running a search shells out to this
verb (source: SearchForm.pas:155).

## What it needs
Optional, per the feature map's Index column.

## Example
Illustrative only:
```
drag-lint usages --name TCustomerOrder --width wide --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```
This would list usage sites of `TCustomerOrder` as JSON, at "wide" report
width.
