---
id: call-path
title: call-path
summary: Finds the shortest resolved call path from one symbol to another
product: DL
group: search-navigation
order: 20001
since: 0.91.0-alpha
status: shipped
updated: 0.91.0-alpha
---

# call-path

Finds the shortest resolved call path from one symbol to another.

## How to run it

Full flag list: [call-path in the CLI reference](../cli.md#call-path).

**Needs:** index

## Details

Finds the shortest resolved call path from one symbol to another. Reach for
it to answer "does A ever reach B, and how" without manually walking a call
tree.

### Running it from the CLI
```text
drag-lint call-path --from <A> --to <B> [--max-depth N] --db PATH [--json]
```
`--from <A>` and `--to <B>` are qualified symbol names. `--max-depth N`
bounds the search. Exit code 1 means no path was found. `--json` emits
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
drag-lint call-path --from TfrmMain.btnSaveClick --to CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would report the shortest resolved call chain from the button handler
down to `Total`, or exit 1 if no such chain exists.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
