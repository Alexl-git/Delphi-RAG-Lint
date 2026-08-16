# RESUME -- indexer 4.6x, lint 1,742, and the resolve-pass discovery

Date: 2026-08-11. Supersedes `RESUME-2026-08-10-lint-noise-and-constructor-docs.md`
as the entry point.

## >>> UPDATE, later the same day: TASK 2 IS DONE

The "next action" below has shipped. Read
`docs/PLAN-2026-08-11-indexer-performance-and-concurrency.md` (Task 2 section) for
the full account; the short version:

| 2.09 GB library-Win32 index | before | after |
|---|---|---|
| index 1 changed file | 2,276.7 s | **38.7 s** |
| re-index, nothing changed | 2,276.7 s | **20.9 s** |

`ResolveCallTargets` was the entire cost (2,252.8 s of 2,276.7 s); the other three
passes are 19 s combined. It is now scoped to the refs a run can actually have
affected, verified row-identical over 3.32M refs and 541,354 call edges.

**Three things worth carrying forward:**

1. **The passes had no timer and no output.** That, not any concurrency defect, is
   why this cost two sessions. One printed line per pass answered it in one run.
   Nobody had ever let the call pass finish -- 37.5 minutes.
2. **A cheap pass that is also a repair mechanism must not be guarded.** The first
   cut skipped all four when nothing changed and broke
   `run_unit_uses_targets.ps1`, which poisons the column with raw SQL and requires
   the next plain `index` to recompute it. Only the expensive pass is guarded now.
3. **NEW DEFECT FOUND, not yet fixed:**
   `docs/INBOX-whole-db-resolve-degrades-a-stale-index.md`. A whole-corpus resolve
   re-derives `refs.receiver_text` from the file on DISK at the ref's STORED
   line/col, so on an index whose sources have moved it overwrites good receivers
   with garbage -- 11,008 receivers and 464 call edges destroyed in a measured
   run. Cheapest fix: re-derive receivers only for files the run re-indexed, which
   also deletes most of what the pass writes.

**Next**: Task 1 needs re-measuring (the "missing 82 s" was computed before the
resolve passes were timed -- see the note at the top of that task), then Task 3.

## Status (as written this morning, before the above)

Branch **`fix/lint-noise-round1`** = `a0a906e`, two new commits, working tree clean
for `src/` and `tests/`. **`main` still has 3 unpushed commits** (`176cfb9`,
`65dc3b3`, `3fdefd9`). `fix/lint-noise-round1` has **no upstream** -- it is local only.

| | before | after |
|---|---|---|
| `lint-all` | 2,112 | **1,742** |
| index, ExpressBars 83 files | 670 s | **147 s (4.6x)** |
| win32 library rebuild (projected) | 4.86 h | **~63 min** |
| lint fixtures | 158 | **160/160** |
| lint-store | 16/16 | **16/16** |

Shipped in `3d7d98b` (lint round 2) and `a0a906e` (indexer perf + the plan).

## >>> READ FIRST NEXT SESSION

`docs/PLAN-2026-08-11-indexer-performance-and-concurrency.md` -- the ordered plan,
with the verification contract and the traps. Start at **Task 2**.

## The next action, exactly

**Make the four whole-database resolve passes incremental.** `CLI.pas:2727-2733`
(same block also at 1900, 2681, 15812):

```pascal
Store.ResolveUnitUseTargets;
Store.ResolveAncestry;
Store.ResolveHelpers;
Store.ResolveCallTargets;
```

They scan the ENTIRE index regardless of how many files were just indexed. Indexing
83 files into a 2.1 GB DB pays four full-corpus resolutions. **Measured:** all 83
files indexed in ~5 min, then writes stop dead while CPU holds ~0.8 cores; over the
next 90 s the process read **+15.2 MB / 1,907 read-ops and wrote 0 bytes**.

This is also the true explanation of the "livelock" that was chased for hours --
there is no livelock. See
`docs/INBOX-indexer-livelock-when-two-platforms-run-concurrently.md`, which now
carries the corrected diagnosis and the 5-minute non-destructive reproduction.

After that, Task 1: **82 s of the 147 s run is outside every phase timer.** Add a
whole-`IndexFile` timer plus a `WalkAndIndex` timer to split it, then chase the
candidates listed in the plan (prime suspect: `TAstParseCache.Get` re-parsing each
file a second time for the facts pass).

## Verification contract -- run ALL of it after every change

1. `DRAGLINT_PROFILE=1` before/after on
   `C:\Program Files (x86)\DevExpress\VCL\ExpressBars\Sources` (83 files; 670 s ->
   147 s baseline).
2. `python C:\TEMP\claude\cmpdb.py` and `cmpfacts.py` against a pre-change DB.
   **Zero disagreements**, not merely matching totals. These caught nothing this
   session precisely because they were run every time -- keep it that way.
