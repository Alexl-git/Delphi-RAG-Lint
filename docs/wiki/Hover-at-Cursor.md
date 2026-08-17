# Hover at Cursor

Shows a hover card for the symbol under the editor caret: signature,
documentation, and callers. Reach for it to check what a symbol is and how
it is used without leaving the line you are on.

## Reaching it in the IDE
drag-lint > Hover at Cursor

Keyboard shortcut: Ctrl+Alt+H.

## Running it from the CLI
In the IDE this action is served in-process (the feature map's Mechanism
column marks it "in-process") -- no exe is spawned per hover. The same
capability is also exposed as a standalone CLI verb, and over stdio by the
bundled language server (the [Features](Features) page lists hover among
the methods `drag-lint lsp` implements):
```
drag-lint hover --qname <Foo.Bar> [--db <file.sqlite>] [--format plain|md|json]
```
`--qname` is the fully qualified symbol; `--format` selects plain text,
markdown, or JSON.

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist. In the IDE, it also needs an open
editor with the caret on a symbol.

## Example
Illustrative only:
```
drag-lint hover --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format md
```
This would print the hover card for the `Total` member of `TCustomerOrder`
as markdown.
