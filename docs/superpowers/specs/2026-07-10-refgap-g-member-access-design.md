# Ref-gap G -- index property/field MEMBER-ACCESS on typed receivers: design

**Date:** 2026-07-10
**Status:** Approved (design); implement via TDD -- WITH A SUPERVISED PAUSE
**Sub-project:** A of the "full component-conversion apply" milestone. A (this)
is the enabling index capability; B (the `convert-apply` verb) depends on it.
**Supervision:** the user explicitly wants to SUPERVISE the core-parser change
(same discipline as ref-gaps D and E). The RED test is written FIRST (safe); the
implementation PAUSES for the user's review of the exact
`DRagLint.Parser.Delphi13.pas` diff BEFORE the parser is touched.

## Problem

The full component-conversion apply (sub-project B) must rewrite property/event
ACCESSES at every use site of a converted instance -- `Edit1.Caption := x` ->
`Edit1.Text := x` when the rule set renames `Caption` -> `Text`. To do that
safely it must find every site where a specific MEMBER (`Caption`) is accessed on
an instance whose type is the converted `FromType` (`TOvcEdit`) -- NOT every
`.Caption` in the file (which might belong to unrelated objects).

The reference index does not record this today. For a member access `obj.Member`
(the `exprDot` case, `DRagLint.Parser.Delphi13.pas` ~line 1396), the parser emits
a `read` ref of the BASE identifier `obj` and DELIBERATELY DROPS the member
`Member` -- the code comment says so explicitly: *"The member itself is captured
as call/type_use elsewhere; we don't re-emit it here."* Ref-gap **D** (shipped
v0.98) added the member ONLY for the `Self.`-qualified case, gated tightly *"so we
do NOT flood refs with every obj.Method / obj.Prop member access."*

So today the index knows `Edit1` was used at a site, but not that `.Caption` was
the member accessed on it. Ref-gap G closes exactly that: index the member of a
`receiver.Member` access when the receiver is a plain identifier, under a distinct
ref kind so existing consumers are untouched.

## Verified facts (do not re-litigate)

- `exprDot` member access currently emits only a `read` of the base identifier
  (`DRagLint.Parser.Delphi13.pas` ~line 1398). The rhs member is emitted ONLY when
  lhs = `Self` (ref-gap D, ~line 1402-1408).
- Method-CALL receivers ARE typed: the index has a `call_edges` mechanism with
  `ReceiverTypeSymbolId` (`DRagLint.Core.Interfaces.pas` ~line 217) that resolves
  the receiver TYPE of a `call` ref. Property/field member access has no
  equivalent -- that is the gap.
- `TReference` (`DRagLint.Core.Model.pas` ~line 105) carries `Kind`, `NameText`,
  `EnclosingSymbolId` (the routine the ref sits in), and position. It has NO
  receiver-name column -- and this design does NOT add one (see "Schema" below).
- The rename engine (`TRenameRefactoring.Build` -> `FindCallersByName`) matches
  refs by `name_text` and is kind-agnostic. A NEW kind is therefore NOT picked up
  by the rename automatically -- which is what we want here (the applier queries
  the new kind explicitly; ordinary renames are unaffected).

## The fix

In the `exprDot` case of `Walk` (`DRagLint.Parser.Delphi13.pas`, the
`if NodeType = 'exprDot'` branch, gated by `AState.EmitUsageRefs`), ADDITIONALLY
emit a ref for the rhs MEMBER, under a NEW distinct kind:

- `kind = 'member-read'` normally;
- `kind = 'member-write'` when this `exprDot` is the LHS of an assignment
  (`Edit1.Caption := x`).

`NameText` = the member identifier (`Caption`). Position = the member identifier's
node span (so the applier can rewrite exactly those bytes).

### Tight gate (avoid ref-flooding -- the load-bearing constraint)

