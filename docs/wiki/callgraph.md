# callgraph

Prints an N-deep resolved call tree for a symbol, in either direction.
Reach for it to see who calls a routine or what a routine calls, several
levels deep, from the CLI.

## Running it from the CLI
```
drag-lint callgraph --qname <X> [--direction callers|callees] [--depth N] --db PATH [--json]
```
`--qname <X>` is the symbol to root the tree on. `--direction` selects
`callers` or `callees` (which one is the default is not documented in the
usage line). `--depth N` bounds how deep the tree walks; the tree is
cycle-guarded. `--json` emits machine-readable output.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint callgraph --qname CustomerOrder.TCustomerOrder.Total --direction callers --depth 3 --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would print the 3-deep tree of everything that (transitively) calls
`Total`.
