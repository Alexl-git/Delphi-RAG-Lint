# Compile Buffer (unsaved)

Compiles a project with the current editor buffer's unsaved content
in place of its file on disk, and never writes your real files: the
unsaved buffers are staged in a temporary shadow directory and compiled
there. Reach for it to get compiler diagnostics against unsaved edits
without saving them first.

## Running it from the CLI
The feature map lists this action's CliVerb as "(none - in-process)", but
this IDE action actually runs the `ghost-check` verb. Running it bare
prints its own usage banner and exits 2:
```
Usage: drag-lint ghost-check <dproj> ( --unit <real.pas> --buffer <buf> | --overlays <manifest> ) [--platform win32|win64] [--in-place] [--format json|text]
```
`<dproj>` is the project to compile. Give either a single
`--unit <real.pas> --buffer <buf>` pair, or an `--overlays <manifest>`
file listing multiple real-path/buffer-path pairs. `--platform` selects
`win32` or `win64`; `--format` selects `json` or `text`.

By default every buffer is staged into one temporary shadow directory and
each dirty unit is compiled against it (dcc, shadow directory first on the
unit search path, in full project context). The real files are not touched,
no timestamp is stamped, no `_D-RAG` journal is written and no `.dcu` is
deleted, so the IDE sees no change on disk. The trade-off: only the dirty
units are compiled, so an error in a SAVED unit newly caused by a dirty
unit's interface change is not caught. `--in-place` selects the old
behaviour (dangerous, nothing in the plugin passes it): the real files are
overwritten with the buffers for the duration of one whole-project compile,
then restored with their exact content and timestamp (crash-journaled in
`_D-RAG`).

## Reaching it in the IDE
drag-lint > Compile Buffer (unsaved)

## What it needs
The feature map marks this row's Index column "n/a". It needs the active
project (the `.dproj`) and the unsaved buffer content for the unit being
compiled.

## Example
Illustrative only:
```
drag-lint ghost-check C:\Projects\MyApp\MyApp.dproj --unit C:\Projects\MyApp\frmOrders.pas --buffer C:\Projects\MyApp\_D-RAG\frmOrders.buf --platform win32 --format json
```
This would compile `frmOrders.pas` from the buffer file in a temporary
shadow directory (in the context of `MyApp.dproj`) and report diagnostics as
JSON; `frmOrders.pas` on disk is never written.
