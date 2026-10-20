---
id: workspace-index
title: workspace index
summary: Indexes every project registered in a .drag-lint-workspace.json workspace config in one pass
product: DL
group: editor-integration
order: 110015
since: 0.6.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# workspace index

Indexes every project registered in a .drag-lint-workspace.json workspace config in one pass.

## How to run it

Full flag list: [workspace in the CLI reference](../cli.md#workspace).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<.drag-lint-workspace.json>` |  |  |

## Details

Indexes every project registered in a `.drag-lint-workspace.json` workspace
config in one pass. Reach for it to (re)build all of a workspace's project
indexes together, rather than one project at a time.

### Running it from the CLI

```text
drag-lint workspace index [--config <.drag-lint-workspace.json>]
```

### Reaching it in the IDE

CLI+internal: the plugin calls this internally from
`DragLint.Plugin.ProjectNotifier.pas:103`. There is no menu item for it --
it is invoked in-process by the plugin, not exposed as a user-facing
command.

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
