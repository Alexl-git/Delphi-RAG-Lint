# Copy Diagnostics (Current File)

Puts the current file's lint findings onto the clipboard. Reach for it to
paste a file's findings elsewhere (a chat, an issue, a note) instead of
reading them in the IDE.

## Running it from the CLI
```
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]
```
This runs the lint pass on a file and prints its findings. The
clipboard-copy behavior is an IDE-side convenience on top of this verb;
the CLI itself only prints.

## Reaching it in the IDE
drag-lint > Copy Diagnostics (Current File)

## What it needs
No index needed. `lint <path>` lints the given file directly, without
going through a project index database; the feature map marks this row's
Index column "no".

## Example
Illustrative only:
```
drag-lint lint C:\Projects\MyApp\Unit1.pas --json
```
This would print `Unit1.pas`'s findings as JSON; the IDE action copies
the equivalent findings text to the clipboard instead.
