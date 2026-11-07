# Parameter modes for the liveness rules, and the by-value false negative (E-LD-ROW7)

Date: 2026-11-06. Lane: 146 t1. Status: phase 1 built, three OFF rules; owner reviews the branch.
Background: `C:\TEMP\claude\lanes\145\survey\SURVEY.md` row 7, `lanes\145\ld\REPORT.md`.

## 1. What the survey assumed, and what the code does

The survey said (INFERRED) that the parameter-mode oracle "feeds write-only-local and
overwrite-before-read", so typing method receivers would reduce their false positives. Read in source,
that is wrong in both halves:

* `TLiveness.Transfer` and the replay in `TFlowChecker.Check` call `CollectReadsAndCallDefs` WITHOUT
  the oracle. Only `TDefiniteAssignment` (used-before-assignment) passes it.
* In liveness every call argument is a USE ("callee may read it"). So no oracle answer can remove a
  liveness finding; the error these rules make is the other way round. They cannot have the false
  positives the survey describes. They have false NEGATIVES:

| shape | today | truth |
|---|---|---|
| `Obj.Get(X);` (out) and X read nowhere else | X counts as read; silent | write-only |
| `Get(X);` (bare, out) and X read nowhere else | same; silent | write-only |
| `X := 1; Obj.Get(X); Use(X);` | `X := 1` counts as live; silent | dead store |
| `Obj.Take(X);` (by value), X never assigned | no read recorded, because the mode dispatch asks bare names only; silent; and X then counts as defined | read of garbage |

A `var` argument stays a use in all of this: the callee may read it.

## 2. Options

A. **Pass the oracle into `TLiveness` and let the two existing rules see out arguments; add the method
   dispatch to `CollectReadsAndCallDefs`.** The tidiest code. But `DRagLint.Analysis.Flow.Lattices` is a
   fingerprint unit, so it is a bump (re-parse of every DB), for a lint-only change that writes nothing
   to any index. And it changes what default-ON rules report, one of them at error severity, with no
   measurement behind it, while the owner is away. Rejected for now.

B. **Same, but widen the existing rules from a post-pass in `FlowChecks`.** No bump, but it still moves
   ON rules with no opt-out. `Obj.TryGet(K, Dummy)` becoming a new default finding is exactly the noise
   the owner has to rule on first. Rejected for now.

C. **New rule ids, OFF, from a post-pass in `FlowChecks`.** No fingerprint unit, no ON rule moves, a
   count per shape is available before anyone decides anything. The price: a second liveness solve and a
   small per-item scan, and three catalog entries that may later fold into their parents. **Chosen.**

D. **Do nothing but correct the backlog.** The FNs are real; rejected.

## 3. Phase 1 (this branch)

Three rules, all `False` in the catalog (OFF), all in `TFlowChecker.Check`:

| rule | severity | fires when |
|---|---|---|
| `local-only-out-arg` | info | a local is passed as an `out` argument, and nothing in the routine reads it; existing write-only-local stays silent on it because that argument counted as a read |
| `dead-store-before-out-arg` | warning | a whole-variable store whose value is overwritten by an `out` argument before any read, and the local is read somewhere |
| `by-value-arg-before-assignment` | error when no path assigned it, warning when some path did | a local is passed by value or const to a METHOD before it is assigned |

### What counts as proof

**Mode.** An argument is `out` or by value only when the oracle says so outright; `pmUnknown` means
silence in all three rules.

* Bare callee: the existing `ParamMode` closure (store, then same-unit signatures).
* Method callee: `TMethodArgModes.ModeOfArg` (L-D): receiver static type from ref_types, overload set
  over the whole ancestry, all applicable overloads agree. It now also answers `pmConst`, meaning "by
  value or const". Its callers on the used-before-assignment path test `in [pmVar, pmOut]`, so they do
  not move.
* A by-value answer is withheld when the parameter's type is untyped, a pointer spelling (`^T`, `Pointer`,
  `PChar`, `LPWSTR`, or `P` + capital) or when the local is a static array: Delphi takes such an array's
  address implicitly and the callee fills it (the measured `GetTempFileName` case in Lattices). A by-value
  pointer "does not mean not written".

**Shape.** Only a bare identifier argument.

* `Obj.Get(X.F)` and `Obj.Get(A[0])` write part of a value, so they are not a whole-variable kill.
* An `out` argument is a KILL only if the call certainly runs: not on the right of `and`/`or`, not in a
  branch of an `if` expression. Otherwise the argument stays a use (`X := 1; if A and Get(X) then ..;
  Use(X)` keeps `X := 1` alive).
