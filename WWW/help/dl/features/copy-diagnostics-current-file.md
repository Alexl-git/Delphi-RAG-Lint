---
id: copy-diagnostics-current-file
title: Copy Diagnostics (Current File)
summary: Puts the current file's lint findings onto the clipboard
product: DL
group: linting
order: 30004
since: 0.1.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Copy Diagnostics (Current File)

Puts the current file's lint findings onto the clipboard.

Read this when you want to paste the current file findings elsewhere instead of reading them in the IDE. It puts the file lint findings onto the clipboard.

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

* drag-lint About window, button **Copy Diagnostics (Current File)**
   1. Open the file in the editor
   2. Open the About window (drag-lint > About) and click the Copy Diagnostics (Current File) button
   3. The file's lint findings are on the clipboard

## Details

Puts the current file's lint findings onto the clipboard. Reach for it to
paste a file's findings elsewhere (a chat, an issue, a note) instead of
reading them in the IDE.

### Running it from the CLI
```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]
```
This runs the lint pass on a file and prints its findings. The
clipboard-copy behavior is an IDE-side convenience on top of this verb;
the CLI itself only prints.

### What it needs
No index needed. `lint <path>` lints the given file directly, without
going through a project index database; the feature map marks this row's
Index column "no".

### Example
Illustrative only:
```text
drag-lint lint C:\Projects\MyApp\Unit1.pas --json
```
This would print `Unit1.pas`'s findings as JSON; the IDE action copies
the equivalent findings text to the clipboard instead.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
