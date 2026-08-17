# Run Diagnostics (didSave)

Runs drag-lint's diagnostics pass on a file automatically when it is
saved, mirroring the LSP `textDocument/didSave` notification. Reach for
it indirectly -- it is not something you invoke by hand; it fires on save.

## Running it from the CLI
No CLI equivalent. The feature map lists this action's CliVerb as
"(none - in-process)" and its Mechanism as "in-process" -- it runs inside
the plugin without shelling out to the drag-lint executable.

## Reaching it in the IDE
drag-lint > Run Diagnostics (didSave)

## What it needs
Not documented as needing an index -- the feature map marks this row's
Index column "n/a". Since it fires on save, it needs an open editor with
a saved file.

## Example
Illustrative only: saving a unit in the editor triggers this action, which
runs diagnostics on the just-saved file and updates its findings.
