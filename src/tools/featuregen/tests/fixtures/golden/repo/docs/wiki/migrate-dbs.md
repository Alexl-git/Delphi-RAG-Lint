# migrate-dbs

Moves project index databases into each project's own `_D-RAG` folder,
matching the current index layout: a project's DB lives at
`<project folder>\_D-RAG\<project file base name>.sqlite`. Only the
per-platform library indexes stay in a shared folder. Reach for it after an
index layout change, or to fix DBs stranded in an old shared location.

## Running it from the CLI

```
drag-lint migrate-dbs [--config <drag-lint.json>] [--apply]
```

Without `--apply` this is a dry run -- it reports what it would move
without moving anything.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

No index required -- `migrate-dbs` operates on the index FILES themselves
(moving them), not on their content, so there is nothing to query first.

## Example

Illustrative:

```
drag-lint migrate-dbs --apply
```

This would move every project's index database into that project's own
`_D-RAG` folder.
