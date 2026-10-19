---
id: import-build-log
title: Import Build Log
summary: Parses an external dcc or msbuild build log and folds its errors and warnings into drag-lint's stored findings
product: DL
group: compiler
order: 90009
since: 0.8.0-alpha
status: shipped
updated: 0.8.0-alpha
---

# Import Build Log

Parses an external dcc or msbuild build log and folds its errors and warnings into drag-lint's stored findings.

## How to run it

Full flag list: [import-log in the CLI reference](../cli.md#import-log).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |

## Where to click

* drag-lint About window, button **Import Build Log...**

**Needs:** index

## Details

Parses an external dcc or msbuild build log and folds its errors and
warnings into drag-lint's stored findings. Reach for it to bring
diagnostics from a build that ran outside drag-lint (for example a CI
build) into the index.

### Running it from the CLI
```text
drag-lint import-log <logfile> --db <file.sqlite>
```
`<logfile>` is the dcc/msbuild log to parse; `--db` is the index database
to write the findings into.

### Reaching it in the IDE
drag-lint > Import Build Log...

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint import-log C:\Projects\MyApp\build.log --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would parse `build.log` and add its errors and warnings to
`MyApp.sqlite`'s stored findings.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
