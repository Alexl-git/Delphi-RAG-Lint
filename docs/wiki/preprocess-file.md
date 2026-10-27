# preprocess-file

Diagnostic that prints a file's `{$IFDEF}`-resolved source to stdout under a
given define set. Reach for it to see exactly what the preprocessor
produces for a file, without running a full compile.

## Running it from the CLI
```
drag-lint preprocess-file --in PATH [--define SYM]... [--numeric K=V]... [--include-mode off|defines-only] [--no-near-search] [--tolerances] [--include-sites]
```
`--in PATH` is the source file to preprocess. `--define SYM` may be given
multiple times to set boolean defines. `--numeric K=V` may be given
multiple times to set numeric defines. `--include-mode off|defines-only`
controls `{$I}` include handling. `--include-sites` prints the active include
sites instead of the source: one tab-separated line per resolved `{$I}` site
(`site`, depth, line, column, resolved byte count, MD5 of the resolved bytes,
absolute path). `--no-near-search` and `--tolerances` are
present in the usage line but their behaviour is not documented beyond the
flag name. The verb has no `--json` form.

This is labeled a "diagnostic" in the CLI banner -- it is a troubleshooting
tool, not a daily driver.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
No index required -- `preprocess-file` takes no `--db` flag; it operates
directly on the given file and defines.

## Example
Illustrative only:
```
drag-lint preprocess-file --in C:\Projects\MyApp\CustomerOrder.pas --define DEBUG --numeric APIVERSION=2
```
This would print `CustomerOrder.pas` with `{$IFDEF DEBUG}` blocks resolved
and `APIVERSION` set to 2.
