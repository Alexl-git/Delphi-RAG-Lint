> # RE-MEASURED 2026-08-16 (session 22): BOTH stated causes are DEAD. A third shape is live.
>
> **0 findings** in YADF, YADFOT, YADFSetup and DataCopy. The two competing
> explanations are both obsolete:
>
> * *out-arg-counted-as-a-READ* (the rule-hardening plan's row 3) was already
>   disproven and reverted; structurally, a bare identifier argument reaches
>   `CallDefs` only, never `Reads`.
> * *intra-item `and`/`or` ordering* (this note's own title) is fixed by
>   `CollectAndOrLeftDefs` (`DRagLint.Diagnostics.FlowChecks.pas:622-660`). Even
>   DataCopy's `uAlertGrouper.pas:384` case is silent now.
>
> **CORRECTION (same day, after reading all 39): they are NOT all one shape.**
> An earlier banner here said they were; that was based on a sample of five.
> The real split is **A=4 / B=21 / C=12 / D=2** -- see
> `docs\PLAN-SESSION-23-IMPLEMENTATION.md` section 4 for the full table and the
> per-site anchors. Crucially **12 of the 39 (shape C: arrays and records only
> ever element- or field-written) can NEVER be reached by any predicate
> correlation**, so the ceiling for that approach is 25, not 39.
>
> **What IS live: 39 findings on the self-index, all hedged `[info] ... may be
> used`. The largest group is BOOLEAN-FLAG-CORRELATED GUARDS:**
>
> ```pascal
> if Profiled then TMark := TStopwatch.GetTimeStamp;
> ...
> if Profiled then Inc(AccRes, TStopwatch.GetTimeStamp - TMark);
> ```
>
> The assignment and the read sit under the SAME guard, so the read is safe, but
> the flow analysis cannot see the correlation. Same shape at
> `Storage.SQLite.pas:8507-8509`, `Core.Indexer.pas:584-593` (`Best`/`HasBest`),
> `Refactor.TextEdit.pas:603-611` (`LastInSection`/`HaveLast`),
> `AstChecks.pas:2843-2848` (`Call`/`HaveCall`).
>
> A real fix needs predicate correlation -- assignment and read under the same
> condition, with the flag not mutated between -- which is M-L effort and
> genuinely risky (a reassignment between the two guards breaks it; comparing
> condition TEXT is only a proxy).
>
> **RECOMMENDATION 2026-08-16: DO NOT IMPLEMENT.** 0 findings on all four
> consumer projects; all info and correctly hedged; 14 of 39 unreachable by any
> correlation check; and the highest-yield part needs an airtight flag-pairing
> proof where ANY gap suppresses TRUE positives -- the worst failure direction
> for this rule. If it is ever picked up, do shape B forms (i)+(iv) only.
>
> Separately worth a look and probably a REAL bug: the finding at
> `Lint.ProjectRules.pas:1181` sits ON an inline `var` declaration -- a distinct
> walker defect, cost S.
>
> **Accepting them is a legitimate outcome.** They are hedged info findings on a
> correct and common idiom. Do NOT implement either of the two dead fixes above;
> if this is picked up, write a fresh note for the flag-correlation shape first.

> # NOT re-measured in session 22 (2026-08-16) -- stating that rather than implying progress.
>
> This note was NOT touched this session. Its status is exactly as the
> session-21 assessment left it: `and`/`or` left-to-right sequencing is modelled
> (`CollectAndOrLeftDefs`); the general position-ordered case is not.
>
> **Read this alongside `INBOX-rule-hardening-plan-2026-08-13.md` before picking
> it up.** That plan lists `used-before-assignment` as its item 3 with a
> DIFFERENT stated cause -- *an `out` argument is counted as a READ* -- 7
> findings, cost S, and the signature it needs is already indexed. The two are
> not the same defect, and the rule-hardening one is much cheaper. Measure which
> of the two actually accounts for the current findings before writing code;
> this project's repeated lesson is that the note's stated mechanism is often not
> the live one.

# `used-before-assignment` -- the backlog's premise was wrong; here is the real shape

> **PARTLY ADDRESSED 2026-08-15. The `and`/`or` case is modelled; the general
> position-ordered case is not.**
>
> `CollectAndOrLeftDefs` (`DRagLint.Diagnostics.FlowChecks`) now carries the
> left-to-right refinement for short-circuit chains, so both of these are silent:
>
> ```pascal
> if Supports(Intf, IFoo, V) and V.Method then ...
> if VerQueryValue(Pointer(Buf), '\', Pointer(Fixed), Len) and (Fixed <> nil) then ...
> ```
>
> The mechanism already existed for `not-assigned-interface`
> (`CollectInterfaceDerefs`' own `LocallyAssigned`, whose header explains the
> `Supports` idiom); the plain read check simply never had it, so the two checks
> disagreed about the same idiom. It is applied at the read check ONLY -- not
> inside `CollectReadsAndCallDefs`, which feeds liveness and several other rules
> and would change what they see.
>
> **This closed a REGRESSION, and how it arose is the interesting part.** The
> `Fixed` shape above sits inside `if A then if B then ...`, and until the
> dangling-else `exprIf` arm was added to `Cfg.pas.EmitStmt` the whole nested `if`
> was ONE OPAQUE ITEM -- and opaque items are skipped by the read check entirely.
> So fixing the CFG hole made this latent defect visible for the first time: one
> new false positive appeared on YADFSetup (`uYADFSetupMain.pas:140`) and is now
> gone. Expect more of this: **anything the opaque-item path was hiding is now
> reachable**, which is a good trade but not a free one.
>
> It also let a KNOWN LIMITATION be retired:
> `tests\autotest\run_flow_store_precision.ps1` section B asserted that
> `if TryFetch('k', G) and (G.Tag > 1)` still fires, with the note "flip this when
> intra-item evaluation order is modelled". Flipped -- it now asserts silence.
>
> **STILL OPEN:** ordering WITHIN a single expression that is not an `and`/`or`
> chain. `CollectReadsAndCallDefs` returns index lists with no positions, so a
> read cannot be compared against a def of the same variable in the same item.
> Doing it properly means threading byte offsets through that function, which
> feeds several rules -- worth it only if real findings demand it. Note the naive
> version (drop every read that is also a CallDef) is WRONG: `Writeln(Arr[0])` on
> a never-assigned array puts `Arr` in both lists and must keep firing. That case
> is the positive control in `run_addr_of_is_a_definition.ps1`.

Supersedes item **B** of `INBOX-rule-hardening-progress-and-plumbing.md`
("an `out` argument is a WRITE (7)"). That item was implemented, measured at a
yield of **zero**, and removed. This note records why, and what the findings
actually are, so the next session does not re-derive the same wrong fix.

## What the backlog claimed

> `FlowChecks.pas:561-619`. A call argument is added to BOTH `Reads` (checked at
> line 571) and `CallDefs` (applied at line 619, i.e. AFTER the read check). So
> `SafeDelete(LFile, LSweepErr)` with `out ErrCode: DWord` flags `LSweepErr` as
> read-before-assignment, then marks it assigned.

## What the code actually does

`CollectReadsAndCallDefs` (`DRagLint.Analysis.Flow.Lattices.pas`, the `exprCall`
branch):

```pascal
Idx := LeftmostBaseVar(Arg, ASrc, AVars);
if (Idx >= 0) and (ACallDefs.IndexOf(Idx) < 0) then ACallDefs.Add(Idx);
{ still walk non-identifier args for reads of OTHER vars (indices etc.) }
if Arg.NodeType <> 'identifier' then Walk(Arg, False);
```

A **bare identifier argument goes to `CallDefs` only and is never added to
`Reads`.** So the claimed defect cannot occur: passing an unassigned local as a
bare argument has never produced this finding, for `out` or for `var`.

Verified directly, against a built engine, before and after:

```pascal
procedure P; var X: Integer; begin Writeln(X);          end;  // SILENT (call arg)
procedure Q; var W: Integer; begin if Peek(W) then ...; end;  // SILENT (call arg, var param)
procedure R; var X, Y: Integer; begin Y := X + 1;       end;  // FIRES  (ordinary read)
```

The third case is the control that proves the rule is enabled and working. The
first two are the shape the backlog described, and they were already silent.

A parameter-modifier oracle (resolve the callee, ask whether argument *n* is
`out`, drop the read) was written, wired to a cache, and produced **no change in
any project's count**. It has been reverted rather than kept: an unused store
lookup on every call argument of every item is a real cost, and dead precision
machinery invites the next reader to believe the question is settled.

## The real shape: intra-item evaluation order

From the four surviving findings on `DataCopy.dproj`:

**`uAlertGrouper.pas:384`** -- a genuine false positive, and the interesting one:

```pascal
if FGroups.TryGetValue(LOldest, LGroup) and (LGroup.Count > 1) then
```

`LGroup.Count` is an `exprDot`, so `Walk(Lhs)` records LGroup as a real **read**
(this is the path bare arguments do not take). The call that *defines* LGroup is
in the **same CFG item**, and an item's `CallDefs` are applied only after all of
its reads have been checked -- so the read is judged against the state from
*before* the call. Delphi's `and` short-circuits, so `LGroup.Count` is evaluated
only when `TryGetValue` returned True and therefore assigned it.

The fix is to model evaluation order *within* an item -- a def occurring to the
left of a read reaches that read -- rather than treating an item as a set. That
is a change to the replay loop, not a lookup, and it is the only one of the four
that is clearly wrong today.

**`uZeissRoutines.pas:1162` and `:1231` (x2)** -- a different question:

```pascal
if FileExists(LRestore[LJdx]) then ...
if not CopyFileVerified(LBackup[LJdx], LRestore[LJdx], LMess) then ...
```

`LRestore[LJdx]` is *not* an identifier, so it IS walked for reads, and the
arrays are filled on a conditional path -- hence "**may** be used before it is
assigned" (info severity, correctly hedged). Whether these are false depends on
whether the analysis should track array elements or whole arrays; at whole-array
granularity the warning is defensible. Not obviously a defect.

## Guard

`tests\autotest\run_flow_store_precision.ps1`, section B, reproduces the
`TryGetValue ... and (G.Tag > 1)` shape hermetically and asserts that it **still
fires** -- the same convention `run_concat_in_loop_precision.ps1` uses for its
remaining limitation. Flip that assertion when intra-item ordering is modelled,
and the test will state exactly what changed.

## The lesson, which is the same one as last time

The previous session recorded: *"the earlier '8 of 8 sampled false' was read off
the source shape without testing the analyser."* This item was estimated the same
way -- from reading `CollectReadsAndCallDefs`' doc comment rather than running
it. **A backlog item that names a line number and a mechanism still has to be
reproduced against a built engine before it is implemented.** Both times, the
five minutes that would have cost were paid several times over instead.
