# PLAN -- finish the indexer performance work, then make concurrency safe

Written 2026-08-11 for the NEXT session. Everything below is measured, not assumed;
where something is a guess it says so.

## Where we already are (all committed, all verified)

Three algorithmic fixes landed, each the same shape -- per-ROUTINE work that only
changes per FILE or per CLASS:

| fix | what it was doing | effect |
|---|---|---|
| `ResolveEnclosingSymbolId` | scanned every symbol in the file, per reference | refs phase -> 3.6 s |
| `CfgFindProcs` (in `Analyze`) | walked the WHOLE AST once per routine | facts 104.2 -> 26.8 s |
| `FindAllChildSymbols(ParentId)` | a DB round-trip per routine for the same class | folded into the above |

**DevExpress ExpressBars, 83 files: 670 s -> 147 s = 4.6x.** Extrapolated, win32's
4.86 h full rebuild becomes roughly **63 minutes**.

**Verified equivalent, not just faster:** 219,684 refs compared on
`enclosing_symbol_id` -> 0 disagreements; 14,253 `symbol_facts` rows compared across
all 10 fact fields -> 0 disagreements (and none blank); every aggregate identical;
176/176 fixture tests pass. The comparison harness is
`C:\TEMP\claude\cmpdb.py` + `cmpfacts.py` -- **re-run both after every change below.**

A per-phase profiler shipped with it: `DRAGLINT_PROFILE=1` prints a breakdown to
stderr at exit. Opt-in, so normal runs are unchanged.

## Task 1 -- find the missing 82 seconds

**Re-measure before chasing this.** The 82 s was computed by subtracting the
per-phase timers from the wall clock, and those timers only ever covered
`TIndexer.IndexFile`. The four resolve passes run OUTSIDE them and were, at the
time, both unmeasured and unbounded -- on a large database they are minutes.
Task 2 put a timer on all four, so the arithmetic that produced "82 s" needs
redoing with those numbers subtracted first; what is left may be much smaller
than 82 s, or a different shape entirely.

Current profile of the 147 s run: accounted 64.7 s, **wall 147 s**. The largest
single bucket is now the 82 s that no timer covers.

```
read/pre 0.25  parse 11.49  open-tx 0.05  doc-scan 0.06  symbols 7.22
refs 3.64  uses/di 0.03  literals 1.37  facts 26.79  commit 13.84   TOTAL 64.74
```

**Step 1.** Wrap the whole of `TIndexer.IndexFile` in one timer (`GProfFile`) and add
a `WalkAndIndex` timer. That splits the 82 s into "inside IndexFile but between my
phases" vs "outside IndexFile entirely" and immediately halves the search space.

**Candidates, in the order worth checking:**
1. `TAstParseCache.Get(AFilePath)` -- the facts pass parses each file a SECOND time
   (the indexer already parsed it). If the cache is per-file-single-entry, confirm it
   is actually hitting. Feeding the indexer's own tree in would remove a whole parse.
2. The `finally` blocks -- `DocRegions` (a `TList<TDocCommentRegion>`) and `IdxToId`
   free per file; large records with managed fields are not free to release.
3. `WalkAndIndex` -- glob matching + the ignore-file stack, per file.
4. Final `--prune` and the close-time WAL checkpoint.

**Do not guess.** Three hypotheses about this engine's cost (fsync, FK-cascade scans,
FTS5 trigram deletes) were each measured and each was wrong; the profiler found the
real answer in one run.

## Task 2 -- DONE (2026-08-11, later the same day). Results below, then the original brief.

**Measured on the 2.09 GB `library-Win32` index** (7,412 files, 2,240,573 symbols,
3,321,103 refs, 541,354 call edges):

| | before | after |
|---|---|---|
| index 1 changed file | 2,276.7 s | **38.7 s** |
| -- of which the call pass | 2,252.8 s | 17.0 s |
| re-index, NOTHING changed | 2,276.7 s | **20.9 s** |

**The first thing that had to happen was a timer.** All four passes were silent
and untimed, so nobody had ever let one finish -- the earlier "livelock" reading
came from sampling a 90-second window. With one line printed per pass the answer
took a single run:

```
unit-uses  1.4s      ancestry  4.5s      helpers  13.4s      calls  2252.8s
```

Three of the four cost 19 s combined. `ResolveCallTargets` was the whole thing:
it clears every edge, builds name maps over 2.24M symbols (only 6.4 s -- not the
problem) and then streams **1,109,614** call-site refs, issuing an
`UPDATE refs SET receiver_text` for each. ~2 ms per ref is the entire cost.

**What shipped:**

* `TSQLiteSymbolStore` records what a run actually changed -- file ids from
  `OpenFileTx`, symbol names REMOVED (read out before the delete) and ADDED (in
  `UpsertSymbol`).
