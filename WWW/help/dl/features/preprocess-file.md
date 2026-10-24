---
id: preprocess-file
title: preprocess-file
summary: Diagnostic that prints a file's {$IFDEF}-resolved source to stdout under a given define set
product: DL
group: compiler
order: 90010
since: 0.92.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# preprocess-file

Diagnostic that prints a file's {$IFDEF}-resolved source to stdout under a given define set.

Read this when you need to see what the preprocessor makes of a file. It prints the IFDEF-resolved source under the defines you give it, without running a full compile; it is a diagnostic, not a daily tool.

## How to run it

Full flag list: [preprocess-file in the CLI reference](../cli.md#preprocess-file).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--file` | `PATH` |  |  |
| `--define` | `SYM` |  |  |
| `--numeric` | `K` |  |  |
| `--include-mode` |  |  |  |
| `--no-near-search` |  |  |  |
| `--tolerances` |  |  |  |
| `--include-sites` |  |  |  |

## Details

Diagnostic that prints a file's `{$IFDEF}`-resolved source to stdout under a
given define set. Reach for it to see exactly what the preprocessor
produces for a file, without running a full compile.

### Running it from the CLI
```text
drag-lint preprocess-file --file PATH [--define SYM]... [--numeric K=V]... [--include-mode off|defines-only] [--no-near-search] [--tolerances]
```
`--file PATH` is the source file to preprocess. `--define SYM` may be given
multiple times to set boolean defines. `--numeric K=V` may be given
multiple times to set numeric defines. `--include-mode off|defines-only`
controls `{$I}` include handling. `--no-near-search` and `--tolerances` are
present in the usage line but their behaviour is not documented beyond the
flag name.

This is labeled a "diagnostic" in the CLI banner -- it is a troubleshooting
tool, not a daily driver.

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
No index required -- `preprocess-file` takes no `--db` flag; it operates
directly on the given file and defines.

### Example
Illustrative only:
```text
drag-lint preprocess-file --file C:\Projects\MyApp\CustomerOrder.pas --define DEBUG --numeric APIVERSION=2
```
This would print `CustomerOrder.pas` with `{$IFDEF DEBUG}` blocks resolved
and `APIVERSION` set to 2.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
