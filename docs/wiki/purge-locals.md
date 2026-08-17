# purge-locals

A size escape hatch for an index database that has grown too large: it drops
local-variable and parameter symbols and runs VACUUM to reclaim space. Reach
for it when a DB file is bigger than you want and you don't need per-local
symbol lookups right now.

No data is lost for good: the call graph is unchanged, and the dropped
local-variable/parameter rows are simply re-inflated the next time you
index.

## Running it from the CLI

```
drag-lint purge-locals --db PATH [--json]
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative only:

```
drag-lint purge-locals --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```

This would drop `MyApp`'s local-variable/parameter symbol rows and VACUUM
the database, without touching the call graph.
