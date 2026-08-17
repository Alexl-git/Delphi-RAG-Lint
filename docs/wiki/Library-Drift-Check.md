# Library Drift Check

Flags registered library roots that have source on disk but nothing in the
index. Reach for it to catch a library index that has silently gone stale or
was never built.

## Running it from the CLI
```
drag-lint library-drift [--platform <p>] [--config <path>] [--json]
```
Exits 2 if drift is found. `--platform` scopes the check to `win32` or
`win64`; `--config` points at an alternate manifest.

## Reaching it in the IDE
drag-lint > Index & Maintenance > Library Drift Check...

## What it needs
No index required -- this command has no `--db` flag; it checks the
registered library manifest and what is on disk against what is already
indexed, rather than querying a specific project's index.

## Example
Illustrative only:
```
drag-lint library-drift --platform win64 --json
```
This would report, as JSON, any Win64 library roots that have source on disk
but nothing indexed, exiting 2 if any are found.