* `ResolveCallTargets` re-resolves only the affected refs. The soundness argument
  is in the code: the two FK cascades (`call_edges.ref_id -> refs`,
  `call_edges.target_symbol_id -> symbols`) already delete exactly the edges a
  re-index invalidates, so the affected set is "refs in rewritten files, plus
  refs naming a symbol added or removed".
* Four fallbacks to the whole database: any delete outside `OpenFileTx`
  (`ClearAllFiles` / prune / evict), extra library stores, a run covering a third
  or more of the corpus (latched during accumulation, so a full `--recompile`
  pays for the first third and nothing after), and the one channel a name-keyed
  set cannot catch -- a call resolving through a TYPE whose declaration moved
  while the method name is untouched, closed by requiring that the type names a
  run removed are exactly the ones it put back.
* `DRAGLINT_NO_SCOPED_RESOLVE=1` forces the old whole-corpus pass.

**Verified**: `cmpcalls_sql.py` (ATTACH + EXCEPT both directions) over 3.32M refs
and 541,354 call edges -> **0 disagreements**, plus five mutation shapes on a
fresh 168-file index (unchanged file; cross-unit rename; call target removed, 67
edges dropped; call target restored, 67 edges reappearing in files never
re-indexed; and both fallback guards).

**The regression the battery caught, and the rule it taught.** The first cut
skipped all four passes when nothing changed. That broke
`tests/autotest/run_unit_uses_targets.ps1`, which poisons
`unit_uses.target_file_id` with raw SQL and requires the next plain `index` to
repair it -- these passes are not only an incremental update, they RECOMPUTE, and
that is what makes a re-index a repair. Only the call pass is guarded now; the
other three stay unconditional because together they cost ~21 s even on the 2 GB
index. **A cheap pass that is also a repair mechanism should not be guarded at
all.**

**Still open here:** `refs.receiver_text` is re-derived from the file on DISK at
the ref's STORED line/col, so a whole-corpus pass over an index whose sources have
moved overwrites good receivers with garbage -- 11,008 receivers and 464 edges
destroyed in a measured run. Filed as
`docs/INBOX-whole-db-resolve-degrades-a-stale-index.md`; the cheapest fix is to
re-derive receivers only for files this run re-indexed, which would also delete
most of what the pass writes.

## Task 2 (original brief) -- make the four resolve passes incremental

**Superseded the "livelock" theory. There is no livelock.** After the file walk,
every `index` run does four passes over the WHOLE database
(`CLI.pas:2727-2733`, and the same block at 1900, 2681, 15812):

```pascal
Store.ResolveUnitUseTargets;
Store.ResolveAncestry;
Store.ResolveHelpers;
Store.ResolveCallTargets;
```

Their cost scales with TOTAL index size, not with the files just indexed. Indexing 83
files into a 2.1 GB DB pays four full-corpus resolutions.

**Measured** (two independent processes, 2.1 GB DB copies, ExpressBars 83 files):
all 83 files indexed in ~5 min, writes then stop dead at 2,461 MB while CPU stays at
~0.8 cores; over the next 90 s each process read **+15.2 MB / 1,907 read-ops and wrote
0 bytes**. Not hung -- scanning the corpus with nothing to show for it.

This also explains the original "win64 hangs with 0 files indexed": `--recompile`
skipped every up-to-date file silently, printed nothing, and went straight into these
passes. The correlation with win32 running concurrently was coincidence.

**Do:**
1. Scope each pass to rows affected by the just-indexed file set. This is the single
   highest-value indexer change remaining.
2. If a pass genuinely cannot be scoped, run it ONCE at the end of `index --all`
   rather than once per section, and offer `--no-resolve` for chained runs.
3. **Make them print.** A multi-minute silent phase is indistinguishable from a hang;
   that ambiguity is what produced the wrong diagnosis. One line per pass with row
   counts.

## Task 2b -- old (WRONG) livelock theory, kept so it is not re-investigated

**Signature:** a full core busy, **0.0 MB/min read AND write**, no stdout, no error,
forever. Not memory (349 MB, 9.9 GB free), not corruption (`quick_check` ok,
`foreign_key_check` clean), not a DB lock (separate files; a lock wait burns ~0% CPU).

**Correlation:** win64 hung only ever while a win32 section ran alongside; win32 never
hung, in either mode. Reproduce with:

```
drag-lint index --all --only Library --platform win32 --rebuild    (leave running)
drag-lint index --all --only Library --platform win64 --rebuild    (hangs)
```

**First experiment, because it is one line:** the hung process sat at exactly
4,096 MB virtual, and each write connection sets `PRAGMA mmap_size = 1073741824`
(1 GB) against a ~2 GB DB. Set `mmap_size = 0` (or 256 MB) in
`Storage.SQLite.pas:2506` and re-run the two-platform build. If it stops hanging,
that is the answer and the fix is a smaller/adaptive mmap.

