---
id: copy-selected-diagnostics
title: Copy Selected Diagnostics
summary: Copies only the Diagnostics rows selected in the Structure form (Ctrl/Shift-click, Ctrl+C) to the clipboard
product: DL
group: linting
order: 30005
since: 1.28.3-alpha
status: shipped
updated: 1.38.0-alpha
---

# Copy Selected Diagnostics

Copies only the Diagnostics rows selected in the Structure form (Ctrl/Shift-click, Ctrl+C) to the clipboard.

Read this when you want to paste one or two findings, not the whole list. Select Diagnostics rows in the Structure form (Ctrl or Shift click), then choose Copy or press Ctrl+C; selecting the Diagnostics root copies everything.

## Where to click

* Right-click in the Structure form: **Copy**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Click a Diagnostics row; Ctrl+click or Shift+click to add more
   3. Right-click and choose Copy, or press Ctrl+C; selecting only the Diagnostics root copies every finding

## Details

Copies just the Diagnostics rows you selected in the Structure form to the
clipboard -- one finding, or several. Reach for it when you want to paste one
or two findings (into a chat, an issue, a review) rather than the whole list.

### What lands on the clipboard

One line per selected finding, in panel order (by line, then column), with
no file header:

```text
[W] (10:5) Unit 'Winapi.ShellAPI' is listed in the uses clause but ...  [unused-unit-in-uses]
```

### Running it from the CLI

There is no CLI equivalent of a selection; `drag-lint lint <path>` prints
every finding of a file (see [Copy All Diagnostics](copy-all-diagnostics.md)).

### What it needs

Nothing beyond the findings already shown in the panel.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
