# Full Compile Sweep

Recompiles a project's stale units and refreshes its stored compiler
findings, forcing a full build rather than the default stale-count
threshold. Reach for it when you want a complete, current set of compiler
diagnostics for a project, not just whatever happened to go stale.

## Running it from the CLI
```
drag-lint refresh-findings --project <X.dproj> --db <db> [--full] [--json]
```
`--project` is the `.dproj` to check; `--db` is the project's index
database. Without `--full`, the command only forces a full build once 2
or more units are stale (otherwise it recompiles just the stale ones).
This action runs the verb with `--full` set, forcing a full recompile
every time. `--json` selects JSON output.

## Reaching it in the IDE
drag-lint > Full Compile Sweep

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint refresh-findings --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --full
```
This would force a full recompile of `MyApp.dproj` and refresh its stored
compiler findings.
