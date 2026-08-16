> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21). FIXED.** An if WITH an else parses as `exprIf`; there is no `ifElse` node in this grammar, so `MaxNest` scored the else form ZERO and its chain-continuation branch was dead code keyed on a phantom node type. One trailing else cost a whole level -- six-deep measured five and, against max 5, said nothing. Now counts `exprIf` and locates the else branch by the child after `kElse` (exprIf children are positional, so `ChildByField('else')` returned null). Verified 6/6/7 across three arms, and an 8-long `else if` chain -- well past the threshold -- stays silent, so the chain guard is load-bearing. Guarded by `tests\autotest\run_deep_nesting_else_forms.ps1`. Same family as the kAt/kVar/exprIf 'keywords are NAMED nodes' bugs.

# INBOX: deep-nesting reports NOTHING when a chain ends in `else <procedure call>;`

Found 2026-08-11 while fixing the else-if-chain nesting count. Separate defect,
same rule. Not fixed.

## Repro

Two files differing only in the body of the FINAL `else`:

```pascal
procedure Dispatch(const A: string);
begin
  if A = 'one' then
    WriteLn(1)
  else if A = 'two' then
    WriteLn(2)
  ... (8 arms) ...
  else
    WriteLn(0);          // <-- bare procedure CALL
end;
```

| trailing else body | deep-nesting (pre-fix engine, threshold 5) |
|---|---|
| `WriteLn(0);` (call) | **no finding at all** |
| `B := 0;` (assignment) | `structures 8 deep` |
| trailing else removed | `structures 8 deep` |

So the whole routine goes unanalysed for this rule when the last else holds a
bare call. It is not a threshold effect -- 8 > 5 either way.

## Why it matters

It is a SILENT under-report, and the shape is ordinary: an if/else-if ladder
ending in `else ShowError(...)` or `else raise ...` is idiomatic. The rule simply
says nothing, which reads identically to "this routine is fine".

It also cost real time: the shape was picked by accident for a test fixture while
hunting the else-if counting bug, and the resulting "the bug does not reproduce"
signal nearly led to the counting bug being dismissed as already-fixed. A rule
that can silently skip a routine will do that again.

## Where to look

`TAstChecker.CheckProcMetrics` -> `MaxNest` / `CheckProc` in
`src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`. `CheckProc` only computes
`Nest` when `ADefProc.ChildByField('body')` is non-null, so the first thing to
check is whether the trailing `else <call>` makes the routine's `body` field null
or makes the walk see an ERROR node -- other rules still fired on the same file
(`writeln-in-source` reported every arm, including the trailing one), so the file
does parse; something about THIS traversal stops.

Worth checking whether the same shape also suppresses `too-many-parameters`,
`too-many-locals` and `method-too-long`, which are emitted from the same
`CheckProc` and would be lost together.

## Status after the else-if fix (commit 050b10e)

Unchanged -- that commit altered how depth is counted, not whether the routine is
analysed. The chains in the table above now report clean for the RIGHT reason,
which makes this defect harder to notice, not easier: both columns now say
nothing. Reproduce it against a genuinely nested routine ending in
`else <call>;` instead.
