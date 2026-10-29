---
id: run-ast-checks
title: Run AST Checks
summary: Runs drag-lint's AST-level checks against a file
product: DL
group: linting
order: 30021
since: 0.31.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Run AST Checks

Runs drag-lint's AST-level checks against a file.

Read this when you want to validate a single file against drag-lint AST-level checks: you get the issues found in the parse tree, as text or JSON.

## How to run it

Full flag list: [check-ast in the CLI reference](../cli.md#check-ast).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `PATH` |  |  |
| `--rule` | `<id>` |  |  |
| `--format` |  |  |  |

## Where to click

* drag-lint About window, button **Run AST Checks**
   1. Open the file in the editor
   2. Open the About window (drag-lint > About) and click the Run AST Checks button
   3. From a shell: `drag-lint check-ast <file> [--profile <name>] [--db PATH] [--rule <id>] [--format text|json]`

## Details

Runs drag-lint's AST-level checks against a file. Reach for it to validate
a file's parse tree and catch AST-detectable issues directly.

### Running it from the CLI
```text
drag-lint check-ast <file> [--db PATH] [--format text|json]
```
`<file>` is the file to check; `--db` is an index database; `--format`
selects `text` or `json` output.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint check-ast C:\Projects\MyApp\Unit1.pas --format json
```
This would run AST checks on `Unit1.pas` and print the results as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
