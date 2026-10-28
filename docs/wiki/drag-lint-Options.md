# drag-lint Options

The plugin's settings dialog for drag-lint: lets you browse and toggle the
lint rule catalog. Reach for it to see which rules exist, which are on by
default, and which have an auto-fix, and to change what is enabled.

## Running it from the CLI
The dialog itself is in-process (no CLI shell-out), but it loads its rule
catalog by running:
```
drag-lint rules --json
```
The equivalent standalone command, with the same catalog:
```
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```
As loaded by this dialog, the catalog has 289 rules, 110 of them fixable,
245 on by default, across 18 categories.

## Reaching it in the IDE
drag-lint > drag-lint Options...

## What it needs
Not documented as needing an index -- the feature map marks this row's
Index column "n/a" and its Mechanism "in-process". It needs the rule
catalog files that `rules --json` reads; it does not need a project
database.

## Example
Illustrative only: opening drag-lint > drag-lint Options... shows the
full 289-rule catalog, grouped by its 18 categories, with a toggle per
rule and a marker for which of the 110 fixable rules have an auto-fix.
