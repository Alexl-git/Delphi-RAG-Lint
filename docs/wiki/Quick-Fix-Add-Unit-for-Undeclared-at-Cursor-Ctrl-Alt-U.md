# Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)

Finds which unit declares the identifier under the caret and adds that unit
to the current unit's `uses` clause. Reach for it right where the compiler
would otherwise report an undeclared identifier.

## Running it from the CLI
No CLI equivalent - this action is in-process only.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)

## What it needs
n/a. This action runs in-process against the open editor buffer; the feature
map does not mark it as needing a separate index step.

## Example
Illustrative only: place the caret on an undeclared identifier -- for example
a reference to `TCustomerOrder` in a unit that has not yet added the unit
that declares it -- and invoke the quick-fix (or press Ctrl+Alt+U) to add the
declaring unit to `uses`.
