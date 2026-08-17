# INBOX -- `lint-all`'s project-wide phase dominates runtime on a large project

Found 2026-08-11 while measuring the ownership-scoping change on ORM3.
**Largely FIXED 2026-08-12** -- see "What it was" and "What is left" below.

## Status

ORM3-Micronite2027 `lint-all` **now completes in 732 s (12.2 min)**. Before, it
burned **8,705 CPU-seconds (2.4 h) and had not finished** when it was killed.
Findings are unchanged: the same 19,024, byte-identical report.

| phase | before | after |
|---|---|---|
| per-file scan (565 files) | 151.6 s | 151.6 s |
| **project-rules** | **did not finish** | **30.4 s** |
| doc-drift | 433.0 s | 454.9 s |
| class-metrics | 61.4 s | 60.9 s |
| duplicate-code | 10.2 s | 10.1 s |
| finalize+output | 21.2 s | 18.9 s |
| **TOTAL** | never completed | **732.3 s** |

YADF (8 files) went 77.8 s -> 34.6 s over the same changes, report identical.

## How it was found -- measure, do not guess

The note's own advice held. `lint-all` had no per-phase timing, so the first
change was to add one: **`DRAGLINT_PROFILE=1` now gives `lint-all` a per-phase
breakdown on stderr**, matching the indexer's. It announces each phase when it
OPENS and prints the cost when it CLOSES, streaming, precisely so that a run
that never terminates still names the phase it died in -- an end-of-run report
would have printed nothing at all for the case being diagnosed.

That pinned it to `project-rules`. Attributing it further needed no new code:
**`lint-project --rule <id>` already runs exactly one project rule**, so timing
one run per rule id gives per-rule cost. On YADF that produced the whole answer
in 40 seconds:

```
zzz-baseline-none                  0.52 s     god-class                0.57 s
circular-uses                      0.23 s     unused-public-symbol     0.33 s
enum-helper-separate-units         0.22 s     unused-private-member    1.26 s
repeated-type-switch               0.39 s     unused-unit-in-uses     32.21 s   <--
```

A per-rule breakdown is now built in too (same `DRAGLINT_PROFILE`), because the
ORM3 ranking turned out NOT to match YADF's and one run beats eight.

## What it was -- three rules, one shape

Every one of them asked the store a question **per occurrence** that it could
have asked **once per run**.

**1. `unused-unit-in-uses`** -- 32.2 s of YADF's 37.4 s pass; unbounded on ORM3.
For every reference in every file it called `FindSymbolsByExactName(Ref.NameText)`
plus a `GetFilePath` per matching symbol, i.e. O(all refs in the index) queries,
repeated per file. Identifiers recur constantly (`Create`, `Result`, `Free`), so
almost all of it was recomputation. Fixed with a run-level memo of name -> unit
stems, keyed on the raw name so a memo hit answers exactly what the query would.

**2. `unused-private-member` (447.8 s on ORM3) and 3. `unused-public-symbol`
(59.0 s)** -- both tested "is this symbol referenced at all?" as

```pascal
(Length(AStore.FindReferencesTo(Sym.Id)) = 0) and (Length(AStore.FindCallersByName(Sym.Name)) = 0)
```

Two queries per symbol, each MATERIALISING EVERY MATCHING ROW into a TReference
just to compare a length with zero -- and `refs.name_text` carries **no index**
(`FindCallersByName` says so in its own comment), so the second was a **full
table scan per symbol**. Replaced by two new store methods,
`GetReferencedSymbolIds` and `GetReferencedNamesLower`, one DISTINCT scan each,
loaded into sets once per run. The name set is lowercased because the query it
replaces matched `COLLATE NOCASE`, and that collation and Delphi's `LowerCase`
both fold ASCII only, so the two accept the same rows.

Result: `unused-private-member` 447.8 -> **0.01 s**, `unused-public-symbol`
59.0 -> **0.36 s**, `unused-unit-in-uses` unbounded -> **17.4 s**.

