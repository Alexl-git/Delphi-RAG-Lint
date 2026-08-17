# diff

Compares two index databases and reports what changed between them -- for
example an index snapshot taken before and after a refactor. Reach for it
when you want the symbol/reference-level delta between two points in time.

## Running it from the CLI

```
drag-lint diff --db <old.sqlite> --db <new.sqlite> [--json]
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required -- in fact TWO: `diff` takes exactly two `--db` flags,
one for the "old" database and one for the "new" one, and both must already
exist. Run `drag-lint resolve-dbs --project <X.dproj>` if unsure which DB
covers a given project.

## Example

Illustrative only:

```
drag-lint diff --db drag-lint-before.sqlite --db drag-lint-after.sqlite --json
```

This would print, as JSON, what changed between the two snapshots.
