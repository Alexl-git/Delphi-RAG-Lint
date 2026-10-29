---
id: symbol-slice
title: Symbol Slice
summary: "Shows the slice of code relevant to one symbol: its declaration, body, and immediate context"
product: DL
group: search-navigation
order: 20031
since: 0.17.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Symbol Slice

Shows the slice of code relevant to one symbol: its declaration, body, and immediate context.

Read this when you want only the code that matters for one symbol instead of the whole file: it shows the symbol declaration, body and immediate context.

## How to run it

Full flag list: [slice in the CLI reference](../cli.md#slice).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Inspect Symbol > Symbol Slice...**
   1. Put the caret on the symbol in the editor
   2. Choose drag-lint > Inspect Symbol > Symbol Slice...
   3. Read its declaration, body and immediate context
   4. From a shell: `drag-lint slice --qname <Foo.TBar> [--db <file.sqlite>] [--format text|json]`

## Details

Shows the slice of code relevant to one symbol: its declaration, body, and
immediate context. Reach for it to see just what matters for a symbol
instead of the whole file.

### Running it from the CLI
```text
drag-lint slice --qname <Foo.TBar> [--db <file.sqlite>] [--format text|json]
```
`--qname` is the fully qualified symbol; `--format` selects text or JSON.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint slice --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would print the declaration, body, and immediate context of the
`Total` member.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
