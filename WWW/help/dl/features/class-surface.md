---
id: class-surface
title: Class Surface
summary: "Shows the public surface of a class: its members and signatures, without the method bodies"
product: DL
group: search-navigation
order: 20002
since: 0.1.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Class Surface

Shows the public surface of a class: its members and signatures, without the method bodies.

Read this when you want to know what a class exposes without reading the whole unit. Class Surface shows its members and signatures, without the method bodies.

## How to run it

Full flag list: [surface in the CLI reference](../cli.md#surface).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--include-impl` |  |  |  |
| `--all-visibility` |  |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Inspect Symbol > Class Surface...**

## Pitfalls

* names, TYPES and trailing comments. outline --file lists them with line numbers.

## Details

Shows the public surface of a class: its members and signatures, without
the method bodies. Reach for it to see what a class exposes without
reading the whole unit.

### Reaching it in the IDE
drag-lint > Inspect Symbol > Class Surface...

No keyboard shortcut is documented for this menu item.

### Running it from the CLI
```text
drag-lint surface --qname <Foo.TBar> [--db <file.sqlite>] [--include-impl] [--all-visibility] [--format text|json]
```
`--qname` is the fully qualified class; `--include-impl` adds
implementation-only members; `--all-visibility` includes non-public
members; `--format` selects text or JSON.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint surface --qname CustomerOrder.TCustomerOrder --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would print the public surface of `TCustomerOrder`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
