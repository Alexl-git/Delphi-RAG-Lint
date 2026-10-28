---
id: workspace-add
title: workspace add
summary: Registers a project file into a .drag-lint-workspace.json workspace config, so multi-project workspace commands know about it
product: DL
group: editor-integration
order: 110021
since: 0.6.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# workspace add

Registers a project file into a .drag-lint-workspace.json workspace config, so multi-project workspace commands know about it.

Read this when you add a new project to a multi-project workspace: it registers a project file in the .drag-lint-workspace.json config that workspace index and workspace status use.

## How to run it

Full flag list: [workspace in the CLI reference](../cli.md#workspace).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<.drag-lint-workspace.json>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Registers a project file into a `.drag-lint-workspace.json` workspace
config, so multi-project workspace commands know about it. Reach for it when
adding a new project to a workspace that `workspace index` / `workspace
status` will operate over.

### Running it from the CLI

```text
drag-lint workspace add <projfile> [--config <.drag-lint-workspace.json>]
```

### What it needs

No index required -- `workspace add` only edits the workspace config file;
it does not read or write an index database.

### Example

Illustrative:

```text
drag-lint workspace add MyProject.dproj
```

This would add `MyProject.dproj` to the workspace config in the current
directory.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
