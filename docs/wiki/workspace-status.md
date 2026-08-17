# workspace status

Reports the status of every project registered in a
`.drag-lint-workspace.json` workspace config. Reach for it to see, at a
glance, which workspace projects are indexed, stale, or missing.

## Running it from the CLI

```
drag-lint workspace status [--config <.drag-lint-workspace.json>]
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

No index required to invoke the command itself -- `workspace status` reads
the workspace config and reports on each registered project's index state;
it does not take a `--db` flag.

## Example

Illustrative:

```
drag-lint workspace status
```

This would print the index status of every project registered in the
workspace config found in the current directory.
