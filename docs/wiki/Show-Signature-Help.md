# Show Signature Help

Shows parameter help for the call being typed at the editor caret. Reach
for it to check a routine's parameter list and order while writing a call.

## Reaching it in the IDE
drag-lint > Show Signature Help

Keyboard shortcut: Ctrl+Alt+S.

## Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes signature help over stdio to other editors
-- the [Features](Features) page lists signature help among the methods
`drag-lint lsp` implements -- but that is a stdio protocol server, not a
one-shot CLI command.

## What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs an open editor with the caret inside a call's
argument list.

## Example
Illustrative: position the caret inside the parentheses of a call to
`TCustomerOrder.Create(...)` and press Ctrl+Alt+S to show that
constructor's parameter help.
