> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# `used-before-assignment`: an `out` arg assigned in an `if` CONDITION does not reach the `else` branch

> **FIXED 2026-08-14 (session 19). The node type was `exprIf`.**
>
> `tools\dumpnode` (already built at `src\cli\Win64\Debug\dumpnode.exe` -- no
> build needed) settled the one open question in three runs:
>
> ```
> if #1 at line 15: ChildCount=4 NamedChildCount=4      <- the OUTER if, NO kElse
>     child[ 3] statement  | if Fill(F, Err) then Writeln('ok') else ...
>
> statement #1 at line 16: ChildCount=2 NamedChildCount=1
>     child[ 0] exprIf     | if Fill(F, Err) then Writeln('ok') else ...
> ```
>
> So the dangling else is `statement(exprIf(...))`. `EmitStmt` had arms for
> `'if'`, `'ifElse'`, `'block'` and `'statements'` -- **none for `'statement'` or
> `'exprIf'`** -- so it fell through to the opaque-item path. Note the outer `if`
> has NO `kElse` child: the grammar binds the else correctly, so this was never a
> mis-binding. And the SAME if/else nested in a `for` is a plain `ifElse`
> (measured), which is why only this one shape was ever wrong.
>
> **Fix** (`DRagLint.Analysis.Cfg.pas`, `TBuilderState.EmitStmt`): unwrap a
> `statement` node whose single named child is an `exprIf`, and add `'exprIf'` to
> the conditional arm. The arm now resolves `condition`/`then`/`else` by field
> with a POSITIONAL fallback over the named children (skipping the `kIf`/`kThen`/
> `kElse` keyword nodes, which are themselves named -- the trap the `case` arm
> documents), because `exprIf` is not guaranteed to declare those fields. It also
> now branches on whether an `else` node EXISTS rather than on `K = 'ifElse'`,
> since `exprIf` goes either way.
>
> **Verified:** all 4 false positives in the probe unit gone, both genuinely
> unsafe controls (V8, V9) still reported; DataCopy `uZeissRoutines.pas` 1375 and
> 1675 gone, the 3 array-local findings unchanged as predicted. Regression test:
> `tests\autotest\run_dangling_else_cfg.ps1` (fails before the fix, passes after,
> with a positive control so it cannot pass with the rule off).
>
> **Still open: the ARRAY-LOCAL sub-case** (`lrestore`/`lbackup` at 1160 and
> 1229) -- see "Validated against the real findings" below. Different defect,
> same rule name.

Class: **wrong**. 7 findings on DataCopy, 2 on YADFOT. Minimal repro below --
8 lines, no store needed, reproduces with a bare `lint <file>`.

Rule-hardening plan item 3 called this "`out` argument counted as a READ,
cost S". That is the wrong diagnosis: an `out` argument IS handled correctly in
the simple case. The trigger is the **else branch**.

## Minimal reproducer

```pascal
function Fill(const A: string; out E: DWord): Boolean; forward;

procedure E1(const F: string);          // FIRES -- warning, "is used before"
var Err: DWord;
begin
  if F <> '' then
    if Fill(F, Err) then
      Writeln('ok')
    else
      Writeln(Format('%s %d', [F, Err]));   // <-- flagged
end;

procedure D1(const Files: TArray<string>);  // FIRES -- info, "may be used"
var Err: DWord; F: string;
begin
  for F in Files do
    if F <> '' then
      if Fill(F, Err) then
        Writeln('ok')
      else
        Writeln(Format('%s %d', [F, Err]));
end;
```

`Fill` assigns `E` unconditionally, and it is called in the CONDITION, so the
definition dominates BOTH branches. Reading `Err` in the else branch is safe.

## What is and is NOT the cause -- each eliminated by test

* **NOT "out args count as reads."** These are silent, correctly:

      Fill('x', Err);  if Err = 0 then ...                  { statement    }
      if Fill('x', Err) then if Err = 0 then ...             { condition    }

  So the possible-def treatment `CollectReadsAndCallDefs` documents does work.
