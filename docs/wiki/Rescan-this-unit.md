# Rescan this unit

Re-indexes the active project and re-lints the current unit NOW, so the
Diagnostics panel shows findings computed against the code as it is. Reach
for it when the panel still shows a finding you have already fixed.

## Why a panel can lag

The live lint re-runs after every EDIT. Some rules, though, read the project
INDEX rather than the buffer -- `unused-unit-in-uses`, for example, reads the
indexed uses graph -- and a save is not an edit. Since 2026-10-13 the plugin
re-lints automatically when the reindex that follows a save finishes; this
item is the on-demand version of the same step, for when you do not want to
wait or auto-reindex is switched off.

## How the panel stays current on its own

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

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

Open the Structure form (drag-lint > Show Structure), right-click any node and
choose "Rescan this unit" -- or press the **Refresh** button beside **Diag**,
which re-reads the panel and then does the same rescan. It runs in the background on the drag-lint job
queue; the dock's status strip shows it while it works, and the panel updates
when the re-lint lands.

## Running it from the CLI

The two steps it performs:

```
drag-lint index --project <App.dproj> --db <project.sqlite>
drag-lint lint <Unit.pas> --db <project.sqlite>
```

The reindex is INCREMENTAL (only changed files are re-parsed). Resolve the
project's database with `drag-lint resolve-dbs --project <App.dproj>`.

## What it needs

An active project whose index the plugin knows (the same project and database
a save reindexes). With no active project it only re-lints the buffer.