# Reverse Call Tree (who calls this, N-deep)

Builds the tree of callers of a chosen symbol, transitively, to a chosen
depth. Reach for it to see how far a change to one routine could ripple
backward through its callers.

## Running it from the CLI
```
drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...]
```
Default direction is `callers` (who calls X); `--direction callees` instead
shows what X calls. `--depth` bounds the tree; `--format` selects text, json,
dot, or mermaid output. The command is cycle-guarded.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)...

## What it needs
An index IS required -- `reverse-calltree` reads the project's index
database. The project's DB lives at `<project folder>\_D-RAG\<project
file>.sqlite`; run `drag-lint resolve-dbs --project <X.dproj>` if you are
unsure which one.

## Example
Illustrative only:
```
drag-lint reverse-calltree --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --depth 2
```
This would show, up to 2 levels deep, who calls the `Total` member of
`TCustomerOrder`.
