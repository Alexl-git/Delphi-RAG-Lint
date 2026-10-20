# Rebuild Index for This Project

Walks a project's `.dproj` compile closure and (re)builds its index. Reach
for it after adding or moving units, or when hover, Find Usages, or lint
results feel stale.

## Running it from the CLI
```
drag-lint index --project <file.dproj> [--db <file.sqlite>] [--dry-run] [--watch [--interval N]]
```
`--dry-run` previews without writing; `--watch [--interval N]` keeps
re-indexing on an interval. Mode is chosen per run: `--recompile` (default)
updates the index in place; `--rebuild` first empties it of source, then
walks (implies `--force-reparse`). `--force-reparse` (alias `--no-skip`)
re-parses every walked file even when unchanged. `--prune` forces the
delete-sweep for a single-file walk; `--no-prune` computes and reports what
would be removed without deleting anything.

## Reaching it in the IDE
drag-lint > Index & Maintenance > Rebuild Index for This Project

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint index --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would re-index `MyApp`'s compile closure in place (default recompile
mode).
