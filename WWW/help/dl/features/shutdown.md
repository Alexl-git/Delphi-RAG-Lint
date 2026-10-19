---
id: shutdown
title: shutdown
summary: Ask running lsp engines to close their indexes and stand down, so an index can be rebuilt without killing them
product: DL
group: maintenance
order: 120012
since: 0.6.0-alpha
status: shipped
updated: 0.6.0-alpha
---

# shutdown

Ask running lsp engines to close their indexes and stand down, so an index can be rebuilt without killing them.

## How to run it

```text
drag-lint shutdown [--db <file.sqlite>]... [--wait <sec>] [--dry-run] [--all] [--force] (ask running `lsp` engines to stand down: close every store, exit 0)
```

Full flag list: [shutdown in the CLI reference](../cli.md#shutdown).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
