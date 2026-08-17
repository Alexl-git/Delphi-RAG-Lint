> # THE HEADLINE IS DONE (2026-08-17, session 24): per-file resume SHIPPED.
> # The note stays open for ONE companion issue -- see the end of this banner.
>
> `files.indexed_at_fingerprint`, stamped **inside** the per-file transaction
> `CommitFileTx` closes (before `FConn.Commit`), so a kill commits the rows and
> the stamp together or neither. A run forced by a fingerprint change now takes
> the ordinary up-to-date skip for any file already stamped with the CURRENT
> fingerprint. Additive column, no schema bump, NULL on every existing row --
> so nothing re-parses on account of it existing, and files gain a stamp as they
> are next indexed.
>
> **The written plan (`PLAN-SESSION-23-IMPLEMENTATION.md` section 5b) was wrong
> in two places, and both would have shipped something broken.**
>
> 1. **It reused `ForceReparse`.** That flag is set for THREE reasons and only
>    one may resume: a **fingerprint change** is resumable (a file parsed by
>    THIS engine really is current); **`--force-reparse` is not**, because the
>    flag means "ignore the skip" and honouring a stamp would silently disobey
>    what the caller typed; **`--rebuild` is not**, and is moot since the index
>    is wiped first. Only the caller can distinguish them, so
>    `SetResumeFingerprint` is a separate call, `''` by default, set exclusively
>    on that one branch.
> 2. **Its test fixture tested nothing.** It proposed: index a folder, index ONE
>    file with `--no-preprocess`, index the folder again, assert one file
>    parsed. Measured, `index <one file>` **also** commits the database-level
>    fingerprint. So by step three `Prev = Cur`, the run is not a
>    fingerprint-change run at all, nothing is forced, and BOTH files take the
>    plain incremental skip -- "skipped 2", with the positive control failing.
>
> `tests\autotest\run_index_resume_per_file.ps1` therefore builds the interrupted
> state explicitly, rolling the database-level stamp back by SQL after the
> single-file run. That is exactly what a kill leaves behind (per-file stamps
> written, database-level stamp not -- which is what session 22's split
> guarantees), and it is deterministic rather than racing a Ctrl-C.
> **Said plainly: the real shape -- a process killed hours into a library walk --
> is SIMULATED, not reproduced.** What is verified is the resume logic over the
> exact database state such a kill produces.
>
> ## What keeps this note open
>
> Of the two "Companion issues" at the foot of the note:
>
> * **Progress `n/total` + ETA -- DONE** (session 23). Verified in this session's
>   own fixture output: `[1/2] 50%  elapsed 0s  ~0s left`.
> * **Output appearing only in blocks when redirected -- NOT done, and not
>   diagnosed.** A 9-minute ORM3 profiling run this session wrote a redirected
>   stderr file that stayed at **0 bytes until the process exited**, so a slow
>   run and a hung run were again indistinguishable from outside.
>
>   **MEASURED 2026-08-17: the note's stated cause is WRONG. It is PowerShell,
>   not the engine.**
>
>   The engine already flushes stdout once per file -- `Flush(Output)` at
>   `src\core\DRagLint.Core.Indexer.pas:1176`, guarded by
>   `tests\autotest\run_index_progress_flush.ps1`. The stderr counter
>   (`Indexer.pas:614/620`) has no flush, but the RTL's 128-byte buffer bounds
>   its lag to 2-3 lines.
>
>   Same 52 s index, both redirections, sizes polled every second:
>
>   ```
>   cmd.exe    > 2>   out.log 128 -> 765 -> 2230 bytes within 4 s; err.log grew from t=1 s
>   PowerShell > 2>   out.log 0 until an 8192-byte block
>                     err.log 0 BYTES FOR THE WHOLE RUN, 4462 at exit
>   ```
>
>   PowerShell holds all native stderr to process exit -- exactly the ORM3
>   symptom. **The fix is in the HARNESS** (redirect long runs via `cmd.exe` or
>   `Start-Process -RedirectStandardError`), not in the engine. An optional
>   `Flush(ErrOutput)` after `:620` is secondary.
>
>   Once that is written down in the runner docs, **this note closes.**
>
> ---
>
> # STILL OPEN, but the CORRECTNESS half is fixed (2026-08-16, session 22).
>
> Re-measurement found this note understated the problem: a killed run did not
> merely "restart from zero", it could silently **keep stale parses**.
> `ApplyIndexerFingerprint` stamped the NEW fingerprint via `SetMetaValue`
> **before the walk started**, so an interrupted engine-change re-parse left the
> next run reading `Prev = Cur`, concluding nothing had changed, and taking the
> up-to-date skip over every file the killed run never reached. Strictly worse
> than restarting, because the index then looked complete.
>
> Fixed by splitting the stamp into `CommitIndexerFingerprint`, called only once
> a walk finishes (`DRagLint.CLI.pas`, both the manifest and single-root paths).
> An interrupted run now costs time and nothing else.
> Test: `tests\autotest\run_index_fingerprint_commit.ps1`.
>
> **What remains is this note's actual subject:** there is still no per-file
> resume, so an interrupted run restarts from the beginning. That needs the
> per-file `indexed_at_version` column described below, which can use the
> additive-ALTER-without-schema-bump pattern already at
> `DRagLint.Storage.SQLite.pas:2981-2985`.

