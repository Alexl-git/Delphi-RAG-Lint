# bench-context

Benchmarks the `context` command by building context bundles for a sample
of symbols against a database. Reach for it to measure the cost of
generating context bundles, not to inspect any single symbol.

## Running it from the CLI
```
drag-lint bench-context [--db <file.sqlite>] [--n N]
```
`--n N` sets how many symbols the benchmark samples; `--db` selects the
index. Neither flag's default is documented in the usage line.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint bench-context --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --n 20
```
This would build context bundles for 20 sampled symbols and report
benchmark results.
