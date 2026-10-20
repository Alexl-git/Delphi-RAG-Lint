# Compile & Diagnose

Compiles a project or unit and folds the compiler's errors and warnings
into drag-lint findings. Reach for it to get compiler diagnostics for the
current file or project without leaving the IDE.

## Running it from the CLI
The feature map lists this action's CliVerb as "(none - in-process)", but
this IDE action actually runs the `compile-check` verb:
```
drag-lint compile-check <target.dproj|.pas> [--db PATH] [--format json|text]
```
`<target.dproj|.pas>` is the project or unit to compile; `--db` is an
index database; `--format` selects `json` or `text` output.

## Reaching it in the IDE
drag-lint > Compile & Diagnose

## What it needs
The feature map marks this row's Index column "n/a". It needs an active
project or the current file to compile, and an open editor to show the
resulting diagnostics.

## Example
Illustrative only:
```
drag-lint compile-check C:\Projects\MyApp\MyApp.dproj --format json
```
This would compile `MyApp.dproj` and print the resulting diagnostics as
JSON.
