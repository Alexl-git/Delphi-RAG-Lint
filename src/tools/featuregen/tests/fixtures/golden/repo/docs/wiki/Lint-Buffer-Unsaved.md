# Lint Buffer (Unsaved)

Lints the current editor buffer's in-memory content, including unsaved
edits, without writing it to disk first. Reach for it to see lint findings
for changes you have not saved yet.

## Running it from the CLI
The feature map lists this action's CliVerb as `lint`, but its Mechanism
is "in-process" -- the IDE lints the in-memory buffer directly rather than
shelling out to the CLI. The nearest CLI equivalent operates on a saved
file on disk:
```
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]
```

## Reaching it in the IDE
drag-lint > Lint Buffer (Unsaved)

## What it needs
No index needed. This action lints the buffer's content directly; the
feature map marks this row's Index column "no".

## Example
Illustrative only, showing the CLI verb this action's findings correspond
to once a file is saved:
```
drag-lint lint C:\Projects\MyApp\Unit1.pas --json
```
The IDE action produces the equivalent findings for the unsaved buffer,
in-process, without this shell-out.
