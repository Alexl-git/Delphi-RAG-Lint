# Find Undocumented (public)

Uses `query find` to list indexed symbols filtered by documentation state,
kind, or visibility. Reach for it to see which public symbols still have no
DocInsight comment.

## Running it from the CLI
```
drag-lint query find [--doc-tag X | --doc-contains Y | --no-docs] [--kind K] [--public] [--db ...]
```
`--no-docs` restricts results to symbols with no doc comment; `--public`
restricts to public symbols; `--doc-tag`/`--doc-contains` filter by tag or
tag content instead of by absence; `--kind` filters by symbol kind.

`--doc-tag` accepts exactly nine tags: `summary`, `remarks`, `returns`,
`param`, `exception`, `example`, `seealso`, `since`, `deprecated`. An
unrecognized tag errors (exit 2) and lists the valid set.

## Reaching it in the IDE
drag-lint > Code Quality > Find Undocumented (public)...

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint query find --no-docs --public --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would list `MyApp`'s public symbols that carry no doc comment.
