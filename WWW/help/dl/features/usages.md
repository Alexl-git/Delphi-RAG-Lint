---
id: usages
title: usages
summary: Finds usage sites of a named symbol, with a choice of report width
product: DL
group: search-navigation
order: 20031
since: 0.33.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# usages

Finds usage sites of a named symbol, with a choice of report width.

Read this when you want every place a symbol is used: usages (also behind Find Usages in the IDE) lists the grouped usage sites of a named symbol, with a narrow, wide or very-wide report width.

## How to run it

Full flag list: [usages in the CLI reference](../cli.md#usages).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<X>` |  |  |
| `--width` |  |  |  |
| `--db` | `<path>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Find Usages...**
   1. Put the caret on the symbol in the editor
   2. Choose drag-lint > Find Usages...
   3. Read the grouped usage sites

## Details

Finds usage sites of a named symbol, with a choice of report width. Reach for
it when you want a usages listing outside the IDE, or want to understand what
backs the "Usages" search kind in the Symbol Search dialog.

### Running it from the CLI
```text
drag-lint usages --name <X> [--width narrow|wide|very-wide] [--db <path>] [--depth N] [--format json]
```
`--name <X>` is the symbol to search for. `--width` controls report width
(`narrow`, `wide`, or `very-wide`). `--depth N` is in the usage line with no
further description -- not documented. `--format json` is the only format the
usage line lists.

### What it needs
Optional, per the feature map's Index column.

### Example
Illustrative only:
```text
drag-lint usages --name TCustomerOrder --width wide --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```
This would list usage sites of `TCustomerOrder` as JSON, at "wide" report
width.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
