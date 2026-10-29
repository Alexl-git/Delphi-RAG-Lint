---
id: workspace-index
title: workspace index
summary: Indexes every project registered in a .drag-lint-workspace.json workspace config in one pass
product: DL
group: editor-integration
order: 110024
since: 0.6.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# workspace index

Indexes every project registered in a .drag-lint-workspace.json workspace config in one pass.

Read this when you want to (re)build the indexes of every project in a workspace in one pass instead of one project at a time.

## How to run it

Full flag list: [workspace in the CLI reference](../cli.md#workspace).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<.drag-lint-workspace.json>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Indexes every project registered in a `.drag-lint-workspace.json` workspace
config in one pass. Reach for it to (re)build all of a workspace's project
indexes together, rather than one project at a time.

### Running it from the CLI

```text
drag-lint workspace index [--config <.drag-lint-workspace.json>]
```

### What it needs

No index required to invoke the command -- `workspace index` is the command
that BUILDS the workspace's project indexes; it reads the workspace config,
not an existing index database.

### Example

Illustrative:

```text
drag-lint workspace index --config .drag-lint-workspace.json
```

This would index every project registered in that workspace config.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