* **NOT the store.** `lint <file>` and `lint <file> --db <db>` give identical
  output on uZeissRoutines.pas.
* **NOT cross-unit signature lookup.** A two-unit probe (`Fill` in UbaHelper,
  caller in UbaCaller) is silent.
* **NOT routine size.** E1 is eight lines and fires.
* **IT IS the else branch.** The only difference between the silent
  `if Fill(F, Err) then if Err = 0 then ...` and the firing
  `if Fill(F, Err) then ... else <read Err>` is which branch does the reading.

## Two severities, one bug

Note the `for` loop changes the verdict from MUST to MAY:

    E1 (no loop)  -> warning  "Local "err" is used before it is assigned."
    D1 (in a for) -> info     "Local "err" may be used before it is assigned."

Both come from the same emit site pair in `DRagLint.Diagnostics.FlowChecks.pas`
(~line 601 info / ~604 warning). DataCopy's real findings are all the `info`
form, which is why they read as hedged rather than wrong.

## BISECT COMPLETE 2026-08-14 (session 19) -- IT IS THE DANGLING ELSE

The bisect the section below asked for is done. Probe unit checked in beside this
note as **`docs\probe-used-before-assignment-dangling-else.pas`** (untracked,
like this note; 13 variants, reproduces with a bare `lint <file>`, no DB).

Both remaining halves of the old diagnosis are now dead: **the else branch is
not where the read has to be** (V4 fires with the read in the THEN branch), and
**the outer condition's content is irrelevant** (V2 fires with `if True then`).

| # | change from the V0 baseline | fires |
|---|---|---|
| V0 | baseline: outer `if` no-else / inner `if..else` / single-stmt bodies | **YES** warn |
| V1 | outer `if` gains an `else` | no |
| V2 | outer condition reduced to `True` | **YES** warn |
| V3 | outer `if` -> `while` | no |
| V4 | read moved to the inner THEN branch | **YES** warn |
| V5 | outer `if` -> plain `begin..end` | no |
| V6 | read moved after the inner `if`, inside the outer then-block (SAFE) | no (correct) |
| V7 | else body compound + read via `N := Err` | no |
| V10 | else body compound, read form UNCHANGED (open array) | no |
| V11 | single-stmt else, read is `Err + 1` (not an open array) | **YES** warn |
| V12 | inner `if` loses its `else` | no |
| V8 | read after an elseless `if Fill(...)` -- genuinely unsafe | **YES** info (correct) |
| V9 | as V8 with `N := Err` -- genuinely unsafe | **YES** info (correct) |

V10 vs V11 resolves a confound the earlier matrix left in: V7 changed the read
form AND made the else compound at once. **The read form is innocent** (V11
fires without an open array); **the `begin..end` is the discriminator** (V10 is
silent with the open array intact). The earlier "open-array constructor" clause
should be struck.

V8/V9 are the positive controls: the rule fires correctly, in the `info` form,
on the genuinely-unsafe shape, through both read forms. So neither read
detection nor the join merge is broken.

### The trigger, stated exactly

    if A then           <- an `if` with NO else
      if B(out V) then  <- whose then-part is a SINGLE-STATEMENT `if` WITH an else
        S1              <- single statement
      else
        S2              <- single statement, and one of S1/S2 reads V

**This is the DANGLING ELSE, and only it.** Every silencing edit removes the
`else`-binding ambiguity and nothing else does: give the outer `if` its own
`else` (V1), take the inner `else` away (V12), put `begin..end` at either level
(V5, V7, V10), or make the outer construct one that cannot own an `else` at all
(V3, `while`). Change the condition text (V2) or move the read between branches
(V4) -- both ambiguity-preserving -- and it still fires.

### Where it is, from the anchor column

The finding anchors at **34:5**, and column 5 is the inner `if` KEYWORD -- the
condition `Fill(F, Err)` starts at column 8. `FlowChecks.pas:689` anchors on
`It.Node.StartPoint`, so **the CFG item is the ENTIRE inner `if` statement**,
not its condition.

