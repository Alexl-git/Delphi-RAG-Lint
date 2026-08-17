# workspace add

Registers a project file into a `.drag-lint-workspace.json` workspace
config, so multi-project workspace commands know about it. Reach for it when
adding a new project to a workspace that `workspace index` / `workspace
status` will operate over.

## Running it from the CLI

```
drag-lint workspace add <projfile> [--config <.drag-lint-workspace.json>]
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

No index required -- `workspace add` only edits the workspace config file;
it does not read or write an index database.

## Example

Illustrative:

```
drag-lint workspace add MyProject.dproj
```

This would add `MyProject.dproj` to the workspace config in the current
directory.
