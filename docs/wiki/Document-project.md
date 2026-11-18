# Document project

Generates or repairs managed DocInsight comments for every public
declaration the project owns, starting from a Structure-tree node's
project. Reach for it when a whole project needs documentation coverage,
not just one unit or symbol.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Document project".

## Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the whole-project form:

```
drag-lint document --project <p.dpr|.dproj> [--stubs|--apply|--json|--no-backup|--include-accessors|--reindex|--document-third-party] [--db PATH]
```

Documents every public declaration the project owns (scope: the compile
closure restricted to the project's own roots). `--reindex` self-freshens
the index afterward so hover/LSP are correct immediately.

When a file the run reads facts from changed since it was indexed (for
example another project's `--apply` rewrote a shared unit), the line
ranges in the index cover other text and the facts would cite the wrong
routines. A dry run then prints a `doc: WARN` on stderr naming those files
and still shows the preview (`--json` carries `"staleFactSources": N`);
`--apply` refuses and writes nothing until the index is fresh. Reindex, or
use `--apply --reindex`, which reindexes before it documents.
`document-all` behaves the same way. Under `--json`, stdout is one JSON
document even when the run reindexes in-process (`--reindex`, the
stale-anchor retry, the tamper rescan).

## What it needs

Optional, per the feature map's Index column.

## Example

Illustrative:

```
drag-lint document --project C:\Projects\MyApp\MyApp.dproj --apply --reindex --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write managed DocInsight comments across the whole project and
refresh the index afterward.
