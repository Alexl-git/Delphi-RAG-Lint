# Find Dead Code

Scans the index for code with no references -- candidates to delete. Reach
for it before a cleanup pass or before removing something you suspect is
unused.

## Running it from the CLI
```
drag-lint find-deadcode [--kind method|function|...] [--include-private] [--db PATH]
```
`--kind` filters by symbol kind (for example `method` or `function`);
`--include-private` also considers private members.

## Reaching it in the IDE
drag-lint > Code Quality > Find Dead Code...

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint find-deadcode --kind method --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would list methods in `MyApp`'s index with no resolved references.
