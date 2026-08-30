# Fix all in unit

Applies autofixes for every fixable finding in the current unit, starting
from the Structure form. Reach for it when a unit has several fixable
findings and you want them all resolved in one action.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

**The Structure form's right-click menu is the only place autofix
("Fix it", "Fix all in unit", "Fix all in project") is reachable in the
IDE** -- there is no main drag-lint menu item for it.

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a tree node and choose "Fix all in unit".

## Running it from the CLI

The menu item runs `lint` with the autofix flags, unscoped -- no
`--fix-line`/`--fix-rule`, so every fixable finding in the file is applied:

```
drag-lint lint --file <path.pas> --fix --apply
```

Without `--apply` the command is a DRY RUN: it reports what it would fix
and writes nothing. Always dry-run first.

Only rules marked fixable are applied; 22 of the 178 rules are fixable
(`drag-lint rules --json` reports a `fixable` field per rule).

## What it needs

No index required -- `lint --file` works on a single file.

## Example

Dry run:
```
drag-lint lint --file C:\Projects\MyApp\Unit1.pas --fix
```
Typical output when nothing is fixable:
```
autofix: no fixable findings (of 13 finding(s))
```
Apply for real:
```
drag-lint lint --file C:\Projects\MyApp\Unit1.pas --fix --apply
```
