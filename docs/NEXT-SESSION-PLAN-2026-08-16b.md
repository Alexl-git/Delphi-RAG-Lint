# What is left -- written end of session 22 (2026-08-16)

Supersedes `NEXT-SESSION-PLAN-2026-08-16.md`, whose three groups are now either
finished, reviewed, or planned. **INBOX 60 -> 23 -> 12 open.**

---

## RELEASE GATE

`main` is ~85 commits ahead of `origin/main` deliberately. Owner ruling:
*"To github we'll publish new release only after all 11+1 are done."*
**Group A is now finished** (its last item, the Loader2019 leak, was fixed on
owner instruction). The gate is therefore the owner's to lift; nothing has been
pushed.

---

## Where the four consumer projects stand

Measured end of session, after the two false-positive fixes below.

| project | start of session 22 | now | what remains |
|---|---|---|---|
| YADF | 5 | **4** | 2 `unused-public-symbol` (shared-unit hints), 1 TODO comment, 1 unit-too-large |
| YADFOT | 5 | **4** | identical set -- it shares the same units |
| YADFSetup | 8 | **7** | 5 `unused-public-symbol`, 1 TODO comment, 1 unit-too-large |
| DataCopy | 43 | **43** | see the breakdown below |
| **total** | **61** | **58** | |

**Zero errors and zero warnings in all three YADF projects.** Everything left
there is `info`/`hint`.

### What is actually left, and why it is not simply "fixable"

* **`unused-public-symbol` (12 of the 58)** -- these are already honest. The
  message says *"Its unit is shared with YADF, YADFOT, YADFSetup -- check there
  before treating it as dead."* They are `hint` severity for exactly that
  reason. Closing them properly needs **cross-project reachability**: a symbol
  referenced in ANY sibling project that shares the unit should not be reported.
  That is rule-hardening item 9 (multi-DB reachability) and is the single
  biggest remaining win for these four projects.
* **`unit-too-large`** (YADF.Layout.pas, 5620 lines) -- a true positive and a
  real refactor, not a lint fix.
* **`compiler-magic-comments`** -- a genuine TODO in `YADF.Guard.pas`.
* **DataCopy's 43** are dominated by `unused-parameter` (5), `local-field-prefix`
  (5), `sleep-in-vcl` (3), `unused-public-symbol` (3), `const-casing` (3). The
  two `field-name-prefix` findings were checked and are **true positives** (real
  `private` fields), not the DFM heuristic that item 10 describes.

**LoopZero was not run as a loop.** The reindex/autodoc/lint/triage cycle needs
`document --apply` to write into the consumer repos, and the standing
instruction is *"consumer files will wait"*. What was done instead is the
measurement half: current counts, per-rule breakdown, and the two engine fixes
that removed real false positives. Running the writing half is an owner call.

---

## The rule-hardening plan is substantially STALE -- re-measured

`INBOX-rule-hardening-plan-2026-08-13.md` is the owner's own prioritised table.
Four of its rows were re-measured this session and **three no longer exist**:

| row | plan said | measured 2026-08-16 |
|---|---|---|
| 1 `sql-injection-concat` | 1+ findings | **0.** Already tightened on 2026-08-13 -- the rule now requires an anchored leading SQL verb AND a clause keyword, exactly what the plan proposed. Nothing to do. |
| 3 `used-before-assignment` | 7, cause = `out` arg read as a READ | **0 in all four projects.** Both stated causes are dead: the out-arg theory was disproven and reverted, and the `and`/`or` ordering case is fixed by `CollectAndOrLeftDefs`. **See below -- the live shape is a third one nobody has written down.** |
| 2 `object-leak` (A) | ~15, cause = guard is the next statement | **FIXED this session, 9 -> 0 on the self-index** -- but the cause was NOT the next-statement shape (already handled). See below. |
| 10 `field-name-prefix` | 6, DFM heuristic | **0 false positives.** The rule was visibility-scoped by owner ruling 2026-08-13; DataCopy's 2 are real private fields. |

**Do not work rows 1, 3 or 10 as written.** Re-measure any remaining row before
coding it -- that is now 7 notes in two sessions whose stated mechanism was not
the live one.

### `used-before-assignment` needs a NEW note before any code

0 findings in the four consumer projects, but **39 on the self-index**, all
hedged `[info] ... may be used`. A sample of five are all the same previously
undocumented shape: **boolean-flag-correlated guards.**

