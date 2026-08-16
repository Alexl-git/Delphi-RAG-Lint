# INBOX -- three dataflow rules are majority-false (and one proposes a bug)

> **SECTION 3 IS FIXED, 2026-08-16. `double-free` 42 -> 0.**
>
> Re-measured first: 42, unchanged. Then read ALL 42 against source -- not a
> sample, the whole set -- and every one was false. They were **three different
> bugs**, which is why the note's single "loop-invariance" fix would not have
> closed it:
>
> * **A. The freed expression was not the variable (~15).** `DetectFreedVarKind`
>   resolved the operand with `LeftmostBaseVar`, which walks DOWN to the leftmost
>   identifier, so `ColKv.Value.Free` and `FieldMaps[I].Free` were both credited
>   to the base var. What they free is a member or an element -- a different
>   object every pass. Fixed by `FreedOperandVar`: the operand must BE the
>   variable (a bare identifier), not merely start with it. Deliberately NOT
>   applied to `DetectFreedVar`, which backs object-leak's escape lattice: there
>   the loose reading only ever SUPPRESSES a finding, so it is the conservative
>   one. Here it fabricated findings.
> * **B. The for-in iterator is rebound every pass (~15).** `for L in Coll do
>   L.Free`. The CFG already recorded the iterator in `TCfgBlock.EntryDefs` and
>   `TDefiniteAssignment` already honoured it; `TFreedState` did not, so the loop
>   back-edge carried "L is dangling" into an iteration that sees a different
>   object. Fixed by `ApplyEntryDefs` -- now ONE implementation that both
>   lattices and both replays in `FlowChecks` call, differing only in the value
>   written (True = assigned, False = not-dangling).
> * **C. An inline `var X := Expr` was not a definition at all (~11).**
>   `AssignmentTargetIndex` resolved a `varAssignDef` lhs with `NamedChild(0)`,
>   and **the `var` KEYWORD is a named child**, so it looked up a routine var
>   literally called "var" and returned -1. Every inline declaration failed to
>   kill any prior state. **Fourth bug in this tree from "keywords are NAMED
>   nodes."** One-line fix: `FirstIdentChild`, which `LeftmostBaseVar` was
>   already using two functions away.
>
> Guarded by `tests\autotest\run_double_free_loops_and_members.ps1`, **7/7**.
> **Three positive controls**, because the cheap fix for all three causes is to
> stop reporting inside loops: a straight-line `Free; Free;`, an inline-declared
> var freed twice, and -- the one that matters -- **ONE object created OUTSIDE a
> loop and freed INSIDE it**, which is a genuine double free from the second
> iteration on and MUST still fire. It does.
>
> **Blast radius, measured, whole tree 1575 -> 1535:** `double-free` -42;
> `overwrite-before-read` **+2**, and both are GENUINE dead stores
> (`FormsMap.pas:1008 var Hooked := False`, `MCP.Server.pas:1082 var BundleTask
> := ''`) that the rule could not see before fix C. Everything else returned to
> baseline. 0 error-severity findings.
>
> Fix C also exposed a latent object-leak FP -- `var Re := TRegEx.Create(..)` --
> because `TypeIsRefCountedOrValue` decides from the DECLARED type and an inline
> var has none. Closed in the same pass by `ConstructedTypeText`, which falls
> back to the type the constructor names. The guard that already existed (and
> already named TRegEx in as many words) simply had nothing to read.
>
> **What is left in this note: nothing.** All three sections are now fixed.
> Section 2 (`used-before-assignment`) was closed on 2026-08-15 by
> `CollectAndOrLeftDefs`; the residue is correlated conditions, a
> path-sensitivity limit, tracked in
> `INBOX-used-before-assignment-array-local-never-counted-as-defined.md`.
> **Retire this note once the battery is green.**
>
> **SECTION 1 IS FIXED, 2026-08-15. `overwrite-before-read` 56 -> 32.**
>
> `ProtectedByFollowingTry` (`DRagLint.Diagnostics.FlowChecks`) suppresses the
> finding when the store is a member of the run of assignments immediately
> preceding a `try` whose except/finally MENTIONS that variable. Guarded by
> `tests\autotest\run_overwrite_before_read_pretry.ps1`.
>
> The predicate is the SOUND one, not the cheap one, and the difference is
> asserted: a store before a `try` whose handler never names it STILL FIRES
> (fixture case `UnrelatedTry`), alongside an ordinary dead store with no `try` in
> sight (`GenuineDead`). Without both controls the fix would be indistinguishable
> from switching the rule off, which is the trap this whole note warns about.
>
> Scoped to the CHECK, not the CFG -- following the precedent
> `FreedInFinallyBlock` set for object-leak's identical cause. The `try..except`
> handler edge models "the exception fired after the body's assignments ran", and
> `used-before-assignment` depends on the state that edge carries, so rerouting it
> would perturb every dataflow rule at once. Verified acceptance: the note's own
> example sites are gone (`Doc.SymbolFacts.pas:1371`, `CLI.pas:7727-7730`).
>
> **The 32 survivors are NOT this shape and are not covered** -- sample them
> before assuming. The note's own section on the interface-release form is one
> known category.
>
> **`double-free` (42) and the rest of the table are UNTOUCHED.** This note stays
> open for them; its method -- sample before believing a count -- is why it is
> trustworthy where a raw count is not.
>
> Original 2026-08-14 triage banner follows.
>
> On drag-lint's own source right now: `overwrite-before-read` **56**,
> `too-many-exit-points` 150, `duplicate-code` 169, `concat-in-loop` 117. So the
> 58 in the table below is essentially unchanged.
>
> `used-before-assignment` from the same table HAS moved: two separate causes were
> fixed this session (the dangling-else `exprIf` CFG hole, and `@Arr[0]` counted as
> a read instead of a write), and YADFOT's instances are gone. Its remaining
> DataCopy findings are **correlated conditions** -- `if LHasBck` guards both the
> write and the read -- which is a path-sensitivity limit, not a bug, and is the
> one shape in this family that is legitimately `dl:ok`-able. See
> `INBOX-used-before-assignment-array-local-never-counted-as-defined.md`.
>
> **Start with section 1.** It is the strongest case in the whole INBOX: the rule
> does not merely produce noise, its ADVICE IS WRONG -- deleting the nil-init
> before a `try` leaves an uninitialised variable to be tested or freed on the
> exception path, so following the finding converts correct code into a crash.
> The fix shape is narrow and syntactic: do not report a store when the next
> statement is a `try` whose `except`/`finally` reads or frees that variable. The
> multi-init case (five nil-inits before one `try`) must be covered -- protection
> extends to every variable initialised between the previous statement and the
> `try`, exactly as `object-leak`'s Cause A needed.
>
> And per this repo's hard-won pattern: the guard fixture must include a GENUINE
> dead store that must still fire, because the cheap fix for every rule in this
> family is to stop reporting near a `try`.

