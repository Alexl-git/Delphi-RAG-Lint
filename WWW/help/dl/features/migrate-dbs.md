---
id: migrate-dbs
title: migrate-dbs
summary: Moves project index databases into each project's own D-RAG folder, matching the current index layout
product: DL
group: indexing
order: 10004
since: 1.3.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# migrate-dbs

Moves project index databases into each project's own D-RAG folder, matching the current index layout.

Read this after an index layout change, or when index databases are stranded in an old shared folder. It moves each project index into that project own _D-RAG folder; without --apply it only reports what it would move.

## How to run it

Full flag list: [migrate-dbs in the CLI reference](../cli.md#migrate-dbs).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<drag-lint.json>` |  |  |
| `--apply` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Index & Maintenance > Migrate Index DBs to _D-RAG...**
   1. drag-lint > Index & Maintenance > Migrate Index DBs to _D-RAG...
   2. Yes applies the move (queued job, LSP stopped); No previews it

## Details

Moves project index databases into each project's own `_D-RAG` folder,
matching the current index layout: a project's DB lives at
`<project folder>\_D-RAG\<project file base name>.sqlite`. Only the
per-platform library indexes stay in a shared folder. Reach for it after an
index layout change, or to fix DBs stranded in an old shared location.

### Running it from the CLI

```text
drag-lint migrate-dbs [--config <drag-lint.json>] [--apply]
```

Without `--apply` this is a dry run -- it reports what it would move
without moving anything.

### What it needs

No index required -- `migrate-dbs` operates on the index FILES themselves
(moving them), not on their content, so there is nothing to query first.

### Example

Illustrative:

```text
drag-lint migrate-dbs --apply
```

This would move every project's index database into that project's own
`_D-RAG` folder.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
