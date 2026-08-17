# drag-lint: Project Rules...

Shows the catalog of lint rules in the context of a specific project. Reach
for it when you want to see which rules exist (and their categories)
starting from the Project Manager rather than the drag-lint main menu.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Project
Manager (right-click a project)".

Unlike the other IDE-context rows on this wiki, this one is NOT reached
through the Structure form. To reach it: in RAD Studio's Project Manager,
right-click a project and choose "drag-lint: Project Rules...".

## Running it from the CLI

The feature map lists the underlying verb as `rules`. From the usage
banner:

```
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```

Lists every lint rule (catalog).

## What it needs

No index needed, per the feature map's Index column.

## Example

Illustrative:

```
drag-lint rules --category naming --json
```

This would print the catalog of naming-category rules as JSON.
