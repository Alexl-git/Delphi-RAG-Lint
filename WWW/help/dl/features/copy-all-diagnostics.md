---
id: copy-all-diagnostics
title: Copy All Diagnostics
summary: Puts every lint finding for the current unit onto the clipboard, starting from the Structure form
product: DL
group: linting
order: 30003
since: 0.1.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Copy All Diagnostics

Puts every lint finding for the current unit onto the clipboard, starting from the Structure form.

Read this when you want to paste a unit full list of findings into a chat, issue or note. Right-click in the Structure form and choose Copy All Diagnostics to put every lint finding for the current unit on the clipboard.

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
| `--build-config` | `<name>` |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

## Where to click

* Right-click in the Structure form: **Copy All Diagnostics**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click in the Structure form
   3. Choose Copy All Diagnostics; every finding of the current unit is on the clipboard

## Details

Puts every lint finding for the current unit onto the clipboard, starting
from the Structure form. Reach for it when you want to paste a unit's full
findings list elsewhere (a chat, an issue, a note) instead of reading them
in the IDE.

### What lands on the clipboard

The unit's path on the first line, then one line per finding in the SAME
order as the Diagnostics rows -- by line, then column:

```text
C:\Projects\MyApp\Unit1.pas
[W] (10:5) Unit 'Winapi.ShellAPI' is listed in the uses clause but ...  [unused-unit-in-uses]
[I] (227:7) Public field on a class breaks encapsulation -- ...  [public-field]
```

(Before 2026-10-13 the copy followed the engine's rule-grouped order, so the
paste did not match what the panel showed.) To copy only some rows, see
[Copy Selected Diagnostics](copy-selected-diagnostics.md).

### Running it from the CLI

The feature map lists the underlying verb as `lint`. From the usage banner:

```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]
```

This runs the lint pass on a file and prints its findings. The
"copy to clipboard" behavior is an IDE-side convenience on top of this
verb; the CLI itself only prints, it does not clipboard-copy.

### What it needs

No index required -- `lint <path>` lints the given file directly, without
going through a project index database.

### Example

Illustrative:

```text
drag-lint lint C:\Projects\MyApp\Unit1.pas --json
```

This would print `Unit1.pas`'s findings as JSON; the IDE action copies the
equivalent findings text to the clipboard instead.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
