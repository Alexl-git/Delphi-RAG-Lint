# Export to Obsidian

Uses `export obsidian` to write the indexed project out as a set of Obsidian
vault markdown pages. Reach for it to build a browsable wiki of a project's
symbols.

## Running it from the CLI
```
drag-lint export obsidian --db <file.sqlite> --output-dir <dir> [--open]
```
`--output-dir` is required and names the folder to write pages into; `--open`
opens it after export.

## Reaching it in the IDE
drag-lint > Generate & Export > Export to Obsidian...

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint export obsidian --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --output-dir C:\Projects\MyApp-wiki --open
```
This would write `MyApp`'s indexed symbols as markdown pages into
`C:\Projects\MyApp-wiki` and open the folder afterward.
