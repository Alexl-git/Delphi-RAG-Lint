# Add Missing Units to uses (whole unit)

The whole-unit form of the undeclared-identifier quick-fix: resolves every
unresolved name in a unit at once and adds the units that declare them. Reach
for it after a large paste or a big refactor leaves several names unresolved.

## Running it from the CLI
```
drag-lint check-unit <unit.pas> [--project <dproj>] [--platform win32|win64] [--shadow <dir>] [--resolve-uses] [--db PATH] [--format json|text]
```
`--resolve-uses` is what drives the add-missing-units behaviour; `--project`
and `--platform` scope the check; `--shadow <dir>` and `--format` are also available.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Add Missing Units to uses (whole unit)...

## What it needs
Optional. An index is not marked required, but resolving names to their
declaring units depends on what has been indexed.

## Example
Illustrative only:
```
drag-lint check-unit C:\Projects\MyApp\CustomerOrder.pas --project C:\Projects\MyApp\MyApp.dproj --resolve-uses --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would resolve every unresolved name in `CustomerOrder.pas` and add the
units that declare them.
