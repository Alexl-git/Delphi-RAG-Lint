# drag-lint Graph

This page documents the "View > Tool Windows > drag-lint Graph" menu entry
-- the drag-lint graph viewer, reached from RAD Studio's standard Tool
Windows menu instead of the drag-lint menu. It is the same window as
[drag-lint Graph (dockable)](drag-lint-Graph-dockable); see that page for
the drag-lint-menu path to it.

## Reaching it in the IDE
View > Tool Windows > drag-lint Graph

No keyboard shortcut is documented for this menu item.

## Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin.

## What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs the drag-lint plugin loaded in the IDE, and requires
`drag_lint_graph.exe` deployed beside the plugin's BPL (per the
[IDE Menu Reference](IDE-Menu-Reference)).

## Example
Illustrative: choose "View > Tool Windows > drag-lint Graph" to open the
graph viewer.
