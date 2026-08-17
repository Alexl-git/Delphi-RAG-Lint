# ghost-recover

Scans a project's hidden `_D-RAG` folder for recovery journals left behind
when a `ghost-check` overlay was interrupted by a crash, and restores each
affected file to its saved original content. Reach for it (or let the IDE run
it automatically) after a crash during a buffer-compile, so no unit is left
holding overlaid (unsaved-buffer) content.

## Running it from the CLI
Running the verb bare (no arguments) does not print a usage banner; it runs
immediately and prints `ghost-recover: nothing pending.` (exit 0) when there
is no recovery journal, or `ghost-recover: N file(s) restored.` after acting.
Passing `--help` or any unrecognized flag produces
`FATAL: Exception: Unknown argument: <flag>` -- no other flags are documented.

The plugin invokes it as:
```
drag-lint ghost-recover "<path-to-.dproj-or-folder>"
```
The single positional argument is optional; if omitted it defaults to the
current directory.

## Reaching it in the IDE
No menu item calls this by name directly; the feature map's "Recover
Buffer-Compile Files" menu item is the user-facing action for it. The
plugin's editor code (Editor.pas:2522) shells out to this verb, both on
demand and automatically after a project loads, to restore any file left
overlaid by a crashed ghost-check.

## What it needs
Not needed, per the feature map's Index column.

## Example
Illustrative only:
```
drag-lint ghost-recover C:\Projects\MyApp\MyApp.dproj
```
This would scan `C:\Projects\MyApp\_D-RAG` for ghost-check recovery journals
and restore any affected file to its saved original content.
