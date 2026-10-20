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

A `#link` may carry a glyph expression after its FromPath --
`#link OptionsImage.Glyph <- Picture G[*/4], G[1/5]G[2/5]G[3/5]G[4/5] : AssignGraphic`
(`G[I/N]` slot I of N, `G[I]`, `G[*/N]`, `G[count]`; terms side by side stitch,
commas separate per-N alternatives). It is checked even without `--from`/`--to`:
malformed terms, I or N out of range, two alternatives for one N, and a
`G[count]` without exactly one image link are errors that name the column inside
the expression. `line N: warning: ...` lines (a straight `NumGlyphs` carry beside
a G-link) never change the exit code. `convert-apply` refuses a G-linked book
until the extraction build lands. Full grammar: `docs\CONVERSION-RULES.md`.

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
