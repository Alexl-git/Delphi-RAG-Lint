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
