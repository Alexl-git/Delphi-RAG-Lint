# Scan TODOs / FIXMEs

Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers. Reach for it to
triage outstanding work markers left in code.

## Running it from the CLI
```
drag-lint todos [<path>] [--json]
```
`<path>` is optional per the usage banner; `--json` emits JSON instead of
text. No further defaults for an omitted `<path>` are documented.

## Reaching it in the IDE
drag-lint > Code Quality > Scan TODOs / FIXMEs...

## What it needs
No index required -- this command has no `--db` flag; it scans source files
directly for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers.

## Example
Illustrative only:
```
drag-lint todos C:\Projects\MyApp\src --json
```
This would list TODO/FIXME/HACK/XXX/REVIEW/NOTE markers found under
`C:\Projects\MyApp\src`, as JSON.
