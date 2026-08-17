# Copy All Diagnostics

Puts every lint finding for the current unit onto the clipboard, starting
from the Structure form. Reach for it when you want to paste a unit's full
findings list elsewhere (a chat, an issue, a note) instead of reading them
in the IDE.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a tree node and choose "Copy All Diagnostics".

## Running it from the CLI

The feature map lists the underlying verb as `lint`. From the usage banner:

```
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json]
```

This runs the lint pass on a file and prints its findings. The
"copy to clipboard" behavior is an IDE-side convenience on top of this
verb; the CLI itself only prints, it does not clipboard-copy.

## What it needs

No index required -- `lint <path>` lints the given file directly, without
going through a project index database.

## Example

Illustrative:

```
drag-lint lint C:\Projects\MyApp\Unit1.pas --json
```

This would print `Unit1.pas`'s findings as JSON; the IDE action copies the
equivalent findings text to the clipboard instead.
