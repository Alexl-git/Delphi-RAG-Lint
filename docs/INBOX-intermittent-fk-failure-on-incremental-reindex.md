# INBOX -- an INTERMITTENT `FOREIGN KEY constraint failed` aborts a section build

**Split out 2026-08-17 (session 25)** from
`INBOX-indexer-fingerprint-disagrees-between-entry-points`, whose headline is
fixed and retired. This finding was unrelated to that one -- it merely happened
to be observed in the same run -- and it was keeping a discharged note open.

**Filed:** 2026-08-17 (session 24), during a CLI self-index reindex.
**Class:** `wrong` / robustness. **Seen ONCE. Not reproduced.**

## Why this is the most function-impeding item currently open

Every other open note is performance, a feature request, or blocked on an owner
decision. This one **stops the tool doing its job**, and does it quietly:

```
drag-lint index --all --only DragLint-Cli
  resolve: unit-uses  101/134 ...
  resolve: ancestry   5/18 ...
  resolve: helpers    6/6 ...
  ERROR building section DragLint-Cli: ESQLiteNativeException:
    [FireDAC][Phys][SQLite] ERROR: FOREIGN KEY constraint failed
```

The run reports ERROR and exits, leaving that section **unbuilt**. A scripted
`index --all` sweep over many sections would abandon this one and report success
for the rest, so the operator is left with a silently missing index rather than a
failed build.

## What is known

* **Not reproducible.** The identical command immediately afterwards succeeded
  (102 files, 5,518 call edges), as did `--rebuild`. Other sections
  (`DragLint-Tests`) and a fresh ad-hoc index were unaffected throughout.
* **The database was NOT corrupt** -- checked at the moment of failure:
  `PRAGMA foreign_key_check` 0 violations, `PRAGMA integrity_check` ok, and zero
  orphans in `call_edges.ref_id` / `call_edges.target_symbol_id`.
* So the violation arises **transiently inside the run**, after the helper
  resolve and (by position) during `ResolveCallTargets`.
* **The distinguishing condition:** it was the FIRST incremental reindex after a
  large number of source files had changed in one go -- many files re-parsed, ids
  reissued, while `call_edges` was rebuilt against them.

## THE NEXT OPPORTUNITY TO CATCH IT IS THE DevExpress UPDATE

The owner updates DevExpress monthly, which changes a large number of library
units at once and then needs a library reindex. **That is precisely the
"many files changed in one go" shape this failure was seen under**, on the
largest index in the tree.

If it fires during that run: **keep the log and the database**, do not simply
re-run. A re-run succeeded last time, which is why this was never diagnosed.

## What an investigation should do

* Re-run the shape deliberately: touch ~40 files, then incremental index,
  several times, and see whether it reproduces at all.
* If it does, log the failing STATEMENT. `ResolveCallTargets`
  (`src\storage\DRagLint.Storage.SQLite.pas`) rebuilds edges from scratch, so the
  candidate is an edge inserted against a ref or symbol id deleted by the same
  run.
* Consider whether the rebuild transaction ordering can leave a window where a
  `call_edges` row references a `refs` row already removed.

## Related

The whole-database calls resolve now ANNOUNCES itself before running
(`INBOX-incremental-index-hangs-on-large-db`), so a log captured during a failure
will say which shape was in flight and why -- information the original occurrence
did not have.
