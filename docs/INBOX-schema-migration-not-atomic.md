# INBOX: the schema migration is not atomic -- an interrupted upgrade bricks the DB

**Found:** 2026-08-03, during the nine-DB rollout to schema v19.
**Severity:** high for anyone whose index is large enough that a rebuild is expensive
(the ORM3 DB is ~90 MB / 74k symbols and took 438 s; the two library DBs took ~3.6 h).
**Class:** `wrong` -- the index answers with a hard failure where it should either work
or self-heal.

## Symptom

`C:\Projects\DB\ORM3\drag-lint.sqlite` could not be opened at all. Every command --
including the read-only `schema` introspection command -- died with:

```
> drag-lint schema --db C:\Projects\DB\ORM3\drag-lint.sqlite --format text
FATAL: ESQLiteNativeException: [FireDAC][Phys][SQLite] ERROR:
       table symbol_facts has no column named mutates_params
```

## Actual state of that DB

```
schema_meta:                 schema_version = 19
pragma table_info(symbol_facts):
  symbol_id, reads_fields, writes_fields, returns_owner, cyclomatic,
  body_loc, dfm_event, sql_reads, sql_writes, covered_by
                             <- the four v19 columns are ABSENT
symbols:      74,151 rows
symbol_facts: 13,267 rows
```

Stale `drag-lint.sqlite-shm` (32 KB) and `drag-lint.sqlite-wal` (0 bytes) siblings were
present, i.e. the previous writer did not shut down cleanly.

## Root cause

The v18 -> v19 upgrade does two things: stamp `schema_meta.schema_version = 19`, and
`ALTER TABLE symbol_facts ADD COLUMN` four times. **Those are not in one transaction**,
so a process killed (or a WAL never checkpointed) between them leaves a DB that is
stamped-but-unmigrated.

The version gate is a `>=` check, so the migration then **never runs again** -- the DB
believes it is current. And because `symbol_facts` is written unconditionally on open /
index, the missing column is a hard `ESQLiteNativeException` rather than a degraded
read. The DB is permanently unusable with no repair path but deletion.

Note the failure survives a *read-only* command: `schema --db ...` is documented as
"read-only" introspection, yet it also FATALs, so there is no way to even diagnose the
DB with the tool itself. It had to be inspected with Python's `sqlite3`.

## Reproduction

Not reproduced deliberately (it needs a kill in a specific window), but the state is
trivially constructible:

```sql
-- against any v18 index
UPDATE schema_meta SET value = '19' WHERE key = 'schema_version';
-- then run any drag-lint command against it
```

The healthy path does work: copying a clean v18 DB and running `index` against it
migrated it correctly, adding all four columns.

## Suggested fixes, cheapest first

1. **Wrap the migration in one transaction** -- `BEGIN; ALTER...; ALTER...; ALTER...;
   ALTER...; UPDATE schema_meta...; COMMIT;`. Stamp the version **last**, inside the
   same transaction. This alone removes the failure window. (SQLite does support
   transactional DDL.)
2. **Verify columns, not just the version stamp, on open.** A cheap
   `pragma table_info(symbol_facts)` check at open time could detect the mismatch and
   either re-run the ALTERs (they are idempotent in effect) or fail with an actionable
   message -- `"index at C:\... is stamped v19 but missing column mutates_params;
   delete the file and reindex"` -- instead of a raw FireDAC exception.
3. **Make `schema` genuinely read-only.** It is the one command that should still work
   on a damaged DB, since its whole job is telling you what state the DB is in.

## Related

- The same rollout surfaced a second, separate trap: after the migration, the new
  columns stay **NULL on every DB** unless `--force-reparse` is passed, because the
  incremental walk skips unchanged files. See section 6a of
  `docs/INBOX-index-schema-v19-reindex-for-converter.md`. Fix (2) above would be a
  natural place to also warn when a DB's schema version is newer than the last full
  parse.
