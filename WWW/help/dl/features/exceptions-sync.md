---
id: exceptions-sync
title: exceptions-sync
summary: Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites
product: DL
group: linting
order: 30007
since: 1.8.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# exceptions-sync

Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites.

Read this when a project raises bare Exception.Create with literal messages and you want one named exception class per distinct message. It is opt-in: add an "exceptions" block to drag-lint-lint.json (an empty one is enough; without it the verb says the feature is off and exits 0). It runs as a dry run, and --apply writes the classes into a managed block in your exceptions unit; the raise sites are then rewritten by `drag-lint lint <file> --fix --fix-rule raise-bare-exception [--apply]`.

## How to run it

```text
drag-lint exceptions-sync [--profile <name>] [--db <file.sqlite>] [--config <lint.json>] [--apply] [--json] (materialise the project's derived exception classes)
```

Full flag list: [exceptions-sync in the CLI reference](../cli.md#exceptions-sync).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--config` | `<lint.json>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
