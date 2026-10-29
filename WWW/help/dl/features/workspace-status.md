---
id: workspace-status
title: workspace status
summary: Reports the status of every project registered in a .drag-lint-workspace.json workspace config
product: DL
group: editor-integration
order: 110024
since: 0.6.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# workspace status

Reports the status of every project registered in a .drag-lint-workspace.json workspace config.

Read this when you want to see at a glance how many files of each workspace project are in the shared index; a project with 0 files is not indexed yet.

## How to run it

Full flag list: [workspace in the CLI reference](../cli.md#workspace).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<.drag-lint-workspace.json>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Reports the status of every project registered in a
`.drag-lint-workspace.json` workspace config. Reach for it to see, at a
glance, which workspace projects are indexed, stale, or missing.

### Running it from the CLI

```text
drag-lint workspace status [--config <.drag-lint-workspace.json>]
```

### What it needs

No index required to invoke the command itself -- `workspace status` reads
the workspace config and reports on each registered project's index state;
it does not take a `--db` flag.

### Example

Illustrative:

```text
drag-lint workspace status
```

This would print the index status of every project registered in the
workspace config found in the current directory.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
