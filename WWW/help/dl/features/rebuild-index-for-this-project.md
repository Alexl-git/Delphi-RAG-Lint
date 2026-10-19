---
id: rebuild-index-for-this-project
title: Rebuild Index for This Project
summary: Walks a project's .dproj compile closure and (re)builds its index
product: DL
group: indexing
order: 10005
since: 0.1.0-alpha
status: shipped
updated: 0.1.0-alpha
---

# Rebuild Index for This Project

Walks a project's .dproj compile closure and (re)builds its index.

## How to run it

Full flag list: [index in the CLI reference](../cli.md#index).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--watch` |  |  |  |
| `--interval` | `N` |  |  |
| `--library-db` | `<lib.sqlite>` | consult another index for calls THIS one cannot resolve. |  |
| `--max-file-kb` | `N` |  |  |
| `--no-use-ignore` |  |  |  |
| `--no-sql-ms` |  |  |  |
| `--deep` |  |  |  |
| `--shallow` |  |  |  |
| `--exclude-under` |  |  |  |
| `--include-only` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Index & Maintenance > Rebuild Index for This Project**

## Details

Walks a project's `.dproj` compile closure and (re)builds its index. Reach
for it after adding or moving units, or when hover, Find Usages, or lint
results feel stale.

### Running it from the CLI
```text
drag-lint index --project <file.dproj> [--db <file.sqlite>] [--dry-run] [--watch [--interval N]]
```
`--dry-run` previews without writing; `--watch [--interval N]` keeps
re-indexing on an interval. Mode is chosen per run: `--recompile` (default)
updates the index in place; `--rebuild` first empties it of source, then
walks (implies `--force-reparse`). `--force-reparse` (alias `--no-skip`)
re-parses every walked file even when unchanged. `--prune` forces the
delete-sweep for a single-file walk; `--no-prune` computes and reports what
would be removed without deleting anything.

### Reaching it in the IDE
drag-lint > Index & Maintenance > Rebuild Index for This Project

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint index --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would re-index `MyApp`'s compile closure in place (default recompile
mode).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
