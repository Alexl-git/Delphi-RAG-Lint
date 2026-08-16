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
