---
id: syntax-count
title: syntax-count
summary: "Counts modern syntax in the parse of every unit, uncapped: Delphi 13 if-expressions, is not, not in; inline var/const; anonymous methods; multiline strings"
product: DL
group: search-navigation
order: 20033
since: 1.42.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# syntax-count

Counts modern syntax in the parse of every unit, uncapped: Delphi 13 if-expressions, is not, not in; inline var/const; anonymous methods; multiline strings.

Read this when you want to know how much of a codebase uses a given syntax feature -- for example how many Delphi 13 if-expressions or is-not tests a downgrade would have to rewrite. It parses each unit at the call and counts shapes in the parse, so strings and comments never count and nothing is capped.

## How to run it

Full flag list: [syntax-count in the CLI reference](../cli.md#syntax-count).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--in` | `<path>` |  |  |
| `--feature` | `<a,b>\|all` |  |  |
| `--per-file` |  |  |  |
| `--hits` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Counts how often a codebase uses a modern syntax feature. Each unit is parsed
at the call and the count is of SHAPES in the parse, so a string or a comment
that happens to say "is not" never counts, and nothing is capped (`query --text`
covers strings and comments only and stops at 200 hits).

| feature | what counts | first Delphi |
|---|---|---|
| `if-expr` | `X := if C then A else B` (each nested one too; `IfThen()` does not) | 13 |
| `is-not` | `X is not T` (`not (X is T)` does not) | 13 |
| `not-in` | `a not in S` (`not (a in S)` does not) | 13 |
| `inline-var` | block-level `var x := ...`, `var x: T;`, `for var i` (a `var` section does not) | 10.3 |
| `inline-const` | block-level `const k = ...` | 10.3 |
| `anon-method` | `function ... begin ... end` / `procedure ... begin ... end` as a value | 2009 |
| `multiline-string` | a `'''` string spanning lines (`''''` does not) | 12 |

### Running it from the CLI

```text
drag-lint syntax-count (--db <file.sqlite> | --in <path>...) [--feature <a,b>|all] [--per-file] [--hits] [--json]
```

* `--db` takes every `.pas` / `.dpr` / `.dpk` / `.inc` file of that index. The
  index is opened read-only and supplies only the file list; nothing is written.
* `--in` adds one path (repeatable); with no `--db` only those files count.
* `--feature if-expr,is-not` counts only those; the default is all.
* `--per-file` lists each file with at least one occurrence and its counts;
  `--hits` lists `path:line:col  feature` per occurrence.
* `--json` prints one object: `features[]`, `files_scanned`, `files_unreadable`,
  `files_with_parse_errors`, `totals{feature: n}`, and `files[]` / `hits[]` when
  asked.

The count is of the text as written: `$IFDEF` branches are not evaluated, so
code in every branch counts. A file that parses with errors is still counted
(the shapes outside the error survive) and tallied in `files_with_parse_errors`.

Exit codes: 0 = counted (zero occurrences included); 2 = no `--db` / `--in`,
an unknown `--feature` name, or an index that is missing or has an old schema;
3 = an unknown flag (`error[unknown-flag]` on stderr).

### Examples

```text
drag-lint syntax-count --db <db> --feature if-expr,is-not
drag-lint syntax-count --db <db> --feature is-not --hits
drag-lint syntax-count --in Unit1.pas --json
```

Typical use: before a downgrade to an older compiler, see how many Delphi 13
constructs the `compat` fixes would have to rewrite.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
