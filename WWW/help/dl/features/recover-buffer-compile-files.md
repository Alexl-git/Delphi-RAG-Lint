---
id: recover-buffer-compile-files
title: Recover Buffer-Compile Files
summary: Restores any file left holding unsaved-buffer content after a Compile Buffer (unsaved) run was interrupted (for example by a crash)
product: DL
group: compiler
order: 90012
since: 0.47.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# Recover Buffer-Compile Files

Restores any file left holding unsaved-buffer content after a Compile Buffer (unsaved) run was interrupted (for example by a crash).

Read this if a Compile Buffer (unsaved) run was interrupted, for example by a crash. It restores any file left holding the unsaved-buffer content so no unit keeps overlaid text instead of its saved original; the IDE can run it for you.

## Where to click

* drag-lint About window, button **Recover Buffer-Compile Files**
   1. Nothing to click in the normal case; the IDE runs it for you
   2. To run it by hand: `drag-lint ghost-recover "<project>"`
   3. It prints "ghost-recover: nothing pending." when there is nothing to restore

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
