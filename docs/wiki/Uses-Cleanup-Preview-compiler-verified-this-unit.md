# Uses Cleanup Preview (compiler-verified, this unit)

The removals a Uses Audit suggests, but verified by actually compiling -- so
a unit only needed for an inline routine or a `{$IF}` branch is not stripped
by mistake. Reach for it before applying an audit's suggestions.

## Running it from the CLI
```
drag-lint uses-fix <unit.pas> --project <dproj> --db <file.sqlite> [--platform win32|win64] [--apply] [--remove-unused]
```
Without `--apply` this previews the cleanup; `--apply` writes it.
`--remove-unused` extends the cleanup to unused units; `--platform` selects
`win32` or `win64`.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Uses Cleanup Preview (compiler-verified, this unit)...

## What it needs
Required. You must have indexed the project first.

## Example
Illustrative only:
```
drag-lint uses-fix C:\Projects\MyApp\CustomerOrder.pas --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --platform win32
```
This would preview the compiler-verified uses cleanup for `CustomerOrder.pas`
without changing the file; add `--apply` to write it.
