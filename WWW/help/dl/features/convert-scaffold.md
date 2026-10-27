---
id: convert-scaffold
title: convert-scaffold
summary: Auto-generates a valid conversion-rules file from the real property trees of a from-type and a to-type
product: DL
group: component-conversion
order: 60003
since: 1.1.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# convert-scaffold

Auto-generates a valid conversion-rules file from the real property trees of a from-type and a to-type.

Generate a starting conversion-rules book for a pair of component classes, from their real property trees, instead of typing every rule.

## How to run it

Full flag list: [convert-scaffold in the CLI reference](../cli.md#convert-scaffold).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--from` | `<FromType>` |  |  |
| `--to` | `<ToType>` |  |  |
| `--output` | `<file>` |  |  |
| `--surface` |  |  |  |
| `--depth` | `N` |  |  |
| `--rules` | `<file>` |  |  |
| `--progress-interval` | `S` |  |  |
| `--db` | `PATH` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

**Needs:** index

## Details

Auto-generates a valid conversion-rules file from the real property trees of a
from-type and a to-type: a concrete `#link` where exactly one source property
matches by leaf-name and type, a `???` marker for ambiguous matches, and a
`DROPPED` note for orphaned source properties. Reach for it to get a starting
rules file instead of writing one by hand.

### Running it from the CLI
```text
drag-lint convert-scaffold --from <FromType> --to <ToType> [--output <file>] [--surface dfm|pas] --db PATH [--db ...]
```
`--from`/`--to` name the source and target types. `--output <file>` is where the
generated rules file is written. `--surface` picks the TO-side target bar:
default `dfm` (published properties only) or `pas` (published + public,
including public fields). A target with `is_writable=false` is never
auto-linked on either surface. `--db PATH` is required and may be repeated.

### What it needs
An index IS required -- `convert-scaffold` reads the project's index
database. The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`; run `drag-lint resolve-dbs --project <X.dproj>` if you are
unsure which one.

### Example
Illustrative only:
```text
drag-lint convert-scaffold --from TOvcTable --to TcxGrid --output C:\Projects\MyApp\convert-rules\OvcTable-to-cxGrid.rules --surface dfm --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would write a starting conversion-rules file linking `TOvcTable`
properties to `TcxGrid` properties on the DFM surface, flagging ambiguous or
orphaned properties for review.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
