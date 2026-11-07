# Export Graph (DOT)

Uses `graph` to export the indexed call/reference graph in DOT format,
either whole or rooted at a name substring. Reach for it to visualize
dependency structure with Graphviz.

## Running it from the CLI
```
drag-lint graph --db <file.sqlite> [--format dot|mermaid|json|html] [--name <root-substr>] [--output <file>]
```
`--format` selects `dot`, `mermaid`, `json` (`drag-lint.graph/1`: an edges list of from/to/weight) or `html` (one self-contained page); `--name` roots the graph at a
substring match; `--output` writes to a file instead of stdout.

## Reaching it in the IDE
drag-lint > Generate & Export > Export Graph (DOT)...

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint graph --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format dot --name TCustomerOrder --output order.dot
```
This would write a DOT graph rooted around `TCustomerOrder` to `order.dot`.
