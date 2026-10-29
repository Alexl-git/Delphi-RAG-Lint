---
id: taint-analysis
title: Taint analysis (SQL, command, path)
summary: taint-sql-injection, taint-command-injection and taint-path-traversal follow index data_flows facts from a source to a sink
product: DL
group: linting
order: 30024
since: 1.37.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Taint analysis (SQL, command, path)

taint-sql-injection, taint-command-injection and taint-path-traversal follow index data_flows facts from a source to a sink.

Read this when you want to find tainted values reaching a SQL, command or file-path sink across routines and units. The rules run in lint-all and in lint with a store; the catalogues of sources, sinks and propagators are editable JSON.

## How to run it

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Three lint rules follow a value from a catalogued source to a dangerous sink across routines and units: `taint-sql-injection` (CWE-89), `taint-command-injection` (CWE-78) and `taint-path-traversal` (CWE-22). They walk the `data_flows` facts that the indexer writes (extractor 1.26.0-alpha), so they need a project index.

### Running it from the CLI
```text
drag-lint lint-all --db <db> --rule taint-sql-injection
drag-lint lint <file.pas> --db <db> --rule taint-path-traversal
```
`lint-all` runs all three by default. `lint <file>` runs them only with `--db`. A run that disables every taint rule skips the taint stage. Findings carry the path from source to sink.

### Catalogues
The sources, sinks, propagators and sanitizers are JSON files shipped in `rules\`: `taint-sources.json`, `taint-sinks.json`, `taint-propagators.json`. The `taint` object of `drag-lint-lint.json` extends them (`sources`, `sinks`, `propagators`, `sanitizers`, `disable`, `max_depth`, `lib_depth`, `max_rounds`, `follow_ambiguous`, `weak_receiver_regex`, `weak_severity_drop`, `max_paths_per_sink`, `second_order`). A source row can name `categories` and `trusted_args`: the command line, a dropped file and a file dialog are not path-traversal sources, and `ParamStr(0)` is the module path, not user input.

### What it needs
An index of the project (`drag-lint index --project <file.dproj>`) with the 1.37.0 extractor, so the `data_flows` table is filled.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
