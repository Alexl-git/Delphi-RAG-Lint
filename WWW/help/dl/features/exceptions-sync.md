---
id: exceptions-sync
title: exceptions-sync
summary: Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites
product: DL
group: linting
order: 30005
since: 1.8.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# exceptions-sync

Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites.

Read this when a project raises bare Exception.Create with literal messages and you want one named exception class per distinct message. It runs as a dry run, and --apply writes the classes into a managed block in your exceptions unit; the raise sites are then rewritten by lint --fix.

## How to run it

```text
drag-lint exceptions-sync [--db <file.sqlite>] [--config <lint.json>] [--apply] [--json] (materialise the project's derived exception classes)
```

Full flag list: [exceptions-sync in the CLI reference](../cli.md#exceptions-sync).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--config` | `<lint.json>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
