# Go to Implementation

Jumps the editor caret to the implementation of the symbol represented by a
Structure-tree node. Reach for it when the tree node you are on is a
declaration (for example an interface method or a forward-declared routine)
and you want the actual implementation body instead.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Go to Implementation".

## Running it from the CLI

No CLI equivalent - this is an editor navigation action.

## What it needs

Not needed. The feature map marks this row's Index column "n/a" and its
Mechanism "in-process" -- it does not shell out to the CLI or query an index
database.

## Example

Illustrative: with the Structure form open, right-click the node for
`TMyClass.DoWork` and choose "Go to Implementation". The editor jumps to the
`procedure TMyClass.DoWork;` body in the implementation section.
