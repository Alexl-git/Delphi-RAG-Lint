> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED (cb44bab): a dynamic-array append is not string concatenation. Guarded by tests/autotest/run_concat_in_loop_precision.ps1, green in the full battery.
>
> Original note follows unchanged.

# `concat-in-loop` is still type-blind for a variable right operand

Filed 2026-08-13. The `.scm` query was tightened the same day (operator must be
`kAdd`; a right operand starting with a digit or `$` is excluded), which removed
the whole `i := i + 1` / `k := k + 2` increment class. Guarded by
`tests\autotest\run_concat_in_loop_precision.ps1`.

**What remains:** a variable right operand is indistinguishable in the tree.

    i := i + Count;    { integer arithmetic -- reported }
    S := S + Word;     { string concatenation -- correctly reported }

Both are `(assignment lhs: (identifier) rhs: (exprBinary lhs: (identifier)
operator: (kAdd) rhs: (identifier)))`. Nothing in the syntax separates them; only
a type does.

## The fix has a precedent in this repo

`string-equality-comparison` had exactly this shape -- a type-blind `.scm` rule
that a precise, store-backed built-in later superseded. The wiring is already in
`DoLintAll` (search `string-equality-comparison` in `DRagLint.CLI.pas`): when a
store is present the `.scm` findings for that id are DROPPED and the built-in's
type-exact findings are used instead. The `.scm` rule stays as the no-index
fallback.

So the work is:

1. A built-in check that resolves the declared type of the assignment's LHS via
   the store and reports only when it is a string type (`string`,
   `AnsiString`, `WideString`, `UnicodeString`, `ShortString`, and their
   aliases -- `TCaption` is the one that bites).
2. Add its id to the drop-list in `DoLintAll` beside
   `string-equality-comparison`, so the two never double-report.
3. Flip the last assertion in `run_concat_in_loop_precision.ps1`, which was
   written to assert the CURRENT limitation on purpose, so this change shows up
   as a deliberate behaviour flip rather than a silent one.

## Why it is worth doing

Counts on 2026-08-13, after the `.scm` tightening:

| Project | `concat-in-loop` |
|---|---|
| drag-lint's own `src\cli` | 141 (before tightening) |
| DataCopy | 15 |
| YADF | 15 (before tightening) |

The remaining false-positive rate is unmeasured -- sample ~12 before believing
any of those numbers, which is how the increment class was found in the first
place (2 of 6 sampled on YADF).

## A caution about the loop constraint

`require_ancestor: ["for", "while", "repeat"]` lives in the sidecar `.json`
because a tree-sitter pattern cannot ask about ancestors. Anything reimplemented
as a built-in must keep that constraint explicitly -- without it the rule fired
328 times on drag-lint's own source, nearly all of them on code that runs once
and is therefore quadratic in nothing.
