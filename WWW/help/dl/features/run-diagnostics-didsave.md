---
id: run-diagnostics-didsave
title: Run Diagnostics (didSave)
summary: Runs drag-lint's diagnostics pass on a file automatically when it is saved, mirroring the LSP textDocument/didSave notification
product: DL
group: linting
order: 30022
since: 0.22.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Run Diagnostics (didSave)

Runs drag-lint's diagnostics pass on a file automatically when it is saved, mirroring the LSP textDocument/didSave notification.

Read this to know why drag-lint findings refresh on their own: with automatic diagnostics on, the pass runs on a file each time you save it in the IDE. You can also trigger it by hand for the active editor with Ctrl+Alt+D or the About dialog button.

## Where to click

* drag-lint About window, button **Run Diagnostics (didSave)**
   1. It fires on every save when Run diagnostics automatically on save is enabled in the options
   2. To run it by hand on the active editor: press Ctrl+Alt+D or click Run Diagnostics (didSave) in the About dialog
   3. It needs an open editor with a saved file
   4. There is no CLI equivalent; it runs in-process in the plugin

## Details

Runs drag-lint's diagnostics pass on a file automatically when it is
saved, mirroring the LSP `textDocument/didSave` notification. Reach for
it indirectly -- it is not something you invoke by hand; it fires on save.

### Running it from the CLI
No CLI equivalent. The feature map lists this action's CliVerb as
"(none - in-process)" and its Mechanism as "in-process" -- it runs inside
the plugin without shelling out to the drag-lint executable.

### What it needs
Not documented as needing an index -- the feature map marks this row's
Index column "n/a". Since it fires on save, it needs an open editor with
a saved file.

### Example
Illustrative only: saving a unit in the editor triggers this action, which
runs diagnostics on the just-saved file and updates its findings.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
