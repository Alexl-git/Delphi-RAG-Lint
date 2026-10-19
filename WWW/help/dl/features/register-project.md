---
id: register-project
title: register-project
summary: Add a new project to the manifest so index --all and the IDE can see it
product: DL
group: indexing
order: 10006
since: 1.20.4-alpha
status: shipped
updated: 1.20.4-alpha
---

# register-project

Add a new project to the manifest so index --all and the IDE can see it.

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

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
