# Fix all in project

Applies autofixes for every fixable finding across the whole project,
starting from the Structure form. Reach for it when you want a
project-wide sweep of autofixes in one action instead of fixing unit by
unit.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

**The Structure form's right-click menu is the only place autofix
("Fix it", "Fix all in unit", "Fix all in project") is reachable in the
IDE** -- there is no main drag-lint menu item for it.

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a tree node and choose "Fix all in project".

## Running it from the CLI

The menu item runs `lint-all` with the autofix flags across the whole
indexed project:

```
drag-lint lint-all --db <project.sqlite> --fix --apply
```

Without `--apply` the command is a DRY RUN. Dry-run first -- this one can
rewrite many files at once.

Known limitation, from the plugin source: after a project-wide fix only the
CURRENT file's editor buffer is reloaded. Other edited files stay stale in
their open editor buffers until you re-open them.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the project's index
when it is omitted. But `lint-all` does read an index, so one must exist.
The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`;
run `drag-lint resolve-dbs --project <X.dproj>` if you are unsure which
one.

## Example

Dry run:
```
drag-lint lint-all --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --fix
```
Apply for real:
```
drag-lint lint-all --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --fix --apply
```
