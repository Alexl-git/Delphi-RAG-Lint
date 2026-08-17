# convert-scaffold

Auto-generates a valid conversion-rules file from the real property trees of a
from-type and a to-type: a concrete `#link` where exactly one source property
matches by leaf-name and type, a `???` marker for ambiguous matches, and a
`DROPPED` note for orphaned source properties. Reach for it to get a starting
rules file instead of writing one by hand.

## Running it from the CLI
```
drag-lint convert-scaffold --from <FromType> --to <ToType> [--out <file>] [--surface dfm|pas] --db PATH [--db ...]
```
`--from`/`--to` name the source and target types. `--out <file>` is where the
generated rules file is written. `--surface` picks the TO-side target bar:
default `dfm` (published properties only) or `pas` (published + public,
including public fields). A target with `is_writable=false` is never
auto-linked on either surface. `--db PATH` is required and may be repeated.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
An index IS required -- `convert-scaffold` reads the project's index
database. The project's DB lives at `<project folder>\_D-RAG\<project
file>.sqlite`; run `drag-lint resolve-dbs --project <X.dproj>` if you are
unsure which one.

## Example
Illustrative only:
```
drag-lint convert-scaffold --from TOvcTable --to TcxGrid --out C:\Projects\MyApp\convert-rules\OvcTable-to-cxGrid.rules --surface dfm --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would write a starting conversion-rules file linking `TOvcTable`
properties to `TcxGrid` properties on the DFM surface, flagging ambiguous or
orphaned properties for review.
