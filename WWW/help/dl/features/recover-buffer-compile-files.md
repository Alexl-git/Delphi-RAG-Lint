---
id: recover-buffer-compile-files
title: Recover Buffer-Compile Files
summary: Restores any file left holding unsaved-buffer content after a Compile Buffer (unsaved) run was interrupted (for example by a crash)
product: DL
group: compiler
order: 90012
since: 0.0.0
status: shipped
updated: 0.0.0
---

# Recover Buffer-Compile Files

Restores any file left holding unsaved-buffer content after a Compile Buffer (unsaved) run was interrupted (for example by a crash).

## Where to click

* drag-lint About window, button **Recover Buffer-Compile Files**

## Details

Restores any file left holding unsaved-buffer content after a
Compile Buffer (unsaved) run was interrupted (for example by a crash).
Reach for it, or let the IDE run it automatically, so no unit is left
holding overlaid content instead of its saved original.

### Running it from the CLI
The feature map lists this action's CliVerb as "(none - in-process)", but
this IDE action actually runs the `ghost-recover` verb. It prints no
usage banner: running it bare exits 0 and prints
`ghost-recover: nothing pending.` when there is nothing to recover. The
plugin invokes it as:
```text
drag-lint ghost-recover "<project>"
```

### Reaching it in the IDE
drag-lint > Recover Buffer-Compile Files

### What it needs
The feature map marks this row's Index column "n/a". It needs the project
path so it can look for pending recovery state for that project.

### Example
Illustrative only:
```text
drag-lint ghost-recover "C:\Projects\MyApp\MyApp.dproj"
```
This would check for any file left overlaid by an interrupted
Compile Buffer (unsaved) run and restore it to its saved original.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
