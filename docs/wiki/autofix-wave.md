# Autofix for fixable rules

`drag-lint lint --fix` repairs the findings of the 131 fixable lint rules (`drag-lint rules --json` marks them `fixable`). The fixers are grouped: expression-level, statement and block, declaration and directive, hygiene, and store-backed ones that consult the index.

## Running it from the CLI
```
drag-lint lint --in <file.pas> --fix                 (dry run: reports the edits, writes nothing)
drag-lint lint --in <file.pas> --fix --apply         (writes the edits)
drag-lint lint --in <file.pas> --fix --json          (per finding: was it applied)
drag-lint lint <folder> --fix --apply                (every scanned .pas / .inc / .dpr)
drag-lint lint-all --db <db> --fix --apply           (the whole project)
```
`--fix-line` with `--fix-rule` narrows the fix to one finding. `--json` reports each finding as applied or not, keyed by the finding itself, so a fix whose edits sit on other lines still counts as applied. Overlapping fixes are deferred to the next run. A store-backed fixer declines without `--db`. `uses-movable-to-implementation` and a few risky fixes are opt-in.

## Reaching it in the IDE
The Structure form's right-click Fix it / Fix all in unit run the same fixers; see Fix-it and Fix-all-in-unit.

## What it needs
Nothing for the file-level fixers; `--db <index.sqlite>` for the store-backed ones.

## When a fix is not offered
A fixer that cannot prove its output compiles declines: the finding stays and no edit is written. Two rules that used to write code dcc 37 rejects now decline these shapes (1.52.3):

- `ifthen-to-if-expression` keeps `if C then X := A else X := B` as written when an arm is an array or set constructor such as `Rows + [NewRow(..)]` (E2010, or internal error F2084 on a long one), and, inside a generic routine, when an arm is a method call and the target is not a built-in type (`Acc := if C then AAnalysis.Boundary else AAnalysis.Bottom` is E2010 there). An `Integer` target in the same routine is still rewritten.
- `nonminimal-bool` keeps `not (A = B)` when an operand is a record, or an alias of one: a record's `=` and `<>` exist only as declared operators, and `TTSNode` declares `Equal` without `NotEqual` (E2015). It is rewritten only when at least one operand is shown to have built-in equality: a literal, or a local of a scalar, string, class, interface or enum type, or an enum value. With `--db` the fixer reads the type from the index; without it, from the file's own declarations.

`nonminimal-bool` also no longer writes a doubled pair: `(not (I = 0)) and B` becomes `(I <> 0) and B`, not `((I <> 0)) and B`.

`pos-for-contains` rewrites `Pos(Sub, S) > 0` / `<> 0` / `= 0` only when `Sub` is a non-empty string or character literal (1.52.3). `Pos('', S) = 0` but `S.Contains('')` is True, so a variable or empty needle is not the same test and stays a report-only finding; before 1.52.3 the fixer rewrote exactly those. The haystack may be a local or parameter declared `string`, a member declared `string` (read from the index, so `--db` is needed), or a call of `LowerCase`, `UpperCase`, `Trim`, `TrimLeft` or `TrimRight`; any other haystack, such as `Copy(..)`, is reported and not rewritten.
`local-field-prefix` renames a local such as `FTemp` to `Temp` only when the new name is safe (1.52.3). It declines, and prints `local-field-prefix: declined <file>:<line> "FIn" -> "In" -- <why>`, when the new name is a reserved word (`FIn` -> `In` would not compile), when it is already a parameter or local of the same routine or of an enclosing routine, or when it is a member of the method's class or of an ancestor (TObject included): there the new local would hide that name and a later use in the body would silently bind to the local. Before 1.52.3 the prefix was stripped without these checks.

## One pass for packed lines
`multiple-statements-per-line` lays out the whole flagged line in one run (1.52.3): every statement gets its own line, and `if C then begin A; B; end;` becomes `if C then` / `begin` / `A;` / `B;` / `end;` with the block indented one step. `else begin` and `end else begin` put `else` and `begin` on their own lines. Before 1.52.3 the fixer broke the line once, so a line of n statements needed n-1 runs and `B; end;` was left behind. It declines a line it cannot lay out without guessing: a compiler directive, a statement that continues on the next line, or the keywords `case`, `try`, `repeat`, `until`, `except`, `finally`, `asm` or `record`.
