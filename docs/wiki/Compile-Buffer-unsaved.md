# Compile Buffer (unsaved)

Compiles a project with the current editor buffer's unsaved content
substituted for its file on disk, then restores the original file
unchanged. Reach for it to get compiler diagnostics against unsaved edits
without saving them first.

## Running it from the CLI
The feature map lists this action's CliVerb as "(none - in-process)", but
this IDE action actually runs the `ghost-check` verb. Running it bare
prints its own usage banner and exits 2:
```
Usage: drag-lint ghost-check <dproj> ( --unit <real.pas> --buffer <buf> | --overlays <manifest> ) [--platform win32|win64] [--format json|text]
```
`<dproj>` is the project to compile. Give either a single
`--unit <real.pas> --buffer <buf>` pair, or an `--overlays <manifest>`
file listing multiple real-path/buffer-path pairs. `--platform` selects
`win32` or `win64`; `--format` selects `json` or `text`.

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
This would compile `MyApp.dproj` with `frmOrders.pas`'s content replaced
by the buffer file, report diagnostics as JSON, then restore
`frmOrders.pas` unchanged.
