---
id: dump-call-edges
title: dump-call-edges
summary: Diagnostic that dumps every resolved call edge in the index as refid|targetqname|confidence rows
product: DL
group: maintenance
order: 120005
since: 0.91.0-alpha
status: shipped
updated: 0.91.0-alpha
---

# dump-call-edges

Diagnostic that dumps every resolved call edge in the index as refid|targetqname|confidence rows.

## How to run it

Full flag list: [dump-call-edges in the CLI reference](../cli.md#dump-call-edges).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `PATH` |  |  |

**Needs:** index

## Details

Diagnostic that dumps every resolved call edge in the index as
`ref_id|target_qname|confidence` rows. Reach for it when you need to inspect
the raw call-resolution output behind `callgraph`, `find-callees`, or
`call-path`.

### Running it from the CLI
```text
drag-lint dump-call-edges --db PATH
```
No further flags are documented in the usage line.

This is labeled a "diagnostic" in the CLI banner -- it is a troubleshooting
tool, not a daily driver.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint dump-call-edges --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would print every resolved call edge in the index as
`ref_id|target_qname|confidence` rows.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
