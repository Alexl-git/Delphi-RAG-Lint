# Find Usages...

Lists every reference to the symbol under the editor caret across the
indexed project. Reach for it before changing or removing a symbol, to see
everywhere it is used.

## Reaching it in the IDE
drag-lint > Find Usages...

Keyboard shortcut: Ctrl+Alt+F.

## Running it from the CLI
There is no standalone CLI verb for this menu item (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes find-references over stdio to other
editors -- the [Features](Features) page lists find-references among the
methods `drag-lint lsp` implements -- but that is a stdio protocol server,
not a one-shot CLI command.

This is a different feature-map row from the right-click "Find Usages"
action on a Structure-tree node, which does have an underlying verb -- see
[Find Usages (context)](Find-Usages-context).

## What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs an open editor with the caret on the target symbol.

## Example
Illustrative: with the caret on `TCustomerOrder.Total`, choose "Find
Usages..." to list every reference to `Total` across the indexed project.
