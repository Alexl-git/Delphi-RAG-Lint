---
id: bench-context
title: bench-context
summary: Benchmarks the context command by building context bundles for a sample of symbols against a database
product: DL
group: maintenance
order: 120003
since: 0.18.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# bench-context

Benchmarks the context command by building context bundles for a sample of symbols against a database.

Read this when you want to measure what building context bundles costs. bench-context runs the context command over a sample of symbols in a database (--n sets the sample size); it is a benchmark, not a way to inspect one symbol.

## How to run it

Full flag list: [bench-context in the CLI reference](../cli.md#bench-context).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--n` | `N` |  |  |

## Details

Benchmarks the `context` command by building context bundles for a sample
of symbols against a database. Reach for it to measure the cost of
generating context bundles, not to inspect any single symbol.

### Running it from the CLI
```text
drag-lint bench-context [--db <file.sqlite>] [--n N]
```
`--n N` sets how many symbols the benchmark samples; `--db` selects the
index. Neither flag's default is documented in the usage line.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint bench-context --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --n 20
```
This would build context bundles for 20 sampled symbols and report
benchmark results.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
