> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21). REFUTED by fixture.** The note's claim is that a QUALIFIED lhs is not flagged. Measured: `Self.FFoo := TStringList.Create;` as the first statement inside a try..finally IS reported -- `uThree.pas:25:5 [warning] create-inside-try`. This matches the note's own `Status: RESOLVED (2026-08-11, Fix 4)`; only the INBOX index entry was stale.

# create-inside-try: qualified lhs (Self.Field := ...) is never flagged, even when the finally provably frees it

**Status:** RESOLVED (2026-08-11, final whole-branch review, Fix 4). The narrowed
`Self.X`-only fix sketched below was NOT what shipped -- the review that reopened
this also found the gate drops INDEXED targets (`FList[0] := TFoo.Create`) and
general MULTI-LEVEL ones (`A.B.C := TFoo.Create`), not just `Self.<field>`, so the
fix compares the lhs's own NORMALISED SOURCE TEXT (LowerCase + collapsed
whitespace) against what the finally frees, instead of requiring an `identifier`
node at all. See `DRagLint.Diagnostics.DeadCodeChecks.pas` (`IsFreeOf`,
`SubtreeFreesVar`, `TryFinallyFreesVar`, and the `create-inside-try` site) and
`tests\lint\create-inside-try.pas` procedures S/T/U/V (+ `.pas.expected`) for the
indexed- and multi-level-lhs fixtures. Original gap report kept below for
history.

**Status (superseded):** known gap, filed not fixed. Found during Task 9a review (2026-08-12).

## Repro

```pascal
procedure TFoo.Bar;
begin
  try
    Self.FList := TStringList.Create;  // NOT flagged (should be -- see below)
    Self.FList.Add('x');
  finally
    Self.FList.Free;
  end;
end;
```

Pre-Task-9a, this WAS flagged (the old rule fired on any `X := TFoo.Create` as the
first try-protected statement, regardless of lhs shape). Post-9a, the rule
requires the lhs to be a plain `identifier` node so it can name "the variable" to
check the finally against (`DRagLint.Diagnostics.DeadCodeChecks.pas`, the
`CtorLhs.NodeType = 'identifier'` guard next to the `create-inside-try` site).
`Self.FList` parses as an `exprDot` (lhs=identifier `Self`, rhs=identifier
`FList`), not a plain identifier, so it fails that guard and the rule stays
silent -- even in cases like the one above where the finally provably frees
exactly that field via `Self.FList.Free`.

**Not affected:** a bare `FList := TStringList.Create` (no `Self.` prefix) still
matches the `identifier` guard and is flagged correctly when its finally frees
`FList`/`Self.FList`. Only the explicitly-qualified `Self.X` (or any dotted) lhs
form is missed.

## Why not fixed in Task 9a

Extending this symmetrically needs matching logic on BOTH sides:
1. Construction side: accept an `exprDot` lhs shaped like `Self.<field>` (and
   decide how far to generalize -- `Self.X` only, or any `<expr>.X`, which raises
   its own soundness questions since `<expr>` could have side effects or alias
   through different objects).
2. Finally side: `IsFreeOf`/`SubtreeFreesVar` currently only recognize a BARE
   identifier being freed (`X.Free`, `FreeAndNil(X)`, `X.Destroy` where X is a
   plain identifier). They would need to also recognize `Self.X.Free` /
   `FreeAndNil(Self.X)` and treat `Self.X` and bare `X` as the same field
   (implicit-Self equivalence) without conflating it with an unrelated `Other.X`
   of the same field name on a different object.

That is a real doubling of the matching surface for a task whose entire point was
NARROWING create-inside-try (task-9-brief.md: "the user's priority is reducing
the count, not adding a new rule/behaviour"). This gap is a false NEGATIVE
(under-reporting), which does not work against that goal the way a false positive
would, so it was deliberately left for a follow-up rather than implemented inline.

## Suggested fix (when picked up)

- Add a `LhsFieldKey(ALhs: TTSNode): string` helper: returns the lowercased plain
  identifier name for `identifier` lhs, or the lowercased rhs identifier name for
  an `exprDot` lhs whose OWN lhs is the identifier `Self` (reject any other
  qualifier as unsafe/ambiguous rather than generalizing further).
- Extend `IsFreeOf` to accept `Self.X.Free` / `FreeAndNil(Self.X)` in addition to
  the bare forms, keyed on the same normalized field name.
- Fixture: the repro above (should fire), plus a suppression case where
  `Self.FList` and the finally frees `Self.FOther` (different field -- must not
  fire), and a case with a non-`Self` qualifier (`SomeObj.FList := ...` -- leave
  unflagged, matches current conservative behavior, document why).
