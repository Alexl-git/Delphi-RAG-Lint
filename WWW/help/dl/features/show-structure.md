---
id: show-structure
title: Show Structure
summary: Shows a structural outline of the current unit
product: DL
group: search-navigation
order: 20026
since: 0.30.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# Show Structure

Shows a structural outline of the current unit.

## Where to click

* RAD Studio main menu: **drag-lint > Show Structure**

## Details

Shows a structural outline of the current unit. Reach for it to see a
unit's types and members as a navigable tree instead of scrolling the
source.

### Reaching it in the IDE
drag-lint > Show Structure

No keyboard shortcut is documented for this menu item.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. This is
the Structure form that several other feature-map rows (Go to Declaration,
Find Usages (context), Show in Call Graph, and others) reach by
right-clicking a tree node.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs the unit open in the editor.

### Example
Illustrative: with a unit open, choose "Show Structure" to open the
Structure form showing that unit's types and members as a tree.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
