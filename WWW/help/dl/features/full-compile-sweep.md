---
id: full-compile-sweep
title: Full Compile Sweep
summary: Recompiles a project's stale units and refreshes its stored compiler findings, forcing a full build rather than the default stale-count threshold
product: DL
group: compiler
order: 90006
since: 1.2.0-alpha
status: shipped
updated: 1.2.0-alpha
---

# Full Compile Sweep

Recompiles a project's stale units and refreshes its stored compiler findings, forcing a full build rather than the default stale-count threshold.

## How to run it

Full flag list: [refresh-findings in the CLI reference](../cli.md#refresh-findings).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<X.dproj>` |  |  |
| `--db` | `<db>` |  |  |
| `--full` |  |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Full Compile Sweep**

**Needs:** index

## Details

Recompiles a project's stale units and refreshes its stored compiler
findings, forcing a full build rather than the default stale-count
threshold. Reach for it when you want a complete, current set of compiler
diagnostics for a project, not just whatever happened to go stale.

### Running it from the CLI
```text
drag-lint refresh-findings --project <X.dproj> --db <db> [--full] [--json]
```
`--project` is the `.dproj` to check; `--db` is the project's index
database. Without `--full`, the command only forces a full build once 2
or more units are stale (otherwise it recompiles just the stale ones).
This action runs the verb with `--full` set, forcing a full recompile
every time. `--json` selects JSON output.

### Reaching it in the IDE
drag-lint > Full Compile Sweep

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint refresh-findings --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --full
```
This would force a full recompile of `MyApp.dproj` and refresh its stored
compiler findings.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
