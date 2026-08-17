# Show Resolved DBs (debug)

Prints which database(s) drag-lint would actually use for a given project,
file, or platform, without running a real query. Reach for it when a query
seems to be answering from the wrong index.

## Running it from the CLI
```
drag-lint resolve-dbs [--platform win32|win64] [--config <path>] [--json]
drag-lint resolve-dbs --project <file.dproj> [--config <path>] [--json]
drag-lint resolve-dbs --in <file.pas> [--project <file.dproj>] [--config <path>] [--json]
```
The first form prints the consumer DB list `query`/`lsp`/`serve` would use.
`--project` prints the one DB that owns that project -- the write target;
it exits 2 and names the sections if none or several claim it, rather than
guessing. `--in <file.pas>` prints the read list the IDE would open for that
file (the active project's DB first, then the folder-matched DB); omit
`--project` to model "no project active".

## Reaching it in the IDE
drag-lint > Index & Maintenance > Show Resolved DBs (debug)...

## What it needs
No index required -- this command has no `--db` flag; it only resolves and
prints which database(s) drag-lint would use, from config and the manifest,
without querying index content.

## Example
Illustrative only:
```
drag-lint resolve-dbs --project C:\Projects\MyApp\MyApp.dproj --json
```
This would print, as JSON, the one database that owns `MyApp.dproj`.
