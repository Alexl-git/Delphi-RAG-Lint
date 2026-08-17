# context

Returns a compact context bundle for a symbol -- its doc comment, class
surface (signatures), the target's own body, and a capped list of callers
-- instead of whole source files. Reach for it before editing or explaining
a symbol so you read a fraction of the tokens a full-file read would cost.

## Running it from the CLI
```
drag-lint context --task "verb qname" [--db <file.sqlite>] [--format md|json|raw] [--max-callers N] [--context N] [--no-docs]
```
`--task "verb qname"` names the symbol and intended action (e.g. `"modify
Foo.Bar"`). `--format` selects `md`, `json`, or `raw`. `--max-callers N`
caps how many callers are included. `--context N` is present in the usage
line; its effect is not documented beyond the flag name. `--no-docs` omits
doc comments from the bundle.

## Reaching it in the IDE
No menu item calls this directly. The plugin uses it internally from
`DragLint.Plugin.Editor.pas:633`; there is no menu item for it. The MCP
`get_context_bundle` tool wraps this same engine.

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint context --task "modify CustomerOrder.TCustomerOrder.Total" --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format md
```
This would return `Total`'s doc comment, its class's surface, its own body,
and a capped list of callers, as markdown.
