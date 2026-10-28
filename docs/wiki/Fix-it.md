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
drag-lint lint --in <path.pas> --fix --fix-line <L> --fix-rule <rule-id> --apply
```

`--fix-line` and `--fix-rule` narrow the fix to the ONE finding you
right-clicked. Without `--apply` the command is a DRY RUN: it reports what
it would fix and writes no source file -- and, for a naming fix, no index
either (a stale owning index is reported `index=stale`, not reindexed). With
`--apply`, a naming fix may first reindex stale owning project indexes (see
[Multi-Project-Rename](Multi-Project-Rename)).

Only rules marked fixable can be auto-fixed. `drag-lint rules --json`
reports a `fixable` field per rule; 110 of the 289 rules are fixable.

## Unused units (`unused-unit-in-uses`)

"Fix it" on an `unused-unit-in-uses` finding does not use `lint --fix`. It
asks the compiler-verified [uses-fix](Uses-Cleanup-Preview-compiler-verified-this-unit)
verb about that ONE unit, which decides by compiling:

* **removed** -- nothing needs the unit and it has no initialization section;
* **moved to the implementation section** -- only the implementation needs it,
  or it has an initialization section (moving keeps that running; removing
  could build cleanly and break at runtime);
* **no change** -- neither edit compiles; the reason is shown.

It needs an active project with an index (the same one a save reindexes), and
it compiles the unit up to three times, so it can take a minute on a large
unit. The result is reported in the status strip and the Messages pane, e.g.
`applied 1 edit(s): System.Win.Registry removed (.bak written)`. The CLI form:

```
drag-lint uses-fix <Unit.pas> --project <App.dproj> --db <App.sqlite> --platform win32 --remove-unused --only <UnitName> --apply --format json
```

## While it runs, and afterwards

* It runs in the background on the drag-lint job queue; the status strip
  shows it, and the result appears on the Diagnostics root row.
* On a NAMING finding (`const-casing`, `type-name-prefix`,
  `local-var-casing`, ...) "Fix it" RENAMES the symbol -- its declaration and
  every use the project index knows about (e.g. `wrStr` -> `WrStr`). Asking for
  that ONE finding is an explicit request and wins even over `"autofix_off"`. It needs the project index, and is not
  offered without one. A naming fix runs a PREVIEW first (nothing written):
  when the unit is compiled by two or more indexed projects, a confirmation
  lists every one of them and the rename happens in all of them or in none --
  see [Multi-Project-Rename](Multi-Project-Rename). A refusal (a conflicting
  name, an index that could not be refreshed, ...) is shown on the Diagnostics
  root row as `rename refused -- <project>: <reason>`.
* A constant is renamed WORD BY WORD, to the first style in `const_case`
  (the Lint Options tab of the drag-lint Panel; default PascalCase, then UPPER_CASE):
  `StationType_Operator` -> `StationTypeOperator` (PascalCase) or
  `STATION_TYPE_OPERATOR` (UPPER_CASE). Before renaming, the project index is
  asked whether the new name already exists; if it does, the next style is
  tried (`Station_Name` beside an existing `StationName` becomes
  `STATION_NAME`), and with no free name the constant is left alone. Two names
  that close are also reported by the `confusable-identifier` warning.
* A unit with UNSAVED changes is refused ("save the unit first"): a fix
  rewrites the file on disk and then reloads the editor from disk, which would
  otherwise discard the unsaved edits.
* When it changed the file, the buffer is reloaded, the project reindexed and
  the unit re-linted, so the fixed finding drops off on its own.

## What it needs

A plain fixable rule needs no index -- `lint --in` works on a single file.
A NAMING fix (it renames every use) and `unused-unit-in-uses` (the
compiler-verified `uses-fix`) DO need the project index, as described above.
(An index is also needed for the Structure form itself to populate.)

## Example

Dry run first, to see what would change:
```
drag-lint lint --in C:\Projects\MyApp\Unit1.pas --fix
```
Typical output when nothing is fixable:
```
autofix: no fixable findings (of 13 finding(s))
```
Then apply one specific finding:
```
drag-lint lint --in C:\Projects\MyApp\Unit1.pas --fix --fix-line 42 --fix-rule self-assignment --apply
```
