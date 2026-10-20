# Find Usages (context)

Lists references to the symbol represented by a Structure-tree node. Reach
for it when you are browsing the Structure outline and want the usages of a
symbol without first navigating to it in the editor and using the main
"Find Usages..." menu item (a separate, in-process feature-map row).

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Find Usages".

## Running it from the CLI

The feature map lists the underlying verb as `usages`. See the
[usages](usages) page for the full flag list; this page covers only the
right-click Structure-tree access path.

## What it needs

Optional, per the feature map's Index column.

## Example

Illustrative: with the Structure form open, right-click the node for
`TMyClass.DoWork` and choose "Find Usages" to list every reference to
`DoWork` across the indexed project.
