---
id: shutdown
title: shutdown
summary: Ask running engines (lsp, cycles --fix, index, lint-all) to stand down cleanly, so an index can be rebuilt or an engine replaced
product: DL
group: maintenance
order: 120012
since: 0.6.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# shutdown

Ask running engines (lsp, cycles --fix, index, lint-all) to stand down cleanly, so an index can be rebuilt or an engine replaced.

Read this when you need to rebuild an index that running engines hold open, or replace a running engine: shutdown asks the running engines (lsp, cycles --fix, and the long index and lint-all runs) to close their stores and stand down, without killing them (only --force terminates an engine that does not answer). An index run stops between files with its database consistent and the same command resumes; the installer and build\stage-engine.ps1 use this channel first.

## How to run it

```text
drag-lint shutdown [--db <file.sqlite>]... [--wait <sec>] [--dry-run] [--all] [--force] (ask running engines to stand down: close every store, exit 0; `index` and `lint-all` runs exit 4)
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
