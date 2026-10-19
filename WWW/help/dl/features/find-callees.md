---
id: find-callees
title: find-callees
summary: Lists the resolved outgoing calls of one routine
product: DL
group: search-navigation
order: 20005
since: 0.91.0-alpha
status: shipped
updated: 0.91.0-alpha
---

# find-callees

Lists the resolved outgoing calls of one routine.

## How to run it

Full flag list: [find-callees in the CLI reference](../cli.md#find-callees).

**Needs:** index

## Details

Lists the resolved outgoing calls of one routine. Reach for it to see what
a routine actually calls, resolved through the call-edge index rather than
by reading its source.

### Running it from the CLI
```text
drag-lint find-callees --qname <Foo.Bar> --db PATH [--json]
```
`--qname <Foo.Bar>` is the routine to inspect. `--json` emits
machine-readable output.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint find-callees --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would list every routine that `Total` resolves calls to.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