* Any other mention of the local in the same item makes the item an ordinary use (`Obj.Get(X, X)`,
  `Obj.Get(X); ` inside an expression that also names X).

**The same exemptions as the parents.** A captured local is skipped. `dead-store-before-out-arg` applies
`StoreHasEffectLivenessCannotSee` (nil-init before a `try`, `X := nil` on an interface). An opaque `with`
item keeps every local live. `by-value-arg-before-assignment` applies the managed-type skip, the and/or
left-to-right defs and the same-guard suppression (the may arm) of used-before-assignment. It never
fires on an item that already reports the local as a read, so no line carries both rules.

No store, no ref_types, a type with a homonym, a `with`, a helper of that method name: every method
answer is pmUnknown, so a fixture with no index reports only the bare same-unit `out` shapes.

### How

`TOutArgScan` walks one item and classifies each local: bare certain `out`, bare by-value on a method,
or anything else. `TOutAwareLiveness` is `TLiveness` plus "a purely-out local in this item is killed and
not generated". It lives in FlowChecks and runs only when the routine has a purely-out item, so the
ordinary routine pays one scan per item and no second solve.

Finding the stores: a store the second solve calls dead, that overwrite-before-read did not already
report, passing the same exemptions. It cannot double report: the set of stores already reported is
kept and skipped.

## 4. Assumptions the owner can reverse

1. **`out` means the callee does not read.** The compiler does not enforce this for unmanaged types, and
   a sloppy callee can read an `out` it was handed. The Delphi contract is taken at its word. If that is
   wrong in the owner's code the fix is to drop `dead-store-before-out-arg`.
2. **New ids over widening the parents.** `local-only-out-arg` could fold into write-only-local and
   `dead-store-before-out-arg` into overwrite-before-read; the by-value rule into used-before-assignment.
   Folding is a one-line id change in Emit plus catalog removal. Decide from the counts below.
3. **A dummy `out` local is reported, not exempted.** `Dict.TryGetValue(K, Dummy)` genuinely has a local
   nobody reads, but the signature may force it. It is why local-only-out-arg is info and OFF (section 6: 140 findings, mostly these). A later
   phase could skip it when the callee has an overload without the parameter.
4. **Severity of the by-value rule** follows the used-before-assignment ruling of 2026-08-26 (definite
   error, possible warning).
5. **Bare by-value callees are untouched:** they already report through used-before-assignment.

## 5. Phase 2 (not built; the owner decides after the counts)

* Fold what measures well into the parent rules, with a CHANGELOG note, default ON.
* If so, consider doing it properly in Lattices at the next bump (option A) and deleting the post-pass:
  a method's by-value mode as a real read also stops `Obj.Take(X)` from counting X as DEFINED, which hides
  later reads of it. The post-pass cannot see those later reads; it reports the first one only.
* Same-routine `var` analysis ("callee never reads this var") needs callee bodies and is out of scope.

## 6. Measurement

`lint-all --rule <id> --json`, one rule per run, on a copy of `Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite`
(244 MB, re-resolved 2026-11-06 10:47, has ref_types), 2026-11-06:

| rule | findings | read in source |
|---|---|---|
| `local-only-out-arg` | 140 | Names are mostly `dummy`, `ignored`, `discard`, `err`, `reason`: signature-forced. One read: `SplitGenericName(.., Bare, Params)` with `Params` unused. Noise-heavy, hence info |
| `dead-store-before-out-arg` | 47 | 7 of 7 sampled are true dead stores; most are defensive inits (`FormRout := ''`, 17 zero-inits in Storage.SQLite.pas:15629-15645) |
| `by-value-arg-before-assignment` | 0 | **Not proved on real code.** It fires on the fixture through `lint` and `lint-all`. Zero on one modern codebase says little: a legacy DB is the useful test (Micronite is over the lane's 1 GB copy limit; owed) |
| `write-only-local` (parent) | 7 | Same 7 from the 1.44.1 engine, so the parent did not move |

Cost: wall clock 435-577 s per run against 444 s for the 1.44.1 engine, on a saturated shared machine and
across a version gap. That does NOT measure the post-pass; the overhead is unmeasured. The rules have
no enable check in the checker, so the scan runs even when all three are OFF. If an A/B on a quiet
machine shows a cost, gate it on the enabled set.

Recommendation: keep all three OFF. `dead-store-before-out-arg` looks ready to fold into its parent if the
owner accepts defensive inits as findings; `local-only-out-arg` needs an exemption for signature-forced
dummies first.