## What is left

1. **`doc-drift` is now the dominant phase: 454.9 s of 732.3 s on ORM3**, and
   21.6 s of YADF's 34.6 s -- it was simply invisible behind project-rules
   before. Not yet investigated. It is also the subject of
   `docs\INBOX-autodoc-not-idempotent-on-yadf.md`, so the two are worth looking
   at together.

   > ### RE-MEASURED 2026-08-16 (session 23) -- YADF IS NOT A PROXY FOR ORM3.
   >
   > Session 23's plan proposed profiling YADF as the cheap stand-in for ORM3,
   > on the reasoning that doc-drift "reproduces on YADF in ~40-second runs, so
   > it was never environment-blocked". **Measured, that reasoning does not
   > hold.** YADF's whole run is now 11.82 s, and the split is:
   >
   > ```
   >   per-file scan (9 files)            9.55 s     <-- 81%
   >   doc-drift                          1.30 s     <-- 11%
   >   project-rules                      0.62 s
   >   everything else                    0.35 s
   >   TOTAL                             11.82 s
   > ```
   >
   > doc-drift is **11% on YADF and 62% on ORM3**, because the two phases scale
   > on DIFFERENT quantities: per-file scan on file count and size (9 vs 565),
   > doc-drift on the number of DOCUMENTED DECLARATIONS (53 on YADF; ORM3's is
   > untold but far larger). A YADF profile therefore cannot attribute ORM3's
   > doc-drift cost, and this item **cannot be closed from YADF** -- the earlier
   > "21.6 s of YADF's 34.6 s" figure predates the 2026-08-12 fixes and no longer
   > describes the phase either.
   >
   > **What DOES transfer, and it is the actual optimisation target.** The
   > per-phase profiler now breaks doc-drift down internally, and on YADF:
   >
   > ```
   >   TDocDrift.Analyze                  1.08 s   (of doc-drift's 1.30 s)
   >     of which facts rebuild           1.04 s   <-- 80% of Analyze
   >     calls 0.35 | unresolved-name 0.21 | harvest 0.10 | resolved-callers 0.09
   > ```
   >
   > **The facts rebuild is 80% of Analyze**, and it is per-declaration work, so
   > it is the component that should scale to ORM3's 62%. If the ratio holds,
   > roughly 360 s of ORM3's 454.9 s is facts rebuild -- and `calls` is its
   > largest single contributor. That is a hypothesis from one small project, NOT
   > a measurement of ORM3, and it must be confirmed by a real ORM3 profile
   > (~12 min) before anybody optimises against it.
   >
   > So the item stays in the "needs a long run" bucket rather than moving to
   > Group A. It is not environment-blocked -- ORM3 completes in 12.2 min and the
   > profiler already emits everything needed -- it is simply not answerable from
   > a 12-second project.
   >
   > ### THE ORM3 RUN WAS DONE (2026-08-16, same session). It refutes the guess above.
   >
   > ```
   >   per-file scan (565 files)         89.17 s
   >   project-rules                     30.43 s
   >   class-metrics                     55.38 s
   >   doc-drift                        339.15 s     <-- 64% of the run
   >   duplicate-code                     9.33 s
   >   TOTAL                            529.71 s
   > ```
   >
   > doc-drift dominance is CONFIRMED (64%, and the run is now 529.7 s rather than
   > the 732.3 s recorded above -- other work has since sped it up). But the
   > attribution I extrapolated from YADF was **wrong**:
   >
   > ```
   >   DOC-DRIFT BREAKDOWN (4309 decl(s), 4309 with a live doc)
   >     of which facts rebuild         308.52 s
   >     unresolved-name   269.12 s   <-- 87% of the rebuild, 51% of the WHOLE RUN
   >     harvest 6.53 | covered-by 3.57 | raises 2.27 | resolved-callers 2.14
   >     wiring 4.20 | calls 0.99 | ancestry 0.38 | return-cases 0.03
   > ```
   >
   > On YADF, `calls` was the largest sub-item (0.35 s of 1.04 s) and
   > `unresolved-name` was 0.21 s, so I predicted `calls` would scale. **On ORM3
   > `calls` is 0.99 s and `unresolved-name` is 269.12 s.** The two swap places
   > entirely. This is the second time in one session that a YADF-sized
   > measurement predicted the wrong thing about ORM3, and it is worth stating
   > plainly: **YADF cannot attribute ORM3's doc-drift cost, not even in rank
   > order.**
   >
   > It also scales worse than linearly: 53 declarations -> 0.21 s versus 4,309
   > declarations -> 269.12 s, i.e. 81x the declarations for 1,280x the time.
   >
   > ### Where the cost is NOT
   >
   > `FindUnresolvedNameCallers` (`Storage.SQLite.pas:4071`) is called once per
   > declaration. Its name lookup is **already indexed and already using the
   > index** -- verified against the live ORM3 DB (533,244 refs rows):
   >
   > ```
   > EXPLAIN QUERY PLAN ... WHERE r.name_text = 'Create' COLLATE NOCASE
   >   SEARCH r USING INDEX idx_refs_name_nocase (name_text=?)
   >   SEARCH s USING INTEGER PRIMARY KEY (rowid=?) LEFT-JOIN
   >   SEARCH f USING INTEGER PRIMARY KEY (rowid=?)
   > ```
   >
   > **So item 3 below ("refs.name_text has no index") is STALE** -- the index
   > `idx_refs_name_nocase` exists and is chosen. Do not start there.
   >
   > ### Where to look next
   >
   > What remains in that query, and runs per declaration, is the **uses-reach
   > recursive CTE** (the transitive `unit_uses` closure that scopes callers to
   > files which can SEE the target) plus the receiver-type subquery. Those are
   > the only parts not covered by the index above, and a transitive closure
   > recomputed 4,309 times is the shape that matches the super-linear growth.
   >
   > **Measure before optimising** -- that discipline has now corrected three
   > guesses in this session. Time the query with and without the CTE on the live
   > ORM3 DB before changing anything. If the CTE is the cost, the fix is to
   > compute the reach set ONCE per run (or memoise per target file id) rather
   > than per declaration; the file-id set is stable for the whole lint pass.
   >
   > Prize: ~269 s of a 530 s run, i.e. roughly halving `lint-all` on ORM3.
   >
   > ### 2026-08-16, later: the CTE guess was WRONG TOO. It is the query PLAN.
   >
   > A dedicated investigation measured the CTE at **~6 s of the 269 s** -- removing
   > it entirely changes nothing material. So do not memoise it; that was my third
   > wrong guess in this session and it is recorded here so it is not tried again.
   >
   > **The decisive observation.** The IDENTICAL SQL replayed against the SAME DB
   > through an external SQLite runs **~0.74 ms/call**, against **~62 ms/call**
   > in-process. A consistent ~80x gap that scales with row volume is a PLAN
   > difference, not per-call overhead. Replayed variants:
   >
   > | variant | ms/call | x4,309 |
   > |---|---|---|
   > | observed in-process (GBUnresolved) | 62.5 | 269.1 s |
   > | full query, 200 real declarations | 0.74 | 3.2 s |
   > | forced to drive `refs` by `idx_refs_file` over the reach set | 28.2 | **121.5 s** |
   >
   > Only that last plan reaches the observed magnitude. **Two things let a planner
   > choose it, both verified:** no DB in this tree has `sqlite_stat1` (nothing has
   > ever run ANALYZE, so selectivity is guessed), and drag-lint loads
   > **sqlite3.dll dynamically**, so the engine deciding this is whatever is on
   > PATH rather than a version this repo pins.
   >
   > ### What was shipped, and what it actually achieved -- SAY THE SECOND PART
   >
   > * a unary `+` **plan pin** on the reach predicate (`Storage.SQLite.pas`,
   >   `ScopeP`). Semantically inert; SQLite will not use an index on `+expr`, so
   >   that term can no longer be chosen as the driver.
   > * a bounded **ANALYZE** (`analysis_limit=400`) in `Migrate`, guarded on
   >   `sqlite_stat1` being absent.
   >
   > **Measured with the plan pin alone (stats still absent): 269.12 s -> 258.90 s,
   > TOTAL 529.71 s -> 510.03 s. About 4%, i.e. within noise.** The pin is harmless
   > but has NOT demonstrated a win.
   >
   > `sqlite_stat1` now EXISTS on the ORM3 DB (a completed reindex ran the
   > ANALYZE), so the with-statistics measurement is the obvious next step and had
   > not produced a clean number when this was written -- an orphaned reindex
   > process held the DB and the profiling run died with "database is locked".
   > **Re-run it before believing anything about ANALYZE.**
   >
   > ### RESULT: statistics did NOT fix it either. Both levers together buy ~4%.
   >
   > | run | unresolved-name | TOTAL |
   > |---|---|---|
   > | baseline | 269.12 s | 529.71 s |
   > | plan pin only (no `sqlite_stat1`) | 258.90 s | 510.03 s |
   > | **plan pin + `sqlite_stat1` present** | **257.48 s** | 518.21 s |
   >
   > `sqlite_stat1` was confirmed present for the third run (a completed reindex
   > ran the bounded ANALYZE). It moved `unresolved-name` by 1.4 s. **So the
   > "missing statistics let the planner pick a bad join order" hypothesis is not
   > supported by measurement**, and neither is the plan pin. Both are kept -- the
   > `+` is inert and statistics are ordinary hygiene -- but NEITHER is a fix, and
   > this note must not be read as though the problem were solved.
   >
   > ### What is still unexplained, and the ONE experiment that would settle it
   >
   > The ~80x in-process/external gap is measured and real, but every explanation
   > tried for it has now failed. Before another fix is attempted, close the gap
   > between the two measurements themselves -- they may simply not be comparing
   > the same thing (different parameter values, a warm page cache on the replay
   > side, or an extra predicate the replay dropped).
   >
   > **Do this first, in-process, and nothing else until it is done:**
   > 1. log `sqlite3_libversion()` from the loaded DLL, so the engine is known
   >    rather than assumed;
   > 2. run `EXPLAIN QUERY PLAN` for the EXACT assembled SQL **through FConn**,
   >    not an external shell -- this is the only way to see the plan the product
   >    actually gets;
   > 3. time ONE call in-process with the same bound parameters the replay used.
   >
   > If the in-process plan matches the external one and the timing still differs,
   > the cost is not in the plan at all and the search should move to the FireDAC
   > layer (per-call `TFDQuery.Create`, parameter binding, or row marshalling) --
   > which the subagent measured as "a few ms/call at most", so that too would
   > need re-measuring rather than assuming.
   >
   > ### 2026-08-16 (session 24): the PREMISE was wrong. The bucket does not time one call.
   >
   > Before running the prescribed in-process experiment, I re-read the code that
   > the bucket wraps. **`GBUnresolved` is not a timer around
   > `FindUnresolvedNameCallers`.** The window is `TB0` (`Doc.Facts.pas:1813`) to
   > `Inc(GBUnresolved, ...)` (`:1939`), and inside it are also:
   >
   > * **`LeafNameIsUnambiguous`** (`:1872`) -- the ambiguity gate, which calls
   >   `AStore.FindSymbolsByExactName(<leaf>)`. Short-circuit `or`, so it runs
   >   whenever the symbol has NO resolved caller, which on a large project is the
   >   common case.
   > * **`LeafNameNotAmbiguous`** (`:1904`) -- the same query again, once per extra
   >   store.
   > * `AddDistinct` over every returned row, twice.
   >
   > Every measurement above -- mine and the previous sessions' -- compared an
   > external replay of `FindUnresolvedNameCallers` against a timer that was never
   > only measuring it. **That alone could account for the ~80x**, and it must be
   > ruled out before any more plan work.
   >
   > ### What was measured this session, externally, against the live ORM3 DB
   >
   > 155 real documented routine declarations, parameters taken from the DB rather
   > than invented. Python's sqlite3 (3.50.4), read-only, `x4309` scaled to the
   > declaration count:
   >
   > | shape | ms/call | x4309 |
   > |---|---|---|
   > | `Facts.pas:1875` -- scope=file, owner=set (the site everyone assumed) | 0.78 | 3.4 s |
   > | `Facts.pas:1921` -- scope=0, owner=set (extra-store fan-out) | 0.89 | 3.8 s |
   > | `SymbolFacts.pas:3035` -- scope=0, owner='' (**all defaults**) | 0.91 | 3.9 s |
   > | `FindSymbolsByExactName` (the ambiguity gate's query) | 0.31 | 1.3 s |
   >
   > **Two more explanations are therefore DEAD:**
   >
   > * **"the replay dropped a predicate"** -- specifically
   >   `AND r.id NOT IN (SELECT ref_id FROM call_edges)`, which looked like the
   >   ideal suspect (an uncorrelated subquery SQLite materialises into an
   >   ephemeral index once per execution, over 32,983 rows, 4,309 times).
   >   Measured: **0.73 ms/call WITH it, 1.31 ms/call WITHOUT it** -- it is a
   >   filter that makes the query *faster* by cutting rows, and the replay
   >   plainly carried it. `NOT EXISTS` against `idx_call_edges_ref` is 0.99, i.e.
   >   slightly worse. Do not rewrite it.
   > * **"different bound parameters"** -- all three real call shapes were
   >   replayed with their real arguments and land within 0.13 ms of each other.
   >
   > **SQLite serves every query in that window in under 1 ms.** So the 62 ms/call
   > is not in SQLite at all: not the plan, not the CTE, not the statistics, not
   > the predicate set, not the parameters. That is the conclusion the prescribed
   > step 3 was designed to reach, reached from the outside for all four shapes.
   >
   > ### The concrete candidate the code review turned up
   >
   > `LeafNameIsUnambiguous` needs one boolean: "is there more than one call
   > target with this leaf name, or any `local_var`/`param`/`field` sharing it?"
   > It answers by calling `FindSymbolsByExactName`, i.e. `SELECT *`, and
   > **materialising every row into a full `TSymbol`** -- then counting to 2 and
   > throwing the rest away. Measured row counts in the sample: **495 rows for
   > `Create`**, 146 for `Save`, 141 for `Initialize`; 3,341 rows over 155 calls.
   >
   > This is the SAME anti-pattern this note already records fixing twice
   > (`unused-private-member` / `unused-public-symbol`: "MATERIALISING EVERY
   > MATCHING ROW into a TReference just to compare a length with zero"). Cheap in
   > SQLite, expensive in FireDAC, and invisible to an EXPLAIN QUERY PLAN.
   >
   > **NOT YET A MEASURED FIX -- state it as the hypothesis it is.** What is
   > measured is the row volume and that SQLite is not the cost. What is NOT
   > measured is FireDAC's per-row marshalling cost in this process, and a bounded
   > `COUNT`+`EXISTS` reformulation measured only **1.0 s vs 1.3 s in SQLite**, so
   > the entire win would have to come from rows never crossing the FireDAC
   > boundary. Instrument first:
   >
   > 1. split the `GBUnresolved` window into its parts (gate / primary call /
   >    extra stores / AddDistinct) -- one counter each, and a CALL COUNT
   >    alongside each timer, since "once per declaration" has now been assumed
   >    once and been wrong;
   > 2. only then decide whether the gate, the query, or the marshalling owns it.
   >
   > Do NOT ship a `COUNT`-based gate on the strength of the paragraph above.
   >
   > ### MEASURED, AND IT IS NONE OF THE ABOVE. `OverloadArityTag` is 45% of the run.
   >
   > The split timer was built and run on ORM3. It settles the whole thing:
   >
   > ```
   >   unresolved-name                    255.26 s
   >     ambiguity-gate                     0.01 s (   49 call(s), 0.30 ms/call)
   >     primary-query                      2.41 s ( 4293 call(s), 0.56 ms/call)
   >     extra-stores                       0.00 s (    0 call(s))
   >     rest-of-window                   252.83 s
   >   overload-arity-tag                 255.48 s (24286 call(s), 10.52 ms/call)
   >   TOTAL                              572.31 s
   > ```
   >
   > **`FindUnresolvedNameCallers` costs 2.41 s, not 269.** Its in-process
   > 0.56 ms/call AGREES with the external replay's 0.78 ms/call. **The ~80x gap
   > never existed.** Three sessions of plan work -- the CTE hypothesis, the
   > missing-index hypothesis, the missing-statistics hypothesis, the unary `+`
   > plan pin, the bounded ANALYZE -- were all aimed at a query that costs two and
   > a half seconds. The timer was measuring something else the whole time. My own
   > ambiguity-gate hypothesis, written directly above, is refuted too: 49 calls,
   > 0.01 s.
   >
   > **The cost is `OverloadArityTag`** (`Doc.Facts.pas`), called from `ToFactRef`
   > once per rendered caller row. It is charged to BOTH `resolved-callers` and
   > `rest-of-window`, which is why its 255.48 s slightly exceeds the
   > `unresolved-name` bucket that contains most of it.
   >
   > It is expensive per call *and* called often: **10.52 ms x 24,286**. Per call
   > it makes two store calls, and the second is
   > `FindAllChildSymbols(Sym.ParentId)` -- **materialising every sibling of the
   > parent class into a full `TSymbol`** so it can count how many share the
   > symbol's name. ORM3's forms and data modules have hundreds of members each,
   > and this is redone for every caller row of every declaration.
   >
   > So the anti-pattern this note already records fixing twice
   > (`unused-private-member` / `unused-public-symbol`: materialise every row to
   > compare a count) was present a third time, one layer up, in the renderer --
   > and it is the single largest cost in `lint-all`.
   >
   > ### What to do, and the gate on it
   >
   > The tag is a PURE FUNCTION of (store, symbol id), and caller rows repeat the
   > same enclosing routines constantly -- 24,286 calls over far fewer distinct
   > ids. A run-level memo is the smallest change with the largest constant
   > factor. A store-side bounded `COUNT` would also help and is the better
   > long-term shape, but it does not remove the repetition.
   >
   > **The memo key must include the STORE, not just the id.** Symbol ids are
   > per-DB, so a bare id key would collide across a multi-DB run.
   >
   > Related and NOT fixed: in the extra-store loop, `ToFactRef` closes over the
   > PRIMARY `AStore` while `RC.EnclosingSymbolId` came from the EXTRA store, so
   > `OverloadArityTag` is already being handed an id from the wrong DB there.
   > That is a pre-existing correctness bug, separate from the performance one,
   > and it needs its own fix and its own test.
   >
   > **THE GATE, and it is the same one this note used for the 2026-08-12 work:**
   > the report must stay byte-identical. Findings are the product; a 45% saving
   > that changes one line of output is not a win, it is a regression with a
   > stopwatch attached.
   >
   > `seealso` at **17.46 s** is now the second-largest doc-drift sub-item and has
   > never been looked at.
   >
   > ### SHIPPED. 572 s -> 320 s, and the report is byte-identical.
   >
   > A run-level memo on `OverloadArityTag`, keyed on **(store pointer, symbol
   > id)** -- ids are per-DB, so a bare id key would return one DB's answer for
   > another DB's symbol in a multi-DB run. Same 24,286 calls; the second and
   > later asks for an id now cost a dictionary probe instead of
   > `GetSymbolById` + `FindAllChildSymbols`.
   >
   > | | before | after |
   > |---|---|---|
   > | overload-arity-tag | 255.48 s (10.52 ms/call) | **8.18 s (0.34 ms/call)** |
   > | unresolved-name | 255.26 s | **10.19 s** |
   > | resolved-callers | 5.42 s | 1.89 s |
   > | doc-drift | 327.65 s | **78.44 s** |
   > | **TOTAL** | **572.31 s** | **320.02 s** |
   >
   > **44% off the whole `lint-all`, 252 seconds.**
   >
   > **THE GATE WAS MET AND CHECKED, not assumed:** stdout is byte-identical --
   > same SHA256, 2,161,951 bytes, the same 14,764 findings (32 error / 2,156
   > warning / 12,173 info / 403 hint). The earlier instrumentation-only run
   > matched the pre-instrumentation run byte-for-byte too, so the timers
   > themselves changed nothing either.
   >
   > Not invalidated anywhere, and that is safe only because nothing in the
   > doc-facts path writes to a store. A future caller that mutates a store
   > mid-run must clear the memo; the declaration says so.
   >
   > ### What this item is now
   >
   > The headline is discharged. What remains is smaller and each piece is
   > independent:
   >
   > * **`per-file scan` is now the dominant phase** at 141.26 s of 320.02 s
   >   (44%), simply because everything around it shrank. Never profiled.
   > * **`class-metrics` 56.10 s** -- second, also never looked at.
   > * **`seealso` 17.57 s** -- the largest remaining doc-drift sub-item.
   > * **`unused-unit-in-uses`** (item 2 below) still ~17 s.
   > * The cross-DB `ToFactRef` id bug noted above is still open, and is a
   >   CORRECTNESS issue rather than a performance one.
   >
   > And the lesson worth keeping, because it cost three sessions: **the profiler
   > attributed a cost to the wrong thing, and every hypothesis built on that
   > attribution was doomed regardless of how carefully it was tested.** Four
   > explanations were measured and killed (CTE, missing index, missing
   > statistics, the `NOT IN` predicate) before anyone checked what the timer
   > actually enclosed. A timer with no CALL COUNT beside it hid it: "once per
   > declaration" was assumed for three sessions and the real figure was 24,286
   > calls through a different function.
2. **`unused-unit-in-uses` is still 17.4 s** -- the memo removed the repetition
   but the remaining cost is one `FindSymbolsByExactName` per DISTINCT name,
   each an indexed lookup returning every symbol with that name.
3. ~~**`refs.name_text` has no index.**~~ **STALE -- the index exists and is used.**
   Verified 2026-08-16 against the live ORM3 DB: `idx_refs_name_nocase ON
   refs(name_text COLLATE NOCASE)` is present, and `EXPLAIN QUERY PLAN` picks it
   (`SEARCH r USING INDEX idx_refs_name_nocase`). It is created by `TryExec` in
   `Migrate`, which runs on every open, so any DB self-heals. Nothing to do.
4. The pre-existing quadratic `Findings := Findings + <rule results>`
   accumulation in `DoLintAll` was NOT touched. It never showed up: the
   ownership filter over all 54,245 raw findings costs 0.03 s.

## Reproducing

```
set DRAGLINT_PROFILE=1
cd C:\Projects\Delphi-RAG-lint\third_party\dll-win64
drag-lint lint-all --db C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite --quiet
```

Read **stderr**: the profile and the status lines are unbuffered there, whereas
stdout is block-buffered when redirected and shows nothing until the process exits.
