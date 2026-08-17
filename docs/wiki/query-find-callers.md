# query find-callers

Lists callers of a routine by name, with an option to restrict results to
precise, resolved callers. Reach for it to see who calls a given routine
across the index.

## Running it from the CLI

```
drag-lint query find-callers --name <callee-name> [--context N] [--resolved] [--db ...] [--json]
```

`--name` is the callee to look up. `--context N` adds N lines of
surrounding context. `--resolved` restricts results to precise callers via
resolved `call_edges`, grouped by target as certain or ambiguous.

## Reaching it in the IDE

Not reachable through a main-menu item. The feature map's internal call
site is `DragLint.Plugin.CodeLensCache.pas:466` -- the plugin's CodeLens
cache, which powers inline caller-count annotations in the editor. Beyond
that call site, no menu path or right-click item is documented for this
verb.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint query find-callers --name TMyClass.DoWork --resolved --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would list every resolved caller of `TMyClass.DoWork`, grouped as
certain or ambiguous.
