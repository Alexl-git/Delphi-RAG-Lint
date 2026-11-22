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
