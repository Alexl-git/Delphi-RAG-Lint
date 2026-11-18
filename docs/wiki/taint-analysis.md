# Taint analysis

Three lint rules follow a value from a catalogued source to a dangerous sink across routines and units: `taint-sql-injection` (CWE-89), `taint-command-injection` (CWE-78) and `taint-path-traversal` (CWE-22). They walk the `data_flows` facts that the indexer writes (extractor 1.26.0-alpha), so they need a project index.

## Running it from the CLI
```
drag-lint lint-all --db <db> --rule taint-sql-injection
drag-lint lint <file.pas> --db <db> --rule taint-path-traversal
```
`lint-all` runs all three by default. `lint <file>` runs them only with `--db`. A run that disables every taint rule skips the taint stage. Findings carry the path from source to sink.

Since 1.52 each rule reports **one finding per sink site** (file, line, column, rule), however many sources or paths reach it. The message names the best path (certain before weak, then the shortest) and, when more than one distinct path reaches the sink, ends with a summary such as `(4 sources, 6 paths)`. Nothing is dropped: in `--format json` the `path` key holds that best path (source first, sink last) and `paths` lists every distinct path, best first. A `dl:ok` marker on the sink line reviews the whole site, as it did each per-path finding before (the marker hash is unchanged). `max_paths_per_sink` is still accepted in the config and ignored.

## Catalogues
The sources, sinks, propagators and sanitizers are JSON files shipped in `rules\`: `taint-sources.json`, `taint-sinks.json`, `taint-propagators.json`. The `taint` object of `drag-lint-lint.json` extends them (`sources`, `sinks`, `propagators`, `sanitizers`, `disable`, `max_depth`, `lib_depth`, `max_rounds`, `follow_ambiguous`, `weak_receiver_regex`, `weak_severity_drop`, `max_paths_per_sink`, `second_order`). A source row can name `categories` and `trusted_args`: the command line, a dropped file and a file dialog are not path-traversal sources, and `ParamStr(0)` is the module path, not user input.

## Reaching it in the IDE
No dedicated IDE surface. The findings appear with the other lint findings of the project.

## What it needs
An index of the project (`drag-lint index --project <file.dproj>`) with the 1.37.0 extractor, so the `data_flows` table is filled.
