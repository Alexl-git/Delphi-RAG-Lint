---
id: shutdown
title: shutdown
summary: Ask running lsp engines to close their indexes and stand down, so an index can be rebuilt without killing them
product: DL
group: maintenance
order: 120012
since: 0.6.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# shutdown

Ask running lsp engines to close their indexes and stand down, so an index can be rebuilt without killing them.

Read this when you need to rebuild an index that running engines hold open: shutdown asks the running lsp engines to close their stores and stand down, without killing them (only --force terminates an engine that does not answer).

## How to run it

```text
drag-lint shutdown [--db <file.sqlite>]... [--wait <sec>] [--dry-run] [--all] [--force] (ask running `lsp` engines to stand down: close every store, exit 0)
```

Full flag list: [shutdown in the CLI reference](../cli.md#shutdown).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--wait` | `<sec>` |  |  |
| `--dry-run` |  |  |  |
| `--all` |  |  |  |
| `--force` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
