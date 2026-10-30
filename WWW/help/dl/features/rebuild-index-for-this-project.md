---
id: rebuild-index-for-this-project
title: Rebuild Index for This Project
summary: Walks a project's .dproj compile closure and (re)builds its index
product: DL
group: indexing
order: 10007
since: 0.2.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Rebuild Index for This Project

Walks a project's .dproj compile closure and (re)builds its index.

Read this after adding or moving units, or when hover, Find Usages or lint results feel stale. It walks the project .dproj compile closure and rebuilds the index for that project.

## How to run it

Full flag list: [index in the CLI reference](../cli.md#index).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<file.dproj>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--recompile` |  |  |  |
| `--rebuild` |  |  |  |
| `--dry-run` |  |  |  |
| `--wait-library` | `<min>` |  |  |
| `--rule-cache-warm` | `background\|wait\|off` |  |  |
| `--require-library` |  |  |  |
| `--watch` |  |  |  |
| `--interval` | `N` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Index & Maintenance > Rebuild Index for This Project**
   1. Open the project in RAD Studio
   2. Choose drag-lint > Index & Maintenance > Rebuild Index for This Project
   3. Wait for the indexing run to finish; progress shows in the IDE
   4. From a shell instead: `drag-lint index --project <file.dproj> [--db <file.sqlite>] [--recompile|--rebuild]`

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
