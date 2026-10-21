---
id: uses-audit-interface-impl-moves-unused-this-unit
title: Uses Audit -- interface->impl moves + unused (this unit)
summary: For one unit, reports which uses entries could move from the interface section to implementation, and which are unused entirely
product: DL
group: refactoring
order: 50013
since: 0.43.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Uses Audit -- interface->impl moves + unused (this unit)

For one unit, reports which uses entries could move from the interface section to implementation, and which are unused entirely.

Read this when tidying the uses clauses of one unit: it reports which entries could move from the interface section to implementation and which are not used at all.

## How to run it

Full flag list: [uses-audit in the CLI reference](../cli.md#uses-audit).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Uses Audit -- interface->impl moves + unused (this unit)...**

**Needs:** index

## Details

For one unit, reports which `uses` entries could move from the `interface`
section to `implementation`, and which are unused entirely. Reach for it when
cleaning up a single unit's uses clauses before a rename or refactor.

### Running it from the CLI
```text
drag-lint uses-audit <unit.pas> --db <file.sqlite> [--format json|text]
```

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Uses Audit -- interface->impl moves + unused (this unit)...

### What it needs
Required. You must have indexed the project first -- the audit resolves
symbol usage against the index, not by re-parsing the unit alone.

### Example
Illustrative only:
```text
drag-lint uses-audit C:\Projects\MyApp\CustomerOrder.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format text
```
This would report, for `CustomerOrder.pas`, which units in its `uses` clause
(for example one only referenced by a class such as `TCustomerOrder`) could
move to `implementation`, and which are not referenced at all.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
