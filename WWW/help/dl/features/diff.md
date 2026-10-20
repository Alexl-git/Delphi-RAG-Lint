---
id: diff
title: diff
summary: Compares two index databases and reports what changed between them -- for example an index snapshot taken before and after a refactor
product: DL
group: maintenance
order: 120004
since: 0.13.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# diff

Compares two index databases and reports what changed between them -- for example an index snapshot taken before and after a refactor.

## How to run it

Full flag list: [diff in the CLI reference](../cli.md#diff).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<old.sqlite>` |  |  |
| `--json` |  |  |  |

**Needs:** index

## Details

Compares two index databases and reports what changed between them -- for
example an index snapshot taken before and after a refactor. Reach for it
when you want the symbol/reference-level delta between two points in time.

### Running it from the CLI

```text
drag-lint diff --db <old.sqlite> --db <new.sqlite> [--json]
```

### Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

### What it needs

An index IS required -- in fact TWO: `diff` takes exactly two `--db` flags,
one for the "old" database and one for the "new" one, and both must already
exist. Run `drag-lint resolve-dbs --project <X.dproj>` if unsure which DB
covers a given project.

### Example

Illustrative only:

```text
drag-lint diff --db drag-lint-before.sqlite --db drag-lint-after.sqlite --json
```

This would print, as JSON, what changed between the two snapshots.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
