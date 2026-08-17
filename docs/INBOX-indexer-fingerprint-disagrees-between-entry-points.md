# INBOX -- the indexer fingerprint differs by ENTRY POINT, so alternating them forces a full re-parse

**Found:** 2026-08-17 (session 24), while reindexing the CLI self-index after a
day of source edits. **Pre-existing** -- `IndexerFingerprint` and both call sites
predate this session -- but the per-file stamps added for resume
(`INBOX-Done\INBOX-index-runs-are-not-resumable.md`) are what made it visible,
and they inherit it.

**Class:** correctness-adjacent / performance. Costs hours on the library index.

## Measured

One database, `src\cli\_D-RAG\drag-lint.sqlite`, mid-session:

```
DB-level fingerprint : v=1.3.0-alpha;schema=21;pp=1;plat=win64     <- written by `index <dir> --db`
per-file stamps      : 84 x NULL                                   <- indexed before stamping existed
                       10 x v=...;plat=                            <- written by `index --all --only`
                        8 x v=...;plat=win64                       <- written by `index <dir> --db`
```

After a full `index --all --only DragLint-Cli`, everything reads `plat=`:

```
DB-level fingerprint : v=1.3.0-alpha;schema=21;pp=1;plat=
per-file stamps      : 102 x v=1.3.0-alpha;schema=21;pp=1;plat=
```

## Mechanism

`IndexerFingerprint` (`src\cli\DRagLint.CLI.pas:2435`) folds the platform into the
string. The two entry points supply it from different places:

* **manifest path** -- `ApplyIndexerFingerprint(..., AItem.Platform)`
  (`CLI.pas:1873`) and `CommitIndexerFingerprint(..., AItem.Platform)`
  (`CLI.pas:2047`). `TPlanSection.Platform` is **`''` by design** for a project
  or folder section: *"Platform token for library sections; empty for
  folder/closure sections"* (`src\index\DRagLint.Index.Plan.pas:50`).
* **ad-hoc path** -- `ApplyIndexerFingerprint(..., PpPlatform)`
  (`CLI.pas:2641`), which resolves to a real token (`win64`).

The two are internally consistent, so nothing is corrupt. They simply disagree
about the same database.

## Consequence

Alternating entry points against one index makes `Prev <> Cur` every time, so
`ApplyIndexerFingerprint` announces *"Indexer changed since this DB was built"*
and re-parses **every file in scope** -- for no reason. Both spellings are
"correct"; neither describes a real engine change.

**This is worst exactly where it hurts most.** The per-file resume feature was
built for the library walk that ran 12.5 hours and reached 4,748 of 6,978 files.
That walk goes through the manifest path. A subsequent ad-hoc `index` against the
same DB now disagrees with every per-file stamp, so resume finds no match and
the whole point is lost.

## The fix, and the decision inside it

Make the fingerprint's platform component **a property of the database, not of
the caller**. Options, cheapest first:

1. **Normalise `''` to the resolved platform** in `IndexerFingerprint` -- i.e.
   have the manifest path resolve a real token for project sections too. Small,
   but it changes every existing fingerprint once, forcing exactly one full
   re-parse per DB. That cost is real and must be stated, not discovered.
2. **Drop `plat` from the fingerprint entirely** when the section is not a
   library section. Same one-time cost; arguably more honest, since a project
   index is not platform-specific in the way a library index is.
3. Leave the DB-level string alone and stamp per-file with a **canonicalised**
   form. Avoids the one-time reparse but leaves two spellings in circulation.

**Do not pick from this note.** Measure how many DBs carry which spelling first
(`SELECT value FROM schema_meta WHERE key='indexer_fingerprint'` across every DB
in `resolve-dbs`), because that decides whether option 1's one-time cost is
minutes or hours.

## POSITIVE CONTROL for whatever is written

A test asserting "the two entry points agree" passes trivially if BOTH return
`''`. Assert instead that indexing a project section by each entry point in turn
performs **no re-parse on the second run** -- i.e. `skipped N up-to-date` with
N = the file count -- which is the behaviour actually wanted, and which fails
today.

---

# Second, unrelated finding from the same run: an INTERMITTENT FK failure

```
drag-lint index --all --only DragLint-Cli
  resolve: unit-uses  101/134 ...
  resolve: ancestry   5/18 ...
  resolve: helpers    6/6 ...
  ERROR building section DragLint-Cli: ESQLiteNativeException:
    [FireDAC][Phys][SQLite] ERROR: FOREIGN KEY constraint failed
```

**Not reproducible.** The identical command immediately afterwards succeeded
(102 files, 5,518 call edges), as did `--rebuild`. Other sections
(`DragLint-Tests`) and a fresh ad-hoc index were unaffected throughout.

**The database was NOT corrupt** -- checked at the moment of failure:
`PRAGMA foreign_key_check` 0 violations, `PRAGMA integrity_check` ok, and zero
orphans in `call_edges.ref_id` / `call_edges.target_symbol_id`.

So the violation arises **transiently inside the run**, after the helper resolve
and (by position) during `ResolveCallTargets`. The distinguishing condition on
the failing run: it was the FIRST incremental reindex after a large number of
source files had changed in one go -- i.e. many files re-parsed, ids reissued,
while `call_edges` was rebuilt against them.

**Not diagnosed further, deliberately** -- one occurrence, and the index was
needed working. What the next investigation should do:
* re-run the "many changed files at once" shape (touch ~40 files, then
  incremental index) several times to see whether it reproduces at all;
* if it does, log the failing statement -- `ResolveCallTargets`
  (`src\storage\DRagLint.Storage.SQLite.pas`) rebuilds edges from scratch, so
  the candidate is an edge inserted against a ref or symbol id deleted by the
  same run;
* an intermittent failure that leaves the section unbuilt is worse than it
  looks: the run reports ERROR and exits, so a scripted `index --all` sweep
  would abandon that section while the others report success.
