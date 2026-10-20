# Symbol Search...

Searches symbols by name across the indexed projects. Reach for it to jump
to a type, method, or field when you know (or can guess) its name but not
its file.

## Reaching it in the IDE
drag-lint > Symbol Search...

Keyboard shortcut: Ctrl+Alt+T.

## Running it from the CLI
```
drag-lint query --name <symbol-name> [--db <file.sqlite>] [--json] [--case-sensitive] [--exact]
drag-lint query --qname <qualified> [--db <file.sqlite>] [--json] [--case-sensitive]
```
`--name`/`--qname` match case-insensitively by default (`--case-sensitive`
restores byte-exact matching); `--name` also accepts a qualified name.
`--exact` suppresses the fuzzy fallback, so zero rows means "no such
symbol". The same lookup is also exposed over stdio as the language
server's "workspace symbols" method (the [Features](Features) page lists
it under `drag-lint lsp`).

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint query --name TCustomerOrder --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would return every symbol named `TCustomerOrder` (exact or fuzzy) as
JSON.