`Cfg.pas:617-638` cannot produce that: the `if`/`ifElse` arm adds only the
CONDITION as an item and recurses `EmitStmt` into each branch. So the inner `if`
is reaching `EmitStmt`'s unknown-statement fall-through, which means **its
NodeType is neither `if` nor `ifElse`** -- the grammar types the ambiguous
nesting as something `EmitStmt` has no arm for (or wraps it), and it lands in the
add-as-one-opaque-item path.

Once it is one item, `CollectReadsAndCallDefs` (`FlowChecks.pas:675-678`) is
handed a node spanning BOTH branches and the read check runs before that item's
own CallDefs are applied, so the out-arg's definition in the condition is not
yet in `CurMust`/`CurMay` when the branch read is tested. The `warning` (not
`info`) severity confirms it: `CurMay` is false too, i.e. the condition's def is
not applied at all rather than merged weakly.

### The one remaining unknown, and the next action

**What NodeType does tree-sitter-delphi13 actually give that inner `if`?** That
is the whole fix: add the arm to `EmitStmt`, or normalise the wrapper. Do NOT
guess it -- `tools\dumpcase`'s own header records that assuming a node shape is
what caused its two bugs, and `tools\dumpnode` exists precisely for this
question. Build `tools\dumpnode\dumpnode.dpr` (delphi-build skill) and run:

    dumpnode docs\probe-used-before-assignment-dangling-else.pas if
    dumpnode docs\probe-used-before-assignment-dangling-else.pas ifElse

then compare V0's inner `if` (line 34) against V12's (line ~213, silent) and
V10's (line ~181, silent).

### Validated against the real findings -- and they are NOT all one bug

Re-measured on `C:\Projects\DataCopy\uZeissRoutines.pas` (5 findings, all `info`):

| site | local | shape |
|---|---|---|
| 1375:9 | `lsweeperr` | **dangling else** -- exact V0 shape |
| 1675:9 | `lsweeperr` | **dangling else** -- byte-identical to 1375 |
| 1160:12 | `lrestore` | array local, read as `LRestore[LJdx]` -- DIFFERENT |
| 1229:12 | `lbackup` | array local -- DIFFERENT |
| 1229:12 | `lrestore` | array local -- DIFFERENT |

1375 and 1675 are `for LFile in ... do / if LFile...EndsWith(...) then / if
SafeDelete(LFile, LSweepErr) then inc(LCleaned) else pLogger.LogError(...)` --
the dangling else, with the `out ErrCode` this note opened with.

**The other three are a separate sub-case: an ARRAY local, read as
`LArr[LIdx]`, whose element-wise assignment is evidently not tracked as a
definition of the array.** They share the rule name and nothing else. So fixing
the dangling else will clear 2 of these 5, not all of them -- do not read a
remaining count as a failed fix. The array sub-case needs its own probe and
probably its own note; it was never separated out because all 7 were counted as
one defect from the start.

Blast radius to check once the arm is added: an opaque whole-`if` item means
EVERY dataflow rule sharing this replay loop -- `not-assigned-interface`,
write-only-local, the freed/liveness analyses in the same `for B` loop -- has
been seeing a dangling-else `if` as one indivisible statement. Expect changes
beyond this one rule, and re-run the flowengine suites, not just the lint ones.

## PROBE MATRIX 2026-08-14 -- "IT IS the else branch" is REFUTED (superseded above)

The claim below that the else branch is the trigger does not survive testing. Ten
variants run against engine 1.3.0-alpha; the ORIGINAL repro still fires at `15:5`
throughout, so this is not an engine drift.

| # | shape | read form | fires |
|---|---|---|---|
| E1 | outer `if` + inner `if/else` | `Format('%s %d',[F,Err])` in else | **YES** |
| P1 | flat `if/else` (no outer) | `Format('%s %d',[F,Err])` in else | no |
| P2 | flat `if`, then-branch | `Format(...)` in then | no |
| P3 | no `if` at all | `Format(...)` after the call | no |
| P4 | flat `if/else` | `if Err = 0` in else | no |
| A | outer `if` + inner `if/else` | `if Err = 0` in else | no |
| B | flat `if/else` | `if Err = 0` in else | no |
| C | outer `if` + inner `if`, no else | `if Err = 0` | no |
| D | flat `if`, no else | `if Err = 0` | no |
| -- | any | bare `Writeln(Err)` | no (call arg = possible-def) |

