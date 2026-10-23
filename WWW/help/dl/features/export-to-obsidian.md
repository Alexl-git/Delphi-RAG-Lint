---
id: export-to-obsidian
title: Export to Obsidian
summary: Uses export obsidian to write the indexed project out as a set of Obsidian vault markdown pages
product: DL
group: graphs-reports
order: 70010
since: 0.6.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Export to Obsidian

Uses export obsidian to write the indexed project out as a set of Obsidian vault markdown pages.

Read this when you want a browsable wiki of your project symbols in an Obsidian vault. drag-lint export obsidian writes markdown pages into the folder you name with --output-dir; also on the IDE Generate & Export menu.

## How to run it

Full flag list: [export in the CLI reference](../cli.md#export).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--output-dir` | `<dir>` |  |  |
| `--open` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Export to Obsidian...**
   1. Make sure the project has an index
   2. drag-lint > Generate & Export > Export to Obsidian...
   3. Follow the prompts; the notes are written as linked markdown pages

**Needs:** index

## Details

Uses `export obsidian` to write the indexed project out as a set of Obsidian
vault markdown pages. Reach for it to build a browsable wiki of a project's
symbols.

### Running it from the CLI
```text
drag-lint export obsidian --db <file.sqlite> --output-dir <dir> [--open]
```
`--output-dir` is required and names the folder to write pages into; `--open`
opens it after export.

### Reaching it in the IDE
drag-lint > Generate & Export > Export to Obsidian...

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint export obsidian --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --output-dir C:\Projects\MyApp-wiki --open
```
This would write `MyApp`'s indexed symbols as markdown pages into
`C:\Projects\MyApp-wiki` and open the folder afterward.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
