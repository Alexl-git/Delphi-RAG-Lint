# convert-validate

Parses and validates a conversion-rules file (a reFind-superset DSL), checking
its `#link`/`#default` paths against the real property trees. Reach for it
before running `convert-scaffold` or `convert-apply`, to confirm a hand-edited
or generated rules file is well-formed.

## Running it from the CLI
```
drag-lint convert-validate --rules <file> [--from <FromType>] [--to <ToType>] [--print-parsed] [--db PATH ...]
```
`--rules <file>` is the conversion-rules file to validate. `--from`/`--to`
name the source and target types (optional). `--print-parsed` prints the
parsed rules. `--db PATH ...` is optional and may be repeated.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
Optional, per the feature map's Index column.

## Example
Illustrative only:
```
drag-lint convert-validate --rules C:\Projects\MyApp\convert-rules\OvcTable-to-cxGrid.rules --from TOvcTable --to TcxGrid --print-parsed
```
This would parse the rules file and report whether its `#link`/`#default`
paths resolve against the real `TOvcTable` and `TcxGrid` property trees.
