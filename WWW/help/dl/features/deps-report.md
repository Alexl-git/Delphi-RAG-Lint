---
id: deps-report
title: deps-report
summary: "Produces a third-party dependency rollup from an index: which external units/libraries an indexed codebase depends on"
product: DL
group: graphs-reports
order: 70007
since: 0.95.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# deps-report

Produces a third-party dependency rollup from an index: which external units/libraries an indexed codebase depends on.

Read this when you are auditing which external units or libraries a codebase depends on. deps-report rolls up the third-party dependencies from one or more indexes, as text, json or csv.

## How to run it

Full flag list: [deps-report in the CLI reference](../cli.md#deps-report).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--depth` | `N` |  |  |
| `--edges` |  |  |  |
| `--all-sources` |  |  |  |
| `--name` | `<pat>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Dependency Report (third-party rollup)...**

**Needs:** index

## Details

Produces a third-party dependency rollup from an index: which external
units/libraries an indexed codebase depends on. Reach for it when auditing
external dependencies across a project.

### Running it from the CLI

```text
drag-lint deps-report --db <file.sqlite> [--db ...] [--depth N] [--edges] [--all-sources] [--name <pat>] [--format text|json|csv] [--output <file>]
```

`--db` may be repeated to roll up dependencies across more than one index.

### Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative only:

```text
drag-lint deps-report --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format csv --output deps.csv
```

This would write `MyApp`'s third-party dependency rollup to `deps.csv`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
