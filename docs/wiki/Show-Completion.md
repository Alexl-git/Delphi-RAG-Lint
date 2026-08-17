# Show Completion

Shows an index-backed completion list at the editor caret. Reach for it to
see what identifiers are valid to type next.

## Reaching it in the IDE
drag-lint > Show Completion

Keyboard shortcut: Ctrl+Alt+C.

## Running it from the CLI
There is no standalone CLI verb for this (feature map CliVerb:
"(none - in-process)"). It is served in-process by the IDE plugin. The
bundled language server exposes completion over stdio to other editors --
the [Features](Features) page lists completion among the methods
`drag-lint lsp` implements -- but that is a stdio protocol server, not a
one-shot CLI command.

## What it needs
The feature map marks this row's Index column "n/a" and its Mechanism
"in-process". It needs an open editor buffer with the caret positioned
where completion is requested.

## Example
Illustrative: type a partial identifier in the editor and press Ctrl+Alt+C
to show the completion list for what follows.
