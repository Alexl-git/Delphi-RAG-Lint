---
id: drag-lint-panel-dockable
title: drag-lint Panel (dockable)
summary: Opens the main drag-lint dockable tool window inside the IDE
product: DL
group: editor-integration
order: 110005
since: 0.0.0
status: shipped
updated: 1.32.0-alpha
---

# drag-lint Panel (dockable)

Opens the main drag-lint dockable tool window inside the IDE.

## Where to click

* RAD Studio main menu: **drag-lint > drag-lint Panel (dockable)**

## Details

Opens the main drag-lint dockable tool window inside the IDE. Reach for it
to keep drag-lint's panel docked alongside your editor instead of a
separate window.

### Reaching it in the IDE
drag-lint > drag-lint Panel (dockable)

Also reachable from View > Tool Windows > drag-lint -- the same dockable
panel under a second menu path; see [drag-lint](drag-lint.md) for that entry.

No keyboard shortcut is documented for this menu item.

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
