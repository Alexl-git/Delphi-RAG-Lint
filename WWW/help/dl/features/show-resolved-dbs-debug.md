---
id: show-resolved-dbs-debug
title: Show Resolved DBs (debug)
summary: Prints which database(s) drag-lint would actually use for a given project, file, or platform, without running a real query
product: DL
group: indexing
order: 10010
since: 0.60.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Show Resolved DBs (debug)

Prints which database(s) drag-lint would actually use for a given project, file, or platform, without running a real query.

Read this when a query seems to answer from the wrong index: it prints which database(s) drag-lint would use for a project, a file or a platform, without running a real query.

## How to run it

Full flag list: [resolve-dbs in the CLI reference](../cli.md#resolve-dbs).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--platform` |  |  |  |
| `--config` | `<path>` |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Index & Maintenance > Show Resolved DBs (debug)...**
   1. Choose drag-lint > Index & Maintenance > Show Resolved DBs (debug)...
   2. Read the list of databases it would use; no query is run
   3. From a shell: `drag-lint resolve-dbs [--platform win32|win64] [--config <path>] [--json]`

## Pitfalls

* never guess a DB path. Also --project `<P.dproj>` and --platform `<win32|win64>`.

## Details

Prints which database(s) drag-lint would actually use for a given project,
file, or platform, without running a real query. Reach for it when a query
seems to be answering from the wrong index.

### Running it from the CLI
```text
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

### What it needs
No index required -- this command has no `--db` flag; it only resolves and
prints which database(s) drag-lint would use, from config and the manifest,
without querying index content.

### Example
Illustrative only:
```text
drag-lint resolve-dbs --project C:\Projects\MyApp\MyApp.dproj --json
```
This would print, as JSON, the one database that owns `MyApp.dproj`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