```pascal
if Profiled then TMark := TStopwatch.GetTimeStamp;
...
if Profiled then Inc(AccRes, TStopwatch.GetTimeStamp - TMark);
```

The assignment and the read are guarded by the same flag, so the read is safe,
but the flow analysis cannot see the correlation. Same shape at
`Core.Indexer.pas:584-593` (`Best`/`HasBest`), `Refactor.TextEdit.pas:603-611`
(`LastInSection`/`HaveLast`), `AstChecks.pas:2843-2848` (`Call`/`HaveCall`).

A real fix needs predicate correlation (assignment and read under the same
condition, flag not mutated between) and is M-L effort with genuine risk.
**Accepting them as hedged info findings on a correct idiom is also a legitimate
owner ruling** -- they are not wrong so much as unprovable cheaply.

---

## Group B -- what is done and what is next

**Done this session:** the scoped-resolve A/B equivalence harness
(`run_scoped_resolve_equivalence.ps1`), which turned two landed fixes from
"believed" into row-identical proven and closed `indexer-livelock`. Also the
index-path size guard, and the fingerprint-commit correctness fix.

**Next, in this order** (a plan with file:line anchors already exists; ask for it
rather than re-deriving):

1. **Walk progress `n/total` + ETA** (~90 min). `ReportProgress` prints per-file
   only, so an hours-long library reindex is indistinguishable from a hang. Emit
   to **stderr**, not stdout -- several suites regex the existing stdout lines.
   Positive control: total must equal the walk's ADMITTED file count (3, not 4,
   with one file excluded by filter), which is the one way a pre-count silently
   lies.
2. **Per-file resume** (`files.indexed_at_fingerprint`, ~120 min). Highest risk
   in the batch -- a wrong skip silently keeps stale parses, which is exactly the
   bug fixed this morning. Stamp INSIDE the per-file transaction, never outside.
3. **CodeLens LRU cap** (~60 min). Pure `TDictionary` + `TCriticalSection`, no
   IDE dependencies, so the unit and its console test can land now; only the BPL
   rebuild needs an IDE-closed window. Positive control: assert an entry is
   RETRIEVABLE before eviction -- a cache that stores nothing passes any
   `count <= cap` check.
4. **Profile doc-drift on YADF** (~40 min, measurement only).
   `lint-all-project-wide-phase` should move to Group A: its dominant phase
   reproduces in 40-second YADF runs and was never environment-blocked.

**Still genuinely blocked:** the Win32 library rebuild abort (root cause unknown;
the per-file flush now makes the next failure diagnosable -- launch it unattended
and harvest), narrowing the added-type resolve fallback (a soundness redesign
that must not precede the equivalence harness), and the 25x figure itself
(O(child-table rows); no small fixture can exhibit it).

---

## Group C -- see `PLAN-GROUP-C-2026-08-16.md`

Unchanged except that its first item, rule-hardening, is now known to be mostly
already done (above). The remaining Group C work of real value:

* **`exception-class-unit` Stage 1** -- measured and unblocked (64 distinct
  messages on ORM3, not the 400 that would have killed it). **BUT:** the note's
  Stage 1 wants the finding to name which existing class fits, and `TLinter` has
  **no symbol store** -- it is purely syntactic. Wiring a store into the linter,
  or moving this rule to the store-aware `lint-all` path, is the real cost and
  was not attempted. Scope it before promising it.
* **`converter-editor-phase-g` finding 2.11** (strong type aliases `T = type X`
  never indexed) -- HIGH, and the same defect class as the already-fixed 2.1.
* **`yadf-share-review-marker-hash`** -- freeze `NormalizeLine` (249 markers
  across three repos now), then ship a VERIFY-only helper that includes
  `HashWindow`.

---

## Standing traps re-confirmed this session

* **A positive control is not optional.** Twice today a "the bad thing stopped"
  assertion passed with the fix disabled: the stale-resolve guard (only "data
  survived" discriminated) and the scoped A/B (both runs took the whole-DB path).
* **Fixture size can silently defeat a test.** `ScopedResolveIsSound` declines
  once the changed set reaches a third of the corpus, so a 3-file fixture with
  one edit compared whole-DB against whole-DB and passed.
* **`document --qname X --json` never contains the block text** -- only a
  summary. Asserting "output lacks 'Called from'" against it is vacuous.
* **PowerShell `(...).Count` is `$null`, not 0**, when a `Where-Object` matches
  nothing. Wrap in `@()`.
