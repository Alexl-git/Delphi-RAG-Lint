---
id: lint-buffer-unsaved
title: Lint Buffer (Unsaved)
summary: Lints the current editor buffer's in-memory content, including unsaved edits, without writing it to disk first
product: DL
group: linting
order: 30015
since: 0.1.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Lint Buffer (Unsaved)

Lints the current editor buffer's in-memory content, including unsaved edits, without writing it to disk first.

Read this when you want lint findings for edits you have not saved yet. The IDE lints the in-memory editor buffer directly, without writing it to disk first; the command line lints saved files.

## How to run it

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--db` | `<index.sqlite>` |  |  |
| `--project-rules` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

## Where to click

* drag-lint About window, button **Lint Buffer (Unsaved)**
   1. Edit a unit without saving it
   2. Open the About and Status window (drag-lint > About)
   3. Click Lint Buffer (Unsaved); findings for the in-memory content are shown

## Details

Lints the current editor buffer's in-memory content, including unsaved
edits, without writing it to disk first. Reach for it to see lint findings
for changes you have not saved yet.

### Running it from the CLI
The feature map lists this action's CliVerb as `lint`, but its Mechanism
is "in-process" -- the IDE lints the in-memory buffer directly rather than
shelling out to the CLI. The nearest CLI equivalent operates on a saved
file on disk:
```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]
```

### What it needs
No index needed. This action lints the buffer's content directly; the
feature map marks this row's Index column "no".

### Example
Illustrative only, showing the CLI verb this action's findings correspond
to once a file is saved:
```text
drag-lint lint C:\Projects\MyApp\Unit1.pas --json
```
The IDE action produces the equivalent findings for the unsaved buffer,
in-process, without this shell-out.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