**Filed:** 2026-08-11, sampling group E of the 1,742-finding `lint-all` baseline.
**Method:** findings sampled evenly across the whole result set and read against
source, per the standing rule -- sample before believing a big number.

**Result: 15 of 15 sampled findings were FALSE, across three rules covering 146
findings.** A fourth rule in the same group (`object-leak`, 56) was already audited
0/12 real in an earlier session. That puts roughly **202 of group E's 261 findings**
in doubt.

| rule | findings | sampled | false | root cause |
|---|---|---|---|---|
| `overwrite-before-read` | 58 | 5 | **5** | pre-`try` nil-init; interface release |
| `used-before-assignment` | 46 | 4 | **4** | guard-flag + short-circuit not modelled |
| `double-free` | 42 | 6 | **6** | one `Free` per loop iteration, distinct objects |

---

## 1. `overwrite-before-read` (58) -- the fix would INTRODUCE bugs

This is the most serious of the three: it is not merely noisy, its advice is wrong.

Three of five sampled findings flag the initialisation immediately before a `try`:

```pascal
Bindings:= nil;                 // <-- flagged "dead store"
try
  Bindings:= ExtractDfmEventBindings(TFile.ReadAllBytes(ADfmPath));
except
  Bindings:= nil;               // unreadable .dfm -- absence over a wrong fact
end;
```

