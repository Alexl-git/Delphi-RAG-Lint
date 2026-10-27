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

## Asking about ONE unit, library units included

`--only <Unit>` narrows the run to the units you name. Candidates are normally
chosen from the PROJECT index, which never contains RTL, VCL or third-party
library units -- so before 2026-10-13 a library unit came back `unmatched`.
Now a unit you name that is in the uses clause is decided by compiling,
whichever index it lives in:

* no `initialization`/`finalization` section -> **removed** (needs
  `--remove-unused`);
* otherwise, when it is an interface entry -> **moved** to the implementation
  `uses` (the section keeps running, so a unit with one is never removed);
* when neither edit compiles -> `skipped`, with the reason.

The section is read from the platform library index (or `--library-db`), the
same one the `unused-unit-in-uses` rule reads. This is what the IDE's
[Fix it](Fix-it) runs on an `unused-unit-in-uses` finding:

```
drag-lint uses-fix Unit1.pas --project MyApp.dproj --db MyApp.sqlite --platform win32 --remove-unused --only System.Win.Registry --apply --format json
```

Each try is a real compile of the unit, so expect seconds to a minute or more
for a large unit.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Uses Cleanup Preview (compiler-verified)...

## What it needs
Required. You must have indexed the project first.

## Example
Illustrative only:
```
drag-lint uses-fix C:\Projects\MyApp\CustomerOrder.pas --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --platform win32
```
This would preview the compiler-verified uses cleanup for `CustomerOrder.pas`
without changing the file; add `--apply` to write it.
