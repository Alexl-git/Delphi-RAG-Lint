# Run AST Checks

Runs drag-lint's AST-level checks against a file. Reach for it to validate
a file's parse tree and catch AST-detectable issues directly.

## Running it from the CLI
```
drag-lint check-ast <file> [--db PATH] [--format text|json]
```
`<file>` is the file to check; `--db` is an index database; `--format`
selects `text` or `json` output.

## Reaching it in the IDE
drag-lint > Run AST Checks

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint check-ast C:\Projects\MyApp\Unit1.pas --format json
```
This would run AST checks on `Unit1.pas` and print the results as JSON.
