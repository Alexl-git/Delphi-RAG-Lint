# rules

Lists the full lint rule catalog: every rule drag-lint can check, with its
category, and its default enabled/fixable status. Reach for it to see what a
lint run can find, or to filter by category.

The catalog currently holds 174 rules -- 149 enabled by default, 22 marked
fixable -- across 16 categories. Of the 173, 119 are built-in and 54 are
external `.scm` rule files.

## Running it from the CLI

```
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```

## Reaching it in the IDE

CLI+internal: the IDE's Options dialog loads this catalog by running
`rules --json` internally, from `DragLint.Plugin.LintOptionsFrame.pas:88`.
There is also a menu item that surfaces the catalog for one specific
project: right-click a project in the Project Manager and choose
"drag-lint: Project Rules..." -- see
[drag-lint: Project Rules...](drag-lint-Project-Rules).

## What it needs

No index required -- `rules` reads the static rule catalog, not any
project's indexed data.

## Example

Illustrative:

```
drag-lint rules --category naming --json
```

This would print the catalog of naming-category rules as JSON.