Emit the member ref ONLY when ALL hold:
1. The `exprDot` `lhs` is a plain `identifier` node (NOT a chained `exprDot`, NOT
   an `exprCall`, NOT an index expression). So `Edit1.Caption` is captured;
   `GetEditor().Caption`, `Panel.Edit1.Caption` (chained), `Arr[0].Caption` are
   NOT (those are the future expression-interpreter's problem, and indexing them
   would flood + mislead).
2. The `rhs` is a plain `identifier` (the member name). A further-chained rhs
   (`obj.A.B`) is handled by the recursion visiting each `exprDot` level; each
   level with an identifier lhs emits its own member ref for its own rhs.
3. Skip when lhs = `Self` -- that case is already covered by ref-gap D's `read`
   emission; do not double-emit. (G is for NON-Self receivers.)

This mirrors ref-gaps D/E: a SINGLE new emission site, gated to a narrow, precise
shape, under a controlled kind. No existing emission is changed.

### Write-vs-read classification

The `exprDot` node itself does not know it is an assignment target. Determine
`member-write` by context: when the `assignment` case (~line 1413) has an `lhs`
that is an `exprDot` (rather than a plain `identifier`), the member of that
`exprDot` is a WRITE. Implementation options (pick the cleaner at build time,
show the user in the diff):
- (a) In the `assignment` case, when `lhs` is `exprDot`, emit `member-write` for
  its rhs member there (and set a flag / handle it so the generic `exprDot`
  recursion does not ALSO emit `member-read` for the same node -- no double-emit);
  OR
- (b) Emit `member-read` in `exprDot` unconditionally, and let the applier treat
  read/write uniformly (a rename rewrites the member name identically whether it
  is read or written, so the distinction is informational). If (b), name the kind
  just `member-access` and drop the read/write split.

DECISION for the spec: prefer (b) `member-access` (one kind) UNLESS the user wants
the read/write split for reporting. Rationale: a property RENAME rewrites the same
bytes regardless of read/write, so the split adds parser complexity (and a
double-emit guard) for information the applier does not need in 2b. The RED test
asserts `member-access` on both a read (`x := Edit1.Caption`) and a write
(`Edit1.Caption := x`) site. (If B later wants read/write for a report, widen
then.)

## Schema

NO new column on `TReference` and NO migration. The new kind rides the existing
`kind` string column. The applier reconstructs "member M on receiver R" by joining
at QUERY TIME:
- the `member-access` ref gives the member `NameText` + position + `EnclosingSymbolId`;
- the companion base-identifier `read` ref at the SAME site (already emitted today)
  gives the receiver name;
- the receiver's TYPE is resolved via the existing receiver-typing path (the same
  machinery `call_edges` uses for call receivers), or -- simpler for 2b -- by the
  applier knowing the converted instance NAMES (from the `.pas` declaration it just
  rewrote) and matching `member-access` refs whose companion base-`read` NameText
  is one of those instance names, within the same unit.

The 2b applier's exact query is finalized in sub-project B's spec after G ships and
the row shape is confirmed on a real fixture. G's job is only to EMIT the
`member-access` facts correctly and tightly.

## Testing (headless, TDD; RED first, then the SUPERVISED pause)

New autotest `tests/autotest/run_member_access_refs.ps1`. Index a fixture unit:

```pascal
procedure TForm1.DoIt;
var L: TLocal;
begin
  Edit1.Caption := 'x';        // member-write (or member-access) on Edit1.Caption
  L := Edit1.Caption;          // member-access on Edit1.Caption (read)
  Grid2.Options.ReadOnly := True; // member-access on Grid2.Options (and the recursion
                                  // may emit Options.ReadOnly -- assert the gated shape)
  Self.FField := 1;            // NOT a new member-access (ref-gap D already covers Self)
  Caption := 'form';           // bare -- NOT a member-access (no receiver)
  L := GetEditor().Caption;    // NOT captured (lhs is exprCall, not a plain identifier)
end;
```

