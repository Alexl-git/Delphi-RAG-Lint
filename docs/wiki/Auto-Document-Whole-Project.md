# Auto-Document Whole Project

Writes DocInsight documentation into every public declaration a project owns.
Reach for it to bulk-document a project rather than symbol by symbol.

## Running it from the CLI
This runs as a 3-step batch, not a single command:
```
drag-lint index --project <file.dproj> --db <db>
drag-lint document --project <file.dproj> --apply --db <db>
drag-lint index --project <file.dproj> --db <db>
```
Step 1 freshens the index. Step 2 writes documentation into every public
declaration the project owns (`--apply` commits the edits; without it the
command only previews). Step 3 re-indexes: `--apply` shifts line numbers in
the files it edited, and the index has to reflect the new positions before
it is trusted again.

`document --project` also accepts `--stubs`, `--json`, `--no-backup`,
`--include-accessors`, `--reindex` (self-freshens the index after applying,
folding steps 2-3 into one call), and `--document-third-party`.

## Reaching it in the IDE
drag-lint > Generate & Export > Auto-Document Whole Project...

## What it needs
An active project. Unusually for this tool, **no pre-existing index is
required**: step 1 of the batch is an `index` run, and indexing creates the
database if it is missing and re-parses only stale or absent files. So this
action is safe to run on a project that has never been indexed -- it will
simply do the indexing first.

The `--db` flag is optional when you run `document` yourself -- drag-lint
auto-resolves the project's index when it is omitted.

## Example
Illustrative only:
```
drag-lint document --project C:\Projects\MyApp\MyApp.dproj --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would document every public declaration `MyApp.dproj` owns, followed by
a re-index of the same project and DB.
