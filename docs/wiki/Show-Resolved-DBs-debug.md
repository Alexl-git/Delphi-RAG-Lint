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

resolve-dbs is read-only and never builds an index. A path that is not built yet stays bare on stdout, so scripts that capture it keep working; stderr carries one line per missing path: `NOTE: <path> (missing) -- not built yet; build it with: <exact command>` (since 1.44). The exit code does not change.

## Reaching it in the IDE
drag-lint > Index & Maintenance > Show Resolved DBs (debug)...

## A reference index for a ported project (IDE plugin)
When a project is being ported from an older code base, the plugin can offer that code base's index as
one more read database, so hover and Find Usages answer names that live only there (since 1.54). It is
read from a per-user file, `%APPDATA%\drag-lint\drag-lint-plugin.ini`; no such database is built in:
```
[Databases]
ReferenceDb=D:\Old\_D-RAG\OldApp.sqlite
ReferenceDbFor=NewApp
```
`ReferenceDb` is the index file. `ReferenceDbFor` is a part of the path of the active project's own index
(case ignored); the reference index is added only when it matches. With the file, either key or the
database absent, nothing is added and nothing is reported. It is never written to.
This plugin list is not what the CLI's `resolve-dbs` prints.
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
