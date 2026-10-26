---
id: ambiguous-calls
title: ambiguous-calls
summary: Resolver-coverage diagnostic that reports call sites the engine could not pin to exactly one target -- unresolved or ambiguous calls
product: DL
group: maintenance
order: 120002
since: 0.91.0-alpha
status: shipped
updated: 1.35.0-alpha
---

# ambiguous-calls

Resolver-coverage diagnostic that reports call sites the engine could not pin to exactly one target -- unresolved or ambiguous calls.

Read this when call-graph or find-callees answers seem to be missing edges. It lists the call sites the resolver could not pin to exactly one target, unresolved or ambiguous, for a symbol or a file, so you can see where the index gave up.

## How to run it

Full flag list: [ambiguous-calls in the CLI reference](../cli.md#ambiguous-calls).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--in` | `<file>` |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

**Needs:** index

## Details

Resolver-coverage diagnostic that reports call sites the engine could not
pin to exactly one target -- unresolved or ambiguous calls. Reach for it
when you suspect `find-callees`/`callgraph`/call-edge answers are missing
edges because the resolver gave up on some call sites.

### Running it from the CLI
```text
drag-lint ambiguous-calls [--qname <Foo.Bar>|--in <file>] --db PATH [--json]
```
Scope the scan to one routine with `--qname`, or to one file with `--in`;
omit both to scan the whole database. `--json` emits machine-readable
output.

This is labeled a "resolver-coverage diagnostic" in the CLI banner -- it is
a troubleshooting tool, not a daily driver.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint ambiguous-calls --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would list call sites targeting `Total` that the resolver could not
resolve to a single certain target.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
