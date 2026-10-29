---
id: register-project
title: register-project
summary: Add a new project to the manifest so index --all and the IDE can see it
product: DL
group: indexing
order: 10008
since: 1.20.4-alpha
status: shipped
updated: 1.38.0-alpha
---

# register-project

Add a new project to the manifest so index --all and the IDE can see it.

Read this when drag-lint does not know a new project. It adds the .dproj to the manifest so index --all and the IDE can see it; without --apply it is a dry run.

## How to run it

```text
drag-lint register-project <file.dproj> [--name <Section>] [--apply] [--json] (add a NEW project to the manifest so index --all and the IDE can see it; dry-run without --apply)
```

Full flag list: [register-project in the CLI reference](../cli.md#register-project).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<Section>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
