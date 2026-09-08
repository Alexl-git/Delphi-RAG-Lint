# Reverse Call Tree (clickable, Messages window)

The same reverse call tree, rendered into the IDE's Messages window so each
line navigates to the caller. Reach for it when you want to click through the
callers instead of reading a flat report.

## Running it from the CLI
```
drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...]
```
Same command as the plain Reverse Call Tree; the IDE renders the result into
the clickable Messages window instead of a text report.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)...

then answer **Yes** when it asks where the output should go.

There used to be a second menu item, `Reverse Call Tree (clickable, Messages
window)...`, sitting directly below the first. The two were one report with two
renderers, differing only in where the answer lands -- so the menu was asking
you to choose a renderer before you had seen the answer. They merged in session
78; the destination moved into a dialog. Nothing about the report itself
changed, and both renderers are still there.

## What it needs
An index IS required -- `reverse-calltree` reads the project's index
database. The project's DB lives at `<project folder>\_D-RAG\<project
file>.sqlite`; run `drag-lint resolve-dbs --project <X.dproj>` if you are
unsure which one.

## Example
Illustrative only: invoking this on `CustomerOrder.TCustomerOrder.Total`
would list its callers in the Messages window, each line clickable to jump to
that call site.
