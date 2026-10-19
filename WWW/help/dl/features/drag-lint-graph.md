---
id: drag-lint-graph
title: drag-lint Graph
summary: "This page documents the \"View > Tool Windows > drag-lint Graph\" menu entry -- the drag-lint graph viewer"
product: DL
group: editor-integration
order: 110002
since: 0.10.0-alpha
status: shipped
updated: 0.10.0-alpha
---

# drag-lint Graph

This page documents the "View > Tool Windows > drag-lint Graph" menu entry -- the drag-lint graph viewer.

## Where to click

* Tool window: **View > Tool Windows > drag-lint Graph**

## Details

This page documents the "View > Tool Windows > drag-lint Graph" menu entry
-- the drag-lint graph viewer, reached from RAD Studio's standard Tool
Windows menu instead of the drag-lint menu. It is the same window as
[drag-lint Graph (dockable)](drag-lint-graph-dockable.md); see that page for
the drag-lint-menu path to it.

### Reaching it in the IDE
View > Tool Windows > drag-lint Graph

No keyboard shortcut is documented for this menu item.

### Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin.

### What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs the drag-lint plugin loaded in the IDE, and requires
`drag_lint_graph.exe` deployed beside the plugin's BPL (per the
[IDE Menu Reference](ide-menu-reference.md)).

### Example
Illustrative: choose "View > Tool Windows > drag-lint Graph" to open the
graph viewer.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
