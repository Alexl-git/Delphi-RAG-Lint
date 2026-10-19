---
id: impact-blast-radius-symbol
title: Impact / Blast Radius (symbol)
summary: Reports what would be affected if a chosen symbol changes -- the set of code to retest
product: DL
group: graphs-reports
order: 70012
since: 0.17.0-alpha
status: shipped
updated: 0.17.0-alpha
---

# Impact / Blast Radius (symbol)

Reports what would be affected if a chosen symbol changes -- the set of code to retest.

## How to run it

Full flag list: [impact in the CLI reference](../cli.md#impact).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--depth` | `N` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Impact / Blast Radius (symbol)...**

## Details

Reports what would be affected if a chosen symbol changes -- the set of code
to retest. Reach for it before changing a widely-used method or type.

### Running it from the CLI
```text
drag-lint impact --qname <Foo.Bar> [--db <file.sqlite>] [--depth N] [--format text|json]
```
`--qname` is the fully qualified symbol; `--depth` bounds how far impact is
traced; `--format` selects `text` or `json`.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Impact / Blast Radius (symbol)...

### What it needs
Optional. An index is not marked required, but the impact trace is read from
whatever has been indexed, so a stale or missing index gives an incomplete answer.

### Example
Illustrative only:
```text
drag-lint impact --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --depth 3
```
This would report what is affected, up to 3 levels out, if the `Total`
member of `TCustomerOrder` changes.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
