# extract-method

Pulls a run of statements out of a routine into a new method. Reach for it
when refactoring a long routine and you want the mechanical extraction done
for you rather than by hand.

## Running it from the CLI

```
drag-lint extract-method --file <F> --from-line <L1> --to-line <L2> --name <N> [--json|--apply|--no-backup]
```

`--file` is the source file; `--from-line`/`--to-line` bound the statement
run to extract; `--name` is the new method's name. The usage line lists
`--apply` as a flag; whether omitting it produces a dry run is not
documented in the help text for this verb.

## Reaching it in the IDE

The feature map's internal call site is `DragLint.Plugin.Keyboard.pas:319`
-- a keyboard-bound plugin action, not a menu item. Beyond that call site,
no menu path or keybinding is documented for this verb, so it is not stated
here.

## What it needs

No index required -- the usage line has no `--db` flag; `extract-method`
operates directly on the given file's line range.

## Example

Illustrative:

```
drag-lint extract-method --file C:\Projects\MyApp\Unit1.pas --from-line 120 --to-line 135 --name ValidateInput --apply
```

This would pull lines 120-135 of `Unit1.pas` into a new method named
`ValidateInput`.
