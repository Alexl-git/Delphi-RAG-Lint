# ghost-check

Compiles a project with one or more units' content temporarily replaced by
their unsaved editor buffers, then restores the original files unchanged.
Reach for it to get compiler diagnostics against unsaved edits without
saving them to disk.

## Running it from the CLI
```
drag-lint ghost-check <dproj> ( --unit <real.pas> --buffer <buf> | --overlays <manifest> ) [--platform win32|win64] [--format json|text]
```
`<dproj>` is the project to compile. Give either a single
`--unit <real.pas> --buffer <buf>` pair, or an `--overlays <manifest>` file
listing multiple real-path/buffer-path pairs. `--platform` selects `win32`
or `win64`. `--format` selects `json` or `text`.

## Reaching it in the IDE
No menu item calls this directly. The plugin's editor code (Editor.pas:2489)
shells out to this verb to compile the active project against unsaved buffer
content, backing "Compile Buffer (unsaved)" and feeding "Compile & Diagnose".

## What it needs
Not needed, per the feature map's Index column.

## Example
Illustrative only:
```
drag-lint ghost-check C:\Projects\MyApp\MyApp.dproj --unit C:\Projects\MyApp\frmOrders.pas --buffer C:\Projects\MyApp\_D-RAG\frmOrders.buf --platform win32 --format json
```
This would compile `MyApp.dproj` with `frmOrders.pas`'s content replaced by
the buffer file, report diagnostics as JSON, then restore `frmOrders.pas`
unchanged.
