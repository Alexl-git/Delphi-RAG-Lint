# Reconcile Project Members (.dpr/.dproj)

Compares a project file's declared member list against what is on disk and in
the compile closure, and can also re-scan and recompile every member to heal
the index and findings. Reach for it after moving or adding units by hand.

## Running it from the CLI
```
drag-lint reconcile-project <App.dpr|.dproj> [--apply] [--db <db>] [--full] [--json] [--config <path>]
```
`--apply` writes the sync; without it the command reports only. `--db` also
heals the index and findings for every project member (re-scan + recompile)
without editing the `.dpr`; `--full` forces the recompile even when nothing
looks incoherent.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Reconcile Project Members (.dpr/.dproj)...

## What it needs
Optional. An index is not required to run this command, but pass `--db` to
also heal the index and findings for the project's members.

## Example
Illustrative only:
```
drag-lint reconcile-project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would compare `MyApp.dproj`'s member list against disk and the compile
closure, and re-scan/recompile its members -- one of which might be the unit
that owns `TfrmMain`.
