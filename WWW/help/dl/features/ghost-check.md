---
id: ghost-check
title: ghost-check
summary: Compiles a project with one or more units' content temporarily replaced by their unsaved editor buffers, then restores the original files unchanged
product: DL
group: compiler
order: 90007
since: 1.8.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# ghost-check

Compiles a project with one or more units' content temporarily replaced by their unsaved editor buffers, then restores the original files unchanged.

Read this when you want compiler diagnostics for edits you have not saved. ghost-check compiles the project with chosen units temporarily replaced by their buffers, then restores the original files unchanged.

## How to run it

Full flag list: [ghost-check in the CLI reference](../cli.md#ghost-check).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--unit` | `<real.pas>` |  |  |
| `--buffer` | `<buf>` |  |  |
| `--overlays` | `<manifest>` |  |  |
| `--platform` |  |  |  |
| `--in-place` |  |  |  |
| `--format` |  |  |  |

## Pitfalls

* compiles each UNSAVED buffer from a shadow dir; your real files are NEVER written. --in-place restores the old behaviour (overwrites the real files for the compile, then restores them) -- it can lose live edits if the IDE reloads inside that window. compile the UNSAVED editor buffer by overlaying it on the real unit. Backs the IDE's "Compile Buffer (unsaved)". Restores the original on exit.

## Details

Compiles a project with one or more units' content temporarily replaced by
their unsaved editor buffers, then restores the original files unchanged.
Reach for it to get compiler diagnostics against unsaved edits without
saving them to disk.

### Running it from the CLI
```text
drag-lint ghost-check <dproj> ( --unit <real.pas> --buffer <buf> | --overlays <manifest> ) [--platform win32|win64] [--in-place] [--format json|text]
```
`<dproj>` is the project to compile. Give either a single
`--unit <real.pas> --buffer <buf>` pair, or an `--overlays <manifest>` file
listing multiple real-path/buffer-path pairs. `--platform` selects `win32`
or `win64`. `--format` selects `json` or `text`.

### Reaching it in the IDE
No menu item calls this directly. The plugin's editor code (Editor.pas:2489)
shells out to this verb to compile the active project against unsaved buffer
content, backing "Compile Buffer (unsaved)" and feeding "Compile & Diagnose".

### What it needs
Not needed, per the feature map's Index column.

### Example
Illustrative only:
```text
drag-lint ghost-check C:\Projects\MyApp\MyApp.dproj --unit C:\Projects\MyApp\frmOrders.pas --buffer C:\Projects\MyApp\_D-RAG\frmOrders.buf --platform win32 --format json
```
This would compile `MyApp.dproj` with `frmOrders.pas`'s content replaced by
the buffer file, report diagnostics as JSON, then restore `frmOrders.pas`
unchanged.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
