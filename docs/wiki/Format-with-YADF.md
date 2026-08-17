# Format with YADF

Formats a single file's source using YADF (Yet Another Delphi Formatter).
Reach for it to reformat the current file to house style without leaving
the IDE.

## Running it from the CLI
```
drag-lint format <file> [--yadf-path PATH]
```
`<file>` is the file to format; `--yadf-path` overrides the YADF
executable location if it is not on the default path.

## Reaching it in the IDE
drag-lint > Format with YADF

## What it needs
No index needed. This action formats the file directly; the feature map
marks this row's Index column "no". It needs a file to format -- the
current editor buffer's file in the IDE, or a path given on the command
line.

## Example
Illustrative only:
```
drag-lint format C:\Projects\MyApp\Unit1.pas
```
This would reformat `Unit1.pas` in place using YADF.