**So the else branch alone does NOT fire it (P4, A, B), and the open-array read
alone does NOT fire it (P1, P2, P3). Only the CONJUNCTION does:** an OUTER `if`
wrapping an inner `if/else` whose else branch reads the variable inside an
open-array constructor `[...]` passed to a call.

That the trigger needs an enclosing `if` is the surprising half, and it is what
the "8-line minimal repro" hid -- E1 was minimal in LINES, not in FEATURES, so
three independent conditions were being varied at once and only their
conjunction was ever tested.

Next step is therefore NOT a code fix but one more bisect: keep E1 and remove the
outer `if` condition's own content (`F <> ''` -> `True`), then swap the
open-array for a plain call argument, to see which of the two is load-bearing and
why an enclosing block changes the classification of a read two levels down.
Check `Reads` vs `CallDefs` membership for the condition item in E1 and in P1 --
`FlowChecks.pas:674-698` collects both and runs the read check BEFORE applying
the item's own `CallDefs`, so anything that moves `Err` from CallDefs to Reads
flips the verdict.

Real DataCopy sites to validate any fix against (7, all in the `may` form except
`uAlertGrouper.pas:384`):
`uZeissRoutines.pas` 1160, 1229 (x2), 1375, 1675; `uAlertGrouper.pas:384`;
`DPPRoutines.pas:201`.

## Where to look -- CORRECTED 2026-08-14, the section below was WRONG

> **Re-measured with engine 1.3.0-alpha. The finding anchors on the CONDITION
> line, NOT on the read in the else branch.**
>
>     15:5  [warning] used-before-assignment: Local "err" is used before it is assigned.
>
> where line 15 is `if Fill(F, Err) then` and the else-branch read of `Err` is on
> line 18. The control (`if Fill(F, Err) then if Err = 0 then`) is still silent.
>
> That kills the "else branch does not inherit the def" theory outright: if the
> else edge were missing the definition, the finding would land on the READ, at
> 18. It lands on the condition, so what is being flagged is `Err` INSIDE
> `Fill(F, Err)` -- the out-argument itself, read-classified.
>
> **Both structures below were inspected and are CORRECT**, so neither is the
> bug:
> * `DRagLint.Analysis.Cfg.pas:620` -- `EmitStmt` adds the condition to the
>   CURRENT block (`Cfg.Blocks[ACur].AddItem(Cond, ...)`) and then adds BOTH the
>   then-block and the else-block as successors of that same `ACur`. The
>   condition's effects are therefore in the OUT set both branches inherit,
>   exactly as the old text below demanded. It already does this.
> * `DRagLint.Analysis.Flow.Lattices.pas:1281-1284` --
>   `TDefiniteAssignment.Transfer` calls `CollectReadsAndCallDefs` on the item and
>   sets `Must`/`May` for every returned CallDef. Note it DISCARDS `Reads`
>   entirely; the read check is not here.
>
> **So look in `DRagLint.Diagnostics.FlowChecks`, at the read-check emit site and
> at `ALocallyAssigned`** (its header describes accumulating intra-item defs so
> that `Supports(Intf, IFoo, V) and V.Method` does not flag `V`). That mechanism
> is what makes the CONTROL silent, and the question is why it does not cover the
> same out-argument when the enclosing `if` has an `else`. Start by dumping which
> list `Err` lands in for the condition item in each of the two shapes.

### Original (superseded) text

The condition expression's call-defs are evidently applied to the fall-through /
true successor but not merged onto the false edge. In CFG terms the definitions
computed while evaluating the condition must be in the OUT set of the condition
block itself, so both successors inherit them -- not attached to the then-block.

## Do NOT `allow` these

`SafeDelete(const APath: string; out ErrCode: DWord)` settles the real case: the
line the finding points at is a WRITE. Marking it reviewed would record
something untrue.