```pascal
StemToGlobal:= nil;
Edges       := nil;
Externals   := nil;
EdgeList    := nil;             // <-- flagged "dead store"
ShortestPath:= nil;
try
  LoadFilesAndEdges(AStores, AllFiles, StemToGlobal, Edges);
```

The store is NOT dead: it is what makes the `except`/`finally` path safe. Deleting it
leaves an uninitialised variable to be tested or freed on the exception path. **The
rule's suggested fix converts correct code into a crash.**

A fourth is worse still -- it is not a dead store at all:

```pascal
Store:= nil; // release the read-only handle before the indexer writes
if not ReindexAfterStaleAnchor(AArgs, Res.FilePath) then Exit(1);
Store:= OpenReadOnlyStore(AArgs.DbPath, Ok);
```

`Store` is a refcounted INTERFACE. `:= nil` is a side-effecting statement that closes
the database handle; the very next line needs it closed. The comment on the line says
so. Removing it breaks the reindex.

A fifth points at `DRagLint.Storage.SQLite.pas:4792`, which is a bare `end;` with no
assignment on it -- so the reported LOCATION is wrong too.

**Fix:** a store is only dead if the variable is (a) not an interface/managed type
whose assignment has a side effect, and (b) not live on any exception edge. The
current analysis appears to consider only the normal-flow successor, which is exactly
the path a `try` guard is not written for.

## 2. `used-before-assignment` (46) -- guard flags are not modelled

All four sampled findings are one idiom: a `HasX`/`HaveX` boolean that gates the read,
with short-circuit evaluation.

```pascal
if HasBest and (not NoDeclarationInGap(Best.EndLine, ...)) then   // Best read only if HasBest
if (not HaveLast) or (U.StartLine > LastInSection.StartLine) then // LastInSection read only if HaveLast
if (not HasMth) or Mth.IsNull or (Mth.NodeType <> 'identifier')   // Mth read only if HasMth
else if HaveGlobal then Result:= GlobalManifest;                  // GlobalManifest read only if HaveGlobal
```

The flag is assigned on exactly the same path as the variable, so the read is safe.

**Fix:** correlate a boolean with the variables assigned alongside it (a simple
two-variable relational fact), or -- much cheaper and still sound -- suppress when the
read is dominated by a test of a boolean that is assigned in the same basic block as
the variable. Delphi's `and`/`or` short-circuit must be honoured; if the analysis
treats them as strict, that alone explains every hit.

## 3. `double-free` (42) -- one Free per iteration, over distinct objects

```pascal
finally
  for ColKv in SqlColumns do ColKv.Value.Free;    // <-- flagged
  for var Kv2 in DelphiFields do Kv2.Value.Free;
  ParentLookup.Free;
```

```pascal
finally Q.Free; Seen.Free; end;                   // <-- flagged
```

Each iteration frees a DIFFERENT object; the loop variable is rebound every pass. The
`finally`-block cases are a single free on every path -- the canonical Delphi idiom
the codebase is supposed to be written in, and which other rules (`create-inside-try`,
`unprotected-object-free`) actively demand.

**Fix:** do not count a free inside a loop body as "the same object freed twice"
unless the freed expression is loop-INVARIANT. `ColKv.Value` depends on the loop
variable; `SomeField.Free` inside a loop would not.

---

## Why this matters beyond the count

These 146 findings sit in the group labelled "real defect candidates" -- the group a
reader is most likely to trust. `overwrite-before-read` in particular hands out advice
that is actively harmful, and it does so 58 times.

**Recommended order:** fix `overwrite-before-read` first (harmful), then
`used-before-assignment` (single well-defined cause, probably one change to
short-circuit handling), then `double-free` (loop-invariance test). Add a fixture per
root cause from the snippets above -- each is small and self-contained.

Related: `docs/BACKLOG-lint-false-positives.md`, and the standing rule that a category
which is always wrong is worse than no category, because people learn to skip it --
including on the day it is right.