**If that is not it:** attach a debugger or add a watchdog thread that dumps the main
thread's stack after N seconds without progress. The livelock is silent today, which
is most of why it cost so much time.

**Do not start Task 3 until this is understood.** Adding threads on top of an
unexplained concurrency defect makes it far harder to diagnose, and the engine
already demonstrates one at process level.

## Task 3 -- threading, once 1 and 2 are done

**Do NOT parallelise "the parser."** Measured: parsing is ~8% of the current run and
SQLite is ~0.1% (it inserts the same 280,695 rows in 0.90 s that the pipeline takes
147 s to produce). The parallel target is the **facts pass** -- per-routine,
independent, pure CPU, and still the largest measured phase.

**Shape:** N worker threads analysing routines, ONE writer. All DB writes stay on the
existing single-threaded path.

**Three known blockers, all documented in the code already:**
1. `GProcsCache` and `GKidsCache` (the two caches added this session) are
   **single-entry and NOT thread-safe** -- by design, matching the existing shared
   parse cache. Each worker needs its own, or key them per thread.
2. `TAstParseCache` is shared and not thread-safe (stated in `CloneChecks`' banner).
3. **`Analyze` reads the database** -- `FindAllChildSymbols`, `FindSymbolsByExactName`,
   `GetSymbolById`, `GetTransitiveAncestors`, `FindResolvedCallers`,
   `FindDiBindingsForImpl`, `FindOrmDatasetLinks`. A single SQLite connection cannot
   be used concurrently. Workers need their own read-only connections, and those must
   see the *in-flight* transaction's rows -- which they cannot, because the file's
   symbols are written in an open transaction. **Resolve this before writing any
   threading code**: either hoist the store lookups out of the parallel region and
   pre-resolve them, or commit symbols before the facts pass.

Blocker 3 is the real design question; 1 and 2 are mechanical.

**Sizing:** the box has 9 logical CPUs and the current run uses ~0.9 of one, with the
disk at 3-5%. Headroom is real. But note that two concurrent PROCESSES did not double
throughput in testing (win32 fell from 84 to 28 files/min when win64 ran), so measure
before assuming linear scaling.

## Can we run Win32 and Win64 together?

**Probably yes -- the reason to think otherwise turned out to be wrong.** They write to
separate databases, and the "livelock" that appeared to block it was the whole-corpus
resolve passes (Task 2), which each process pays independently whether or not the
other is running.

Order of work: finish Task 2, then re-measure two platforms concurrently. The earlier
throughput drop (win32 fell 84 -> 28 files/min while win64 ran) must be re-measured
then, because both processes were partly inside those scans at the time and the
comparison windows also covered different folders. At 4.6x, sequential is already
~1 h per platform.

## Verification contract for every change above

1. `DRAGLINT_PROFILE=1` before/after on `...\DevExpress\VCL\ExpressBars\Sources`
   (83 files; the 670 s -> 147 s baseline).
2. `cmpdb.py` + `cmpfacts.py` against a pre-change DB -- **zero disagreements**, not
   just matching totals.
3. `tests\lint\run_lint_tests.ps1` (160) and `tests\lint-store\run_store_tests.ps1`
   (16), both with `-Exe` pointing at the fresh build.
4. Full `tests\run_battery.ps1` before deploying to `third_party\dll-win64`.
   **Never run the battery while an index job is running** -- it spawns many
   `drag-lint` processes and starves them (measured: win32 fell 84 -> 6 files/min).

## Traps that cost time this session -- do not re-learn them

* **stdout is block-buffered when redirected to a file.** A hung run and a healthy
  slow run look identical for minutes. The only reliable liveness signal is
  `Win32_Process.WriteTransferCount`.
* **Short sampling windows lie.** File sizes vary ~10x between folders; a 4-minute
  window read 84 files/min where the full run averaged 28. Only completed runs settle
  a rate.
* **Benchmark in BOTH orders.** A 2.6x "improvement" was pure page-cache ordering;
  reversed, it was 0.93x.
* **Never text-process a `.pas` with PowerShell/Python.** A `-replace` round-trip
  introduced 3 lone LFs this session (caught and repaired at byte level). Use the Edit
  tool, then verify CRLF + 7-bit ASCII.
* **`--recompile` writes 8.3x more bytes per file than `--rebuild`** (35.1 vs 4.2 MB)
  on a large DB. For a full re-parse, prefer `--rebuild`.
* **A killed index run restarts from zero** -- see
  `docs/INBOX-index-runs-are-not-resumable.md`. Budget for that before killing one.
