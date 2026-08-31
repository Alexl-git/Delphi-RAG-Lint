# Fix it

Applies the autofix for the single lint finding represented by a
Structure-tree node. Reach for it when you are looking at one finding and
want it fixed without touching anything else in the unit.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

**The Structure form's right-click menu is the only place autofix
("Fix it", "Fix all in unit", "Fix all in project") is reachable in the
IDE** -- there is no main drag-lint menu item for it.

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click the tree node for a finding and choose "Fix it".

## Running it from the CLI

The menu item runs `lint` with the autofix flags:

```
drag-lint lint --file <path.pas> --fix --fix-line <L> --fix-rule <rule-id> --apply
```

`--fix-line` and `--fix-rule` narrow the fix to the ONE finding you
right-clicked. Without `--apply` the command is a DRY RUN: it reports what
it would fix and writes nothing.

Only rules marked fixable can be auto-fixed. `drag-lint rules --json`
reports a `fixable` field per rule; 22 of the 179 rules are fixable.

## What it needs

No index required -- `lint --file` works on a single file. (An index is
still needed for the Structure form itself to populate.)

## Example

Dry run first, to see what would change:
```
drag-lint lint --file C:\Projects\MyApp\Unit1.pas --fix
```
Typical output when nothing is fixable:
```
autofix: no fixable findings (of 13 finding(s))
```
Then apply one specific finding:
```
drag-lint lint --file C:\Projects\MyApp\Unit1.pas --fix --fix-line 42 --fix-rule bare-except --apply
```
