---
id: drag-lint-graph-dockable
title: drag-lint Graph (dockable)
summary: Opens the drag-lint graph viewer as a dockable window inside the IDE, so it can sit beside Structure
product: DL
group: editor-integration
order: 110003
since: 0.43.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# drag-lint Graph (dockable)

Opens the drag-lint graph viewer as a dockable window inside the IDE, so it can sit beside Structure.

Read this when you want the graph viewer to stay docked in the IDE, for example beside the Structure form, instead of floating. Choose drag-lint > drag-lint Graph (dockable); it needs the plugin loaded and drag_lint_graph.exe deployed beside it.

## Where to click

* RAD Studio main menu: **drag-lint > drag-lint Graph (dockable)**
   1. Choose drag-lint > drag-lint Graph (dockable)
   2. The graph viewer opens as a dockable window; drag it where you want it to stay docked

## Details

Opens the drag-lint graph viewer as a dockable window inside the IDE, so it
can sit beside Structure. Reach for it to keep the graph viewer docked
instead of a separate window.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs the drag-lint plugin loaded in the IDE, and requires
`drag_lint_graph.exe` deployed beside the plugin's BPL (per the
[IDE Menu Reference](ide-menu-reference.md)).

### Example
Illustrative: choose "drag-lint > drag-lint Graph (dockable)" to dock the
graph viewer beside the Structure form.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
