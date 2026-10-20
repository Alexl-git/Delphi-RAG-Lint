# drag-lint Graph (dockable)

Opens the drag-lint graph viewer as a dockable window inside the IDE, so it
can sit beside Structure. Reach for it to keep the graph viewer docked
instead of a separate window.

## Reaching it in the IDE
drag-lint > drag-lint Graph (dockable)

Also reachable from View > Tool Windows > drag-lint Graph -- the same
dockable window under a second menu path; see
[drag-lint Graph](drag-lint-Graph) for that entry.

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
Illustrative: choose "drag-lint > drag-lint Graph (dockable)" to dock the
graph viewer beside the Structure form.
