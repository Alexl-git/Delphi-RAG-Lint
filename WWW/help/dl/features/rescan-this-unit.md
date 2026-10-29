---
id: rescan-this-unit
title: Rescan this unit
summary: Re-indexes the active project and re-lints the current unit on demand, so the Diagnostics panel drops findings already fixed
product: DL
group: linting
order: 30020
since: 1.28.3-alpha
status: shipped
updated: 1.38.0-alpha
---

# Rescan this unit

Re-indexes the active project and re-lints the current unit on demand, so the Diagnostics panel drops findings already fixed.

Use it when the Diagnostics panel still shows a finding you have already fixed. Rules such as unused-unit-in-uses read the project index, and a save is not an edit, so this reindexes the project incrementally and re-lints the unit when that lands. Runs in the background; the status strip shows it.

## How to run it

Full flag list: [index in the CLI reference](../cli.md#index).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<file.dproj>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--recompile` |  |  |  |
| `--rebuild` |  |  |  |
| `--dry-run` |  |  |  |
| `--watch` |  |  |  |
| `--interval` | `N` |  |  |

## Where to click

* Right-click in the Structure form: **Rescan this unit**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click in the Structure form and choose Rescan this unit
   3. It reindexes the project in the background and re-lints the unit; the status strip shows progress

## Details

Re-indexes the active project and re-lints the current unit NOW, so the
Diagnostics panel shows findings computed against the code as it is. Reach
for it when the panel still shows a finding you have already fixed.

### Why a panel can lag

The live lint re-runs after every EDIT. Some rules, though, read the project
INDEX rather than the buffer -- `unused-unit-in-uses`, for example, reads the
indexed uses graph -- and a save is not an edit. Since 2026-10-13 the plugin
re-lints automatically when the reindex that follows a save finishes; this
item is the on-demand version of the same step, for when you do not want to
wait or auto-reindex is switched off.

### How the panel stays current on its own

* **After an edit** the unsaved buffer is re-linted about 0.7 s after you stop
  typing, in the background.
* **An edit while a lint is still running CANCELS it**: the running engine is
  stopped and its result is thrown away (it describes text that is gone), and
  the next lint starts after the same short pause. The panel never shows
  findings for an older version of the buffer.
* **After any reindex** -- a save, "Rescan this unit", or a project rebuild
  from the menu -- the unit is re-linted when the reindex lands.
* **Unused-unit findings follow the editor**, not the index: a unit you have
  commented out or deleted from the uses clause is not reported even before
  the reindex, and a finding sits on the line the unit occupies in the buffer.
* **The panel refreshes when the findings change**, not only when their number
  does.

### Running it from the CLI

The two steps it performs:

```text
drag-lint index --project <App.dproj> --db <project.sqlite>
drag-lint lint <Unit.pas> --db <project.sqlite>
```

The reindex is INCREMENTAL (only changed files are re-parsed). Resolve the
project's database with `drag-lint resolve-dbs --project <App.dproj>`.

### What it needs

An active project that exactly ONE manifest section names; that section's
database is the one reindexed (the same resolution a save and Refresh findings
use). With no active project, or no unique owner (none, or two sections
claiming it), nothing is reindexed -- the reason goes to the plugin's telemetry
log -- and only the buffer is re-linted.

Before 1.31.2 the database was the one of the project OPENED LAST, so with two
projects in a group a rescan could write the active project's closure into the
other project's index. The engine now refuses that pairing too: `index --project <X>` into a database stamped for another project exits 2.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
