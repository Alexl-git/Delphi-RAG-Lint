---
id: doc-forget
title: doc-forget
summary: Reap or rename the project tags on inbound documentation facts; a dry run unless told to apply
product: DL
group: documentation
order: 40003
since: 1.17.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# doc-forget

Reap or rename the project tags on inbound documentation facts; a dry run unless told to apply.

Read this when documentation facts carry the wrong project tag, or tags need cleaning up. doc-forget removes or renames project tags on inbound doc facts for a file or folder, and is a dry run unless you pass --apply.

## How to run it

```text
drag-lint doc-forget --scope <file.pas|dir> (--project <Tag> [--rename <Tag>=<New>] | --untagged | --list-tags) [--apply|--no-backup] - reap project tags on inbound doc facts
```

Full flag list: [doc-forget in the CLI reference](../cli.md#doc-forget).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--scope` | `<file.pas\|dir>` |  |  |
| `--project` | `<Tag>` |  |  |
| `--rename` | `<Tag>` |  |  |
| `--untagged` |  |  |  |
| `--list-tags` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
