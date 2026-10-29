# Overview (first-turn project summary)

One bounded call that answers what an agent asks first: how fresh is the index, how
big is the project, how is it layered, what is referenced most, where does it start,
which forms exist. Six sections in a fixed order, every one capped.

## Running it from the CLI
```
drag-lint overview --db <file.sqlite> [--max-rows N] [--json]
```
`--max-rows` caps the rows of every section (default 20). A section that was cut
says so: `-- 1578 omitted by cap 20; rerun with --max-rows 1598`. With `--json` the
top-level keys are `freshness`, `counts`, `layers`, `fanin`, `entrypoints`, `forms`,
and each holds `total`, `cap`, `omitted` and `rows`. The exit code does not change
when a section is capped.

## The sections
* `freshness` -- project tag, scan type, schema version, when the index was built, file and symbol counts.
* `counts` -- symbols per kind, largest first.
* `layers` -- units by dependency layer: layer 0 uses no other project unit, layer n uses only lower layers. A unit in or above a circular `uses` group is listed in the final `cyclic` row. Each row shows the first 8 unit names and `+N more`.
* `fanin` -- the most-referenced names (the same aggregation as `top`).
* `entrypoints` -- program files, `initialization` / `finalization` sections and `.dfm` event handlers.
* `forms` -- symbols of kind `form`.

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure. Reads only; never writes the DB.

## Example
Illustrative only:
```
drag-lint overview --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --max-rows 10
```
This would print the six sections with at most 10 rows each.
