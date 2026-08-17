# ambiguous-calls

Resolver-coverage diagnostic that reports call sites the engine could not
pin to exactly one target -- unresolved or ambiguous calls. Reach for it
when you suspect `find-callees`/`callgraph`/call-edge answers are missing
edges because the resolver gave up on some call sites.

## Running it from the CLI
```
drag-lint ambiguous-calls [--qname <Foo.Bar>|--file <file>] --db PATH [--json]
```
Scope the scan to one routine with `--qname`, or to one file with `--file`;
omit both to scan the whole database. `--json` emits machine-readable
output.

This is labeled a "resolver-coverage diagnostic" in the CLI banner -- it is
a troubleshooting tool, not a daily driver.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint ambiguous-calls --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would list call sites targeting `Total` that the resolver could not
resolve to a single certain target.
