---
id: library-drift-check
title: Library Drift Check
summary: Flags registered library roots that have source on disk but nothing in the index
product: DL
group: maintenance
order: 120009
since: 0.47.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# Library Drift Check

Flags registered library roots that have source on disk but nothing in the index.

Read this when a library index may have gone stale or was never built. The library-drift verb (or Library Drift Check in the IDE) flags every registered library root that has source on disk but nothing in the index, and exits 2 when it finds drift.

## How to run it

Full flag list: [library-drift in the CLI reference](../cli.md#library-drift).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--platform` | `<p>` |  |  |
| `--config` | `<path>` |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Index & Maintenance > Library Drift Check...**
   1. drag-lint > Index & Maintenance > Library Drift Check...
   2. The registered library roots that have source on disk but nothing in the index are reported

## Details

Flags registered library roots that have source on disk but nothing in the
index. Reach for it to catch a library index that has silently gone stale or
was never built.

### Running it from the CLI
```text
drag-lint library-drift [--platform <p>] [--config <path>] [--json]
```
Exits 2 if drift is found. `--platform` scopes the check to `win32` or
`win64`; `--config` points at an alternate manifest.

A root whose own folder name the Library section's walk prunes -- an `exclude`
glob such as the manifest's global `"Win64"`, which matches compiled-lib roots
like `...\Lib\RX13\Win64` -- is not drift: no rescan can index it. It is listed
apart (`EXCLUDED BY CONFIG` in text, `excludedRoots` in JSON) and does not
count toward exit 2. To index such a root, change the exclude, not the scan.

### What it needs
No index required -- this command has no `--db` flag; it checks the
registered library manifest and what is on disk against what is already
indexed, rather than querying a specific project's index.

### Example
Illustrative only:
```text
drag-lint library-drift --platform win64 --json
```
This would report, as JSON, any Win64 library roots that have source on disk
but nothing indexed, exiting 2 if any are found.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