Assertions (via `find-callers`/`dump-refs --json` filtered to `kind=member-access`):
- `Edit1.Caption` (both sites) -> present as `member-access`, NameText='Caption',
  at the correct member positions.
- `Grid2.Options` -> present; the further `.ReadOnly` handled per the recursion
  rule (assert whichever the gate produces -- documented).
- `Self.FField` -> NOT present as `member-access` (still only ref-gap D's `read`).
- bare `Caption` -> NOT a `member-access` (it is a normal `write`/`read`).
- `GetEditor().Caption` -> NOT present (exprCall receiver excluded by the gate).

**Over-capture control (the flood check):** index a real, sizable unit (e.g. a
CLIENT form) BEFORE and AFTER the change; record the total ref count and the
`member-access` count. Confirm (1) no `read`/`write`/`type_use`/`call` counts
change (the new kind is additive, existing emissions untouched), and (2) the
`member-access` count is proportionate to actual `ident.Member` accesses, not
exploding (spot-check a sample against the source). Put the numbers in the report.

**Negative controls:** the existing `run_self_field_refs.ps1` (ref-gap D) and
`run_type_ref_gap_e.ps1` (ref-gap E) must stay GREEN -- G must not disturb D's
Self. handling or E's type_use emissions.

## Supervision gate (the load-bearing process rule)

1. Write the RED test (`run_member_access_refs.ps1`) and run it against the CURRENT
   exe to capture RED (member-access refs absent).
2. Do the AST recon (a throwaway S-expr dump, reverted) to confirm the exact
   `exprDot` lhs/rhs field names + the assignment-lhs shape -- documented in the
   build report.
3. **STOP. Hand the user the exact `DRagLint.Parser.Delphi13.pas` diff.** Do NOT
   apply it without the user's explicit go. (This is the same pause ref-gap E
   honored.)
4. After approval: apply, rebuild Win64 Debug, run GREEN + the over-capture check +
   the D/E negative controls.

## Files (sub-project A)

- `src/parser/DRagLint.Parser.Delphi13.pas` -- the ONE new gated emission in the
  `exprDot` (and possibly `assignment`-lhs) branch. SUPERVISED.
- `tests/autotest/run_member_access_refs.ps1` -- the RED->GREEN + over-capture +
  negative-control test.
- Docs: CHANGELOG + a line in `docs/CONVERSION-RULES.md` noting the enabling
  capability for the applier's property-access rewrite.

## Global constraints

- Encoding: all new/edited `.pas` + `.ps1` strict 7-bit ASCII, no BOM, CRLF.
- DocInsight where a public surface changes; the new emission carries a clear code
  comment explaining the gate (mirroring the ref-gap D comment right beside it).
- TDD: failing test first (RED), the SUPERVISED pause, then GREEN + over-capture
  evidence.
- No new ref-kind may change existing `read`/`write`/`type_use`/`call` behavior;
  the D/E autotests are the regression net.

## What G explicitly does NOT do (deferred / out of scope)

- Receiver TYPE resolution join -- that is a QUERY-time concern owned by sub-project
  B (the applier). G indexes the raw member-access facts.
- Chained / call / indexed receivers (`a.b.Caption`, `f().Caption`, `arr[i].Caption`)
  -- excluded by the gate; the future expression stage may revisit.
- Any rewrite -- G is index-only. The rewrite is sub-project B.

## Self-review notes

- Mirrors the exact discipline that made ref-gaps D and E safe: one narrowly-gated
  emission, a distinct/controlled kind, RED-first, a supervised parser-diff pause,
  an over-capture flood check, and D/E as the regression net.
- The new kind (not a reused read/write, not a new column) is the minimum-blast-
  radius choice: existing name-based consumers (rename, find-callers, naming
  autofix) do not see `member-access` unless they opt in, so nothing existing
  shifts. Confirmed against the kind-agnostic-but-not-auto-consuming rename path.
