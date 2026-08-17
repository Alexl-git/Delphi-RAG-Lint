# Uses Audit -- interface->impl moves + unused (this unit)

For one unit, reports which `uses` entries could move from the `interface`
section to `implementation`, and which are unused entirely. Reach for it when
cleaning up a single unit's uses clauses before a rename or refactor.

## Running it from the CLI
```
drag-lint uses-audit <unit.pas> --db <file.sqlite> [--format json|text]
```

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Uses Audit -- interface->impl moves + unused (this unit)...

## What it needs
Required. You must have indexed the project first -- the audit resolves
symbol usage against the index, not by re-parsing the unit alone.

## Example
Illustrative only:
```
drag-lint uses-audit C:\Projects\MyApp\CustomerOrder.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format text
```
This would report, for `CustomerOrder.pas`, which units in its `uses` clause
(for example one only referenced by a class such as `TCustomerOrder`) could
move to `implementation`, and which are not referenced at all.
