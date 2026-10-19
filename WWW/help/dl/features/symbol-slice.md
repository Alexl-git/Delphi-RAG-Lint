---
id: symbol-slice
title: Symbol Slice
summary: "Shows the slice of code relevant to one symbol: its declaration, body, and immediate context"
product: DL
group: search-navigation
order: 20028
since: 0.17.0-alpha
status: shipped
updated: 0.17.0-alpha
---

# Symbol Slice

Shows the slice of code relevant to one symbol: its declaration, body, and immediate context.

## How to run it

Full flag list: [slice in the CLI reference](../cli.md#slice).

## Where to click

* RAD Studio main menu: **drag-lint > Inspect Symbol > Symbol Slice...**

## Details

Shows the slice of code relevant to one symbol: its declaration, body, and
immediate context. Reach for it to see just what matters for a symbol
instead of the whole file.

### Reaching it in the IDE
drag-lint > Inspect Symbol > Symbol Slice...

No keyboard shortcut is documented for this menu item.

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
