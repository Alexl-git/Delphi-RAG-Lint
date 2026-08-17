# Circular Uses Report (cycles + fix plan)

Finds `uses` cycles among indexed units and, on request, proposes a followable
refactoring plan to break them. Reach for it when the compiler is fighting
circular references, or a project's dependency graph feels tangled.

## Running it from the CLI
```
drag-lint cycles --db <file.sqlite> [--edges] [--causes] [--plan] [--format json|text]
```
`--edges` and `--causes` add detail to the cycle report; `--plan` produces the
followable refactoring playbook; `--format` selects `json` or `text` output.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...

## What it needs
Required. You must have indexed the project before running this -- cycle
detection reads unit-to-unit `uses` edges from the index, not from disk.

## Example
Illustrative only, against a project database that has already been indexed:
```
drag-lint cycles --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --plan --format text
```
This would report any `uses` cycles involving, say, the unit that declares
`TfrmMain`, plus a suggested order of moves to break them.
