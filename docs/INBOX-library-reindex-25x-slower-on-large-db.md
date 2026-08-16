> # 2026-08-16 (session 22): the fix is in code; one of the two residuals is DONE.
>
> **Already landed (not this session):** the three FK-child indexes at
> `DRagLint.Storage.SQLite.pas`, added without a schema bump so existing DBs pick
> them up on next open, with the both-orders 2.7x measurement recorded in the
> comment.
>
> **Done this session:** `SizeGuardCheck` is now called on the INDEX path
> (`DoIndex`, before the walk), not only on the consumer commands. That gap is
> why a 1500 MB guard sat silent while the library index grew past 2 GB -- the
> only runs touching it were index runs, and those were the ones not checking.
> The guard still no-ops outside a 32-bit process, so it is free on Win64.
>
> **Still open:** progress reporting has no `n/total` or ETA -- `ReportProgress`
> prints per-file only, so an hours-long library reindex is indistinguishable
> from a hang. Cheap (~30-60 min) and autotest-verifiable; the positive control
> must assert the progress line APPEARS, not merely that no error occurred.
>
> **The 25x figure remains a projection**, and a downscaled fixture cannot
> confirm it -- the cost is O(child-table rows), which is exactly what a small
> fixture lacks. Only a real library reindex converts it to a measurement.

# INBOX -- library reindex is 25x slower per file on a large DB

**Filed:** 2026-08-10, while the Library[Win64] schema v20->v21 re-parse was running.
**Class:** performance / scaling defect.
**Status: CAUSE IDENTIFIED AND MEASURED.** Three hypotheses were tested and refuted
before the fourth held; the refuted ones are kept below so nobody re-runs them.

## The fix (3 statements)

```sql
CREATE INDEX IF NOT EXISTS idx_call_edges_receiver ON call_edges(receiver_type_symbol_id);
CREATE INDEX IF NOT EXISTS idx_symbol_facts_symbol ON symbol_facts(symbol_id);
CREATE INDEX IF NOT EXISTS idx_symbol_docs_symbol  ON symbol_docs(symbol_id);
```

These three FK child columns have **no index**, while every other FK child column in
the schema does. `PRAGMA foreign_keys = ON` is set on the write connection
(`Storage.SQLite.pas:2493`), so deleting a `symbols` row makes SQLite look for
children in each of those tables -- and with no index that is a **full table scan per
deleted symbol**.

Add them to the migration as a schema bump so existing DBs get them.

## The measurement

Per-file cascade delete, 120 files, 25 MB DB, run in **both orders** to rule out the
page-cache artifact that invalidated an earlier attempt:

| order | stock schema | +3 indexes | ratio |
|---|---|---|---|
| stock first | 12,860 ms | 4,619 ms | **2.78x** |
| indexed first | 12,538 ms | 4,649 ms | **2.70x** |

**2.7x at 25 MB -- and the gain grows with corpus size**, because the scan being
eliminated is O(rows in the child table) per deleted symbol:

| | 291-file sample | ~7,000-file library | growth |
|---|---|---|---|
| `call_edges` rows | 5,770 | ~139,000 | 24x |
| `symbol_facts` rows | 3,859 | ~93,000 | 24x |
| symbols deleted per file | ~77 | ~77 | -- |
| row visits per file | ~440 K | ~10.7 M | **24x** |

That 24x is the measured 25x. Note the large-scale figure is a **projection from the
mechanism**, not a measurement -- the 2.7x is what was actually measured.

## Why it looked like something else

Engine throughput by DB size, same build, same machine:

| Run | DB at start | Mode | files/min |
|---|---|---|---|
| `index C:\Projects\fibplus --db <new>` | empty | cold build | **150.4** |
| `index C:\Projects\fibplus --db <same> --force-reparse` | 25 MB | re-parse | **128.3** |
| `index --all --only Library --platform win64 --recompile` | **2,027 MB** | re-parse | **5.9** |

A cold build never deletes anything, so it never pays the scan -- which is why the
engine looks fast in every small test and only collapses on the big DB.

