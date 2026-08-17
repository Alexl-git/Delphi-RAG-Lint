# info

Prints engine self-info: version, build date, license (MIT), tree-sitter
details, and capabilities. Reach for it to check which build of drag-lint
you are running, or to script a version check.

## Running it from the CLI

```
drag-lint info [--json]
```

Read-only.

## Reaching it in the IDE

CLI+internal: the plugin calls this internally from
`DragLint.Plugin.About.pas:217` (the About dialog). There is no menu item
for it beyond that internal call site.

## What it needs

No index required -- `info` reports on the engine binary itself, not on any
indexed project.

## Example

Illustrative:

```
drag-lint info --json
```

This would print the engine's version, build date, and capabilities as JSON.
