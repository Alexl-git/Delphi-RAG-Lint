---
id: extract-method
title: extract-method
summary: Pulls a run of statements out of a routine into a new method
product: DL
group: refactoring
order: 50005
since: 0.85.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# extract-method

Pulls a run of statements out of a routine into a new method.

Read this when a routine is too long and you want a run of statements moved into a new method without doing it by hand. Give the file, the first and last line and the new name; without --apply it is a dry run (exit 0, nothing written) and --json prints the edit set without writing. Exit 0 on a preview or an applied change, 1 when no edit is computed, 2 when the selection is refused or the arguments are incomplete; every refusal reason goes to stderr.

## How to run it

Full flag list: [extract-method in the CLI reference](../cli.md#extract-method).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `<F>` |  |  |
| `--from-line` | `<L1>` |  |  |
| `--to-line` | `<L2>` |  |  |
| `--name` | `<N>` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--no-backup` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Extract Method (selection)... (Ctrl+Alt+M)**
   1. Select the statements to extract in the editor
   2. drag-lint > Extract Method (selection)... (Ctrl+Alt+M)
   3. Enter the new method name, review the dry-run preview, then apply; the unit reloads from disk

## Details

Pulls a run of statements out of a routine into a new method. Reach for it
when refactoring a long routine and you want the mechanical extraction done
for you rather than by hand.

### Running it from the CLI

```text
drag-lint extract-method --in <F> --from-line <L1> --to-line <L2> --name <N> [--json|--apply|--no-backup]
```

`--in` is the source file; `--from-line`/`--to-line` bound the statement
run to extract; `--name` is the new method's name. The usage line lists
`--apply` as a flag; whether omitting it produces a dry run is not
documented in the help text for this verb.

### What it needs

No index required -- the usage line has no `--db` flag; `extract-method`
operates directly on the given file's line range.

### Example

Illustrative:

```text
drag-lint extract-method --in C:\Projects\MyApp\Unit1.pas --from-line 120 --to-line 135 --name ValidateInput --apply
```

This would pull lines 120-135 of `Unit1.pas` into a new method named
`ValidateInput`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
