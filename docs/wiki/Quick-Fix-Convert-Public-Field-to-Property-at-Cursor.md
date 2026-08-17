# Quick-Fix: Convert Public Field to Property at Cursor

Rewrites a public field under the caret as a property. Reach for it when
tightening up a class's public surface.

## Running it from the CLI
No CLI equivalent - this action is in-process only.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Quick-Fix: Convert Public Field to Property at Cursor

## What it needs
n/a. This action runs in-process against the open editor buffer; the feature
map does not mark it as needing a separate index step.

## Example
Illustrative only: place the caret on a public field -- for example
`FCustomer: TCustomerOrder;` exposed directly on `TfrmMain` -- and invoke the
quick-fix to convert it into a property.