## Refuted -- do not re-investigate

* **NOT `--jobs` / lack of threads.** Parallelism in `index --all` is **per SECTION,
  not per file** (`CLI.pas:2044-2066`: `EffJobs = min(CpuCount, NSections)`, one child
  process per plan item). `--only Library --platform win64` is ONE plan item, so it
  collapses to the sequential path. Measured: 2 threads, **0.96 cores of 9**.
* **NOT disk I/O.** Measured over 20 s on the live job: **0.07 MB/s read, 0 MB/s
  write, 11 read IOPS, 0 write IOPS, 0.99 cores busy.** The disk is idle; the process
  is CPU-bound in one thread. Any "parallel reads to saturate the disk" design would
  be optimising a resource that is ~0% utilised.
* **NOT fsync / journal mode.** Two independent reasons, and note the first
  correction: the code sets no `journal_mode` pragma, but **the databases are already
  in WAL** -- `journal_mode=WAL` is persisted in the DB file itself, and
  `library-Win64.sqlite-wal` / `-shm` are present on disk. So the "DELETE journal +
  fsync per commit" theory was wrong on its own premise. It is independently ruled out
  by the measurement: 0 write IOPS over 20 s.
* **NOT the FTS5 trigram delete triggers.** `string_literals_ad` pushes a `'delete'`
  into both `string_fts` (unicode61) and `string_fts_tri` (trigram) per literal, which
  looked expensive. Measured with the triggers dropped, both orders: **1.0x / 1.1x**.
  No material cost.
* **NOT the schema bump itself.** It is why every file is re-parsed, but re-parsing a
  25 MB DB costs only 17% more than a cold build.

**Method note:** the first FK audit reported 23 unindexed columns and was **wrong** --
it reused one sqlite3 cursor for the inner `PRAGMA index_info` while iterating
`PRAGMA index_list`, silently resetting the outer result set so only each table's
first index was seen. The first benchmark then showed a 2.6x that was purely a
page-cache **ordering** artifact (reversing the order gave 0.93x). Both were caught by
re-running in the opposite order. **Always run this class of benchmark in both orders.**

## After the fix, threading becomes worth it -- but only then

Today ~96% of per-file time is the cascade scan, not parsing (0.40 s/file parse
measured cold vs ~10 s/file observed). Parallel parsing would buy ~4% now. Once the
indexes land, parse becomes the dominant term and a **parse-worker pool feeding one
serialized writer** is the right shape. Note that sharding into child processes -- the
existing `--jobs` model -- cannot work *within* a platform: all files in a section
share one `.sqlite` and would contend for the write lock. Across platforms it already
works: `--only Library --jobs 2 --config <path>` (no `--platform`) builds Win32 and
Win64 concurrently into two different DBs.

## Two smaller things noticed in passing

* **`sizeGuardMB: 1500` is set and the DB is 2,027 MB.** The guard never fired and
  nobody was told. Either it is not enforced for `source: registry-libraries` sections
  or it is advisory.
* **A 13-hour single-section job prints no ETA and no progress fraction.** The previous
  session predicted "~45 min" and was wrong by 16x. An `n/total, rate, ETA` line every
  N files would have caught that in the first minute.

## Scope, for reference

Resolved from the registry values the engine reads (`Project.Resolver.pas:575-597`:
`Search Path` + `Browsing Path`, HKCU+HKLM, both views, macros expanded):

* **Win32** -- 142 folders, 8,214 indexable files
* **Win64** -- 137 folders, 7,790 indexable files

Lists: `C:\TEMP\claude\library-index-folders-Win32.txt` / `-Win64.txt` (plus
`*-with-counts.txt`).

**Macro trap:** these values contain `$(DXVCL)`, `$(BDSCatalogRepository)` and
`$(ProgramFiles(x86))`. The nested-parenthesis one defeats a naive
`\$\(([^)]+)\)` regex, and an unexpanded path then fails an existence check and
vanishes silently -- which dropped **every DevExpress folder** from two attempts before
it was caught. Expand from the Delphi `Environment Variables` registry key **and** the
process environment.
