# Complexity counts the if-expression

Since 1.52 (GA-1, owner ruling 2026-11-18) the Delphi 13 conditional expression
`X := if C then A else B` is a decision point, the same as an `if` statement, in:

* `cyclomatic-complexity`: +1 per if-expression;
* `cognitive-complexity`: 1 + its nesting depth; an `else if` arm of an if-expression is the hybrid
  +1 (no nesting), exactly like an `else if` statement ladder;
* the auto-document `Complexity:` fact, which reads the same formula as `cyclomatic-complexity`.

```
drag-lint lint <file.pas> --rule cyclomatic-complexity,cognitive-complexity
drag-lint lint-all --db <project.sqlite> --rule cognitive-complexity
```

| Routine body | cyclomatic before / after | cognitive before / after |
|---|---|---|
| `Result := (if A then 1 else 2) + (if B then 3 else 4);` | 1 / 3 | 0 / 2 |
| `Result := if A then 1 else if B then 2 else 3;` | 1 / 3 | 0 / 2 |
| `if A then Result := if B then 1 else 2 else Result := 0;` | 2 / 3 | 1 / 3 |

`deep-nesting` is unchanged: an if-expression has no statement body and is not a nesting level (1.51.1).

## What this moves

A routine that uses if-expressions reports a higher number, so a routine near its threshold can start
to report, and generated DocInsight `Complexity:` lines change on the next autodoc run. Both rules'
measure-algorithm version went from 1 to 2 (`DRagLint.Lint.MarkerHash`): a `dl:ok` stamped by 1.51.1 or
later (hash v2) on an unchanged routine is re-measured and stays suppressed. A LEGACY marker (stamped
under the 1.51.0 hash, header + metric only) cannot tell a counting change from an edit, so on a routine
whose score moved it goes `review-marker-stale` and the finding reports again: re-review, then
`drag-lint allow --fix-line <line> --fix-rule <rule>` re-stamps it under v2. Measured on this repo's
`src` (partial scan): 9 such routines.

Guard: `tests\autotest\run_v152_BK-OWNGATED.ps1`.