3. `pwsh -File tests\lint\run_lint_tests.ps1 -Exe src\cli\Win64\Debug\drag-lint.exe`
   (160) and `tests\lint-store\run_store_tests.ps1` (16).
4. Full `tests\run_battery.ps1` before deploying to `third_party\dll-win64`.
   **Never run the battery while an index job runs** -- measured, win32 fell
   84 -> 6 files/min.

## State of the indexes

* `library-Win32.sqlite` -- **COMPLETE and current** (7,412 files, 2,240,573 symbols,
  rebuilt 2026-08-11 06:21, 4.86 h). Has the three new FK indexes.
* `library-Win64.sqlite` -- **INCOMPLETE**. Its rebuild was stopped mid-run. Re-run
  when convenient; at 4.6x expect ~1 h:
  `drag-lint index --all --only Library --platform win64 --rebuild`
* `DragLint-Cli.sqlite` -- rebuilt 2026-08-11, current.
* The deployed `third_party\dll-win64\drag-lint.exe` is the **00:08 build** -- it has
  the FK-index migration but NOT the three perf fixes. Deploy after the battery.

## What is still uncommitted / untracked

Nine INBOX notes, deliberately left untracked per the project rule. The ones from
this session:

* `INBOX-library-reindex-25x-slower-on-large-db.md` -- the FK-index fix, plus three
  refuted hypotheses recorded so they are not re-investigated.
* `INBOX-indexer-livelock-when-two-platforms-run-concurrently.md` -- **corrected**;
  now the resolve-pass diagnosis.
* `INBOX-group-E-dataflow-rules-are-majority-false.md` -- 15/15 sampled false.
* `INBOX-index-runs-are-not-resumable.md`
* `INBOX-exception-class-unit-and-generated-exception-types.md` -- the owner's
  exceptions-unit idea, staged so stage 1 is risk-free.
* `INBOX-QUEUED-editor-integration-vscode-zed-delphilsp.md` -- **NOT YET READ**, open
  only after autodoc + linter are finished.

## Lint backlog, with the sampling already done

* **Group E (261)** -- 15/15 sampled FALSE. `overwrite-before-read` (58) is the worst:
  its advice would INTRODUCE bugs (it flags the `X := nil` before a `try`, and a
  refcounted-interface release that closes a DB handle). `used-before-assignment`
  (46) has one cause: guard-flag idiom + short-circuit `and`/`or`. `double-free` (42)
  mistakes one-free-per-iteration loops for repeats.
* **Group C (412)** -- two metric bugs: `else if` chains counted as NESTING, so
  `ParseArgs` reports 141 levels deep and cognitive complexity 10,572. Plus
  thresholds set below the median of what they flag (`too-many-exit-points` is 5,
  median flagged 8).
* **Group F (539)** -- `concat-in-loop` flags 20 dynamic-ARRAY appends as string
  concatenation, with advice (`TStringList`, `string.Join`) that cannot apply.
* **28% of all findings are in one file**, `DRagLint.CLI.pas` (481 of 1,742).

## Gotchas that cost real time this session

* **stdout is block-buffered when redirected.** A hung run and a slow run look
  identical for minutes. The only reliable liveness signal is
  `Win32_Process.WriteTransferCount`.
* **Short sampling windows lie.** File sizes vary ~10x by folder; a 4-minute window
  read 84 files/min where the full run averaged 28.
* **Benchmark in BOTH orders.** A 2.6x "win" was pure page-cache ordering; reversed it
  was 0.93x.
* **Never text-process a `.pas`.** A PowerShell `-replace` round-trip introduced 3
  lone LFs (caught, repaired at byte level). Use Edit, then verify CRLF + 7-bit ASCII.
* **`--recompile` writes 8.3x more bytes per file than `--rebuild`** on a large DB
  (35.1 vs 4.2 MB). Prefer `--rebuild` for a full re-parse.
* **A killed index run restarts from zero** (`INBOX-index-runs-are-not-resumable.md`).
  12.5 h was lost to this once already.
* **`index --all` resolves its manifest relative to the EXE'S OWN DIR.** A fresh exe
  with no `drag-lint.json` beside it indexes NOTHING and exits 0. Verify with
  `index --all --dry-run` -> `Sections to build:` must be > 0.

## The method that actually worked, worth repeating

Three hypotheses about indexer cost (fsync, FK-cascade scans, FTS5 trigram deletes)
were each argued plausibly and each was **wrong**. A 20-line opt-in phase profiler
(`DRAGLINT_PROFILE=1`) found the real answer in one run and then guided three
successive fixes. The same discipline on the lint side -- sample 12 findings and read
the source before believing a count -- has now been right every single time.
