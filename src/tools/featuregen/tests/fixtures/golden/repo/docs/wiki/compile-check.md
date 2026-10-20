# compile-check

Runs a compiler-backed check against a single Delphi project (`.dproj`) or
source file (`.pas`) and reports the result. Reach for it when you want a
compile-style verification of one target without a full project build.

## Running it from the CLI

```
drag-lint compile-check <target.dproj|.pas> [--db PATH] [--format json|text]
```

## Reaching it in the IDE

CLI+internal: the plugin calls this internally from
`DragLint.Plugin.Editor.pas:2037`. There is no menu item for it -- it is
invoked in-process by the plugin, not exposed as a user-facing command.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint compile-check C:\Projects\MyApp\MyApp.dproj --format json
```

This would compile-check `MyApp.dproj` and print the result as JSON.
