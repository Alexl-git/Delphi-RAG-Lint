---
id: drag-lint-panel-dockable
title: drag-lint Panel (dockable)
summary: Opens the main drag-lint dockable tool window inside the IDE
product: DL
group: editor-integration
order: 110005
since: 0.42.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# drag-lint Panel (dockable)

Opens the main drag-lint dockable tool window inside the IDE.

Read this when you want the main drag-lint tool window docked beside your editor instead of as a separate window. Choose drag-lint > drag-lint Panel (dockable); it only needs the IDE plugin loaded.

## Where to click

* RAD Studio main menu: **drag-lint > drag-lint Panel (dockable)**
   1. Choose drag-lint > drag-lint Panel (dockable)
   2. The main drag-lint tool window opens as a dockable window; drag it where you want it to stay docked

## Details

Opens the main drag-lint dockable tool window inside the IDE. Reach for it
to keep drag-lint's panel docked alongside your editor instead of a
separate window.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs the drag-lint plugin loaded in the IDE.

### Example
Illustrative: choose "drag-lint > drag-lint Panel (dockable)" to dock the
main drag-lint panel beside the editor.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
