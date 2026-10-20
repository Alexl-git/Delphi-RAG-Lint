# Call Graph (Butterfly)

Shows callers and callees of one symbol together in a single "butterfly"
view. Reach for it to see both directions of a symbol's call graph at once.

## Running it from the CLI
There are two ways to get this chart, and they are genuinely different --
this is a deliberate asymmetry, not a duplicate.

The `butterfly` verb composes both wings in ONE command:
```
drag-lint butterfly --qname <X> [--depth N] [--format dot|mermaid|text|json] [--output F] --db PATH [--db ...]
```

The IDE menu item does NOT call `butterfly`. It runs `reverse-calltree`
TWICE -- once for callers, once with `--direction callees` -- and composes
the two JSON documents itself into the dock's Call Graph tab:
```
drag-lint reverse-calltree --qname <X> --db <db> --depth 3 --format json
drag-lint reverse-calltree --qname <X> --db <db> --depth 3 --format json --direction callees
```

So `butterfly` is CLI-only: no IDE action invokes it. If you want the chart
from a script, `butterfly` is the single-command option.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Call Graph (Butterfly)...

## What it needs
An index IS required -- both `butterfly` and the two `reverse-calltree`
calls the IDE composes it from read the project's index database. The
project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if you are unsure which one.

## Example
Illustrative only:
```
drag-lint reverse-calltree --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format dot
```
This would produce a DOT-format graph touching the `Total` member of
`TCustomerOrder`.