# INBOX -- a killed index run restarts from zero (no resume)

**Filed:** 2026-08-11.
**Class:** robustness / ergonomics. Cost is measured in hours, repeatedly.

## What happened

A Library[Win64] re-parse ran for **12.5 hours** and reached 4,748 of 6,978 files.
It had to be stopped to apply a schema index. Restarting re-parsed **from file 1** --
all 12.5 hours discarded. The owner's instinct was right ("if we can freeze it we
freeze it"), but there is nothing to freeze: the engine has no checkpoint.

## Why it cannot resume today

`--recompile` decides per file whether to re-parse, by comparing the file's recorded
state against disk. But when the ENGINE version/schema fingerprint changes, that
per-file logic is bypassed wholesale:

```
Indexer changed since this DB was built
(v=1.2.2-alpha;schema=20;pp=1;plat=win64 -> v=...;schema=21;...):
re-parsing every file in scope.
```

The fingerprint is stored **once for the whole database**, and is only updated when
the run completes. So a run that is 68% done has:

* every processed file already re-parsed at the new version, and
* a database still stamped with the OLD version.

Restarting therefore re-does all of it. The information needed to resume was
computed and then thrown away.

## The fix

Store the fingerprint **per file**, not per database -- e.g. a
`files.indexed_at_version TEXT` column written as each file is committed. Then:

* "re-parse every file in scope" becomes "re-parse every file whose
  `indexed_at_version` <> current", which is naturally resumable;
* a killed run resumes exactly where it stopped;
* the DB-level fingerprint stays as a fast path (if it already matches, skip the
  per-file check entirely), so nothing gets slower;
* partial upgrades become visible and queryable instead of implicit.

This is additive (`ALTER TABLE files ADD COLUMN indexed_at_version TEXT`) and needs
no schema-version bump if introduced the same way the FK indexes were -- NULL simply
means "unknown, re-parse it".

## Why it matters more than it looks

Every schema bump currently costs a full re-parse of every DB, and those runs are
measured in hours. Any interruption -- a reboot, a lock, a mistake, a deploy -- costs
the whole run. That is also why the "~45 min" estimate in an earlier resume doc was
off by 16x and nobody noticed until half a day had passed.

## Companion issues

* **No progress fraction or ETA.** A multi-hour single-section run prints only a
  per-file line: no `n/total`, no rate, no ETA. Both this and the resume gap were
  invisible until someone measured by counting log lines by hand.
* **stdout is block-buffered when redirected to a file.** A run whose output goes to
  a file appears to produce NOTHING until 4 KB accumulates, which makes a slow run
  and a hung run look identical from outside. An explicit flush per file (or per N
  files) would make progress observable. This directly cost time during the
  2026-08-11 session: a hung Win64 process and a healthy one were indistinguishable
  for ten minutes.
* See `docs/INBOX-library-reindex-25x-slower-on-large-db.md` for the performance work
  that made these runs frequent enough to matter.
