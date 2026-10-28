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

## What you see while it runs

* The item is ENABLED only when at least one finding in the unit has a
  registered fix, and its caption says how many: "Fix all in unit (3)". It is
  offered from the Diagnostics root and from any Diagnostics row.
* The seven NAMING fixes (`const-casing`, `type-name-prefix`,
  `method-pascalcase`, `local-var-casing`, `field-name-prefix`,
  `param-name-prefix`, `local-field-prefix`) ARE counted when the project has
  an index (they rename a symbol everywhere it is used, so they need it). With
  any naming finding in the unit, Fix all in unit runs a PREVIEW first and
  ALWAYS asks before renaming: `Rename N identifier(s) in <project>?` for a
  unit one project compiles, or the multi-project confirmation listing every
  owning project for a shared unit (see
  [Multi-Project-Rename](Multi-Project-Rename)). Both default to No, and No
  writes nothing. Renames that cannot be done safely are dropped and listed;
  the rest are applied.
* It runs in the BACKGROUND on the drag-lint job queue -- the IDE stays
  usable, and the dock's status strip shows the job while it works.
* When it finishes, the engine's own summary is shown ON THE DIAGNOSTICS ROOT
  ROW of the panel (with the time), in the status strip and in the IDE
  Messages pane, e.g.
  `drag-lint: Fix all in unit -- Unit1.pas: applied 2 edit(s) across 1 file(s) (.bak written)`
  or `... no fixable findings (of 13 finding(s))`.
* When edits were applied, the editor buffer is reloaded from disk, the
  project is reindexed and the unit is re-linted, so the fixed findings
  drop off the panel on their own.

* A unit with UNSAVED changes is refused ("save the unit first"): the fix
  rewrites the file on disk and reloads the editor from it.

"Fix it" on a single finding works the same way. `unused-unit-in-uses`
findings are not counted here -- they are fixed one at a time by
[Fix it](Fix-it), which compiles to decide between removing and moving.

## Running it from the CLI

The menu item runs `lint` with the autofix flags, unscoped -- no
`--fix-line`/`--fix-rule`, so every fixable finding in the file is applied:

```
drag-lint lint --in <path.pas> --fix --apply [--db <project.sqlite>]
```

The IDE passes the project's `--db`: the naming fixes need the index to find
every use. Every fix is on by default (since 1.37.0). With a naming finding in
the unit it also passes `--fix-naming` (a no-op the engine still accepts, and
the reason it prints `rename-local: <N>`) -- on the preview AND on the apply;
only the apply waits for your confirm:

```
drag-lint lint --in <path.pas> --fix --fix-naming --db <project.sqlite>           (preview)
drag-lint lint --in <path.pas> --fix --fix-naming --apply --db <project.sqlite>   (after Yes)
```

To withhold a rule, list it in `"autofix_off": [...]` in `drag-lint-lint.json`
(the retired `"autofix": [...]` key is ignored). A rename the engine cannot
prove complete is skipped and counted (`skipped (dfm-referenced): N`,
`skipped (with-block): N`) -- nothing is written for it.

Without `--apply` the command is a DRY RUN: it reports what it would fix
and writes no source file and no index. With `--apply`, naming fixes may
first reindex stale owning project indexes. Always dry-run first.

Only rules marked fixable are applied; 110 of the 289 rules are fixable
(`drag-lint rules --json` reports a `fixable` field per rule).

## What it needs

No index required -- `lint --in` works on a single file.

## Example

Dry run:
```
drag-lint lint --in C:\Projects\MyApp\Unit1.pas --fix
```
Typical output when nothing is fixable:
```
autofix: no fixable findings (of 13 finding(s))
```
Apply for real:
```
drag-lint lint --in C:\Projects\MyApp\Unit1.pas --fix --apply
```
