---
id: call-graph-butterfly
title: Call Graph (Butterfly)
summary: "Shows callers and callees of one symbol together in a single \"butterfly\" view"
product: DL
group: graphs-reports
order: 70002
since: 0.96.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Call Graph (Butterfly)

Shows callers and callees of one symbol together in a single "butterfly" view.

Read this when you want to see who calls a symbol and what it calls together, in one butterfly view, from the IDE menu. The same chart is available from the CLI with the butterfly verb.

## How to run it

Full flag list: [reverse-calltree in the CLI reference](../cli.md#reverse-calltree).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<X>` |  |  |
| `--direction` |  |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Call Graph (Butterfly)...**
   1. Choose drag-lint > Uses & Dependencies > Call Graph (Butterfly)...
   2. Type the qualified name of the routine in the prompt (the menu item asks for it and does not read the caret; Ctrl+Alt+B opens the same prompt)
   3. The callers (upward wing) and callees (downward wing) open together in the Call Graph view

**Needs:** index

## Details

Shows callers and callees of one symbol together in a single "butterfly"
view. Reach for it to see both directions of a symbol's call graph at once.

### Running it from the CLI
There are two ways to get this chart, and they are genuinely different --
this is a deliberate asymmetry, not a duplicate.

The `butterfly` verb composes both wings in ONE command:
```text
drag-lint butterfly --qname <X> [--depth N] [--format dot|mermaid|text|json] [--output F] --db PATH [--db ...]
```

The IDE menu item does NOT call `butterfly`. It runs `reverse-calltree`
TWICE -- once for callers, once with `--direction callees` -- and composes
the two JSON documents itself into the dock's Call Graph tab:
```text
drag-lint reverse-calltree --qname <X> --db <db> --depth 3 --format json
drag-lint reverse-calltree --qname <X> --db <db> --depth 3 --format json --direction callees
```

So `butterfly` is CLI-only: no IDE action invokes it. If you want the chart
from a script, `butterfly` is the single-command option.

### What it needs
An index IS required -- both `butterfly` and the two `reverse-calltree`
calls the IDE composes it from read the project's index database. The
project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if you are unsure which one.

### Example
Illustrative only:
```text
drag-lint reverse-calltree --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format dot
```
This would produce a DOT-format graph touching the `Total` member of
`TCustomerOrder`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
