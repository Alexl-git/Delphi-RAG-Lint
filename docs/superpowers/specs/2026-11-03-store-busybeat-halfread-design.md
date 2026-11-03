# Store concurrency: beat-aware writer wait (SQLITE-BUSY-BEAT) and half-read index (IDX-HALFREAD)

Lane `store`, 1.41. Owner ruling 2026-11-01 20:25 (SQLITE-BUSY-BEAT); IDX-HALFREAD from the
2026-11-01 engine handoff follow-ups. No extractor bump: nothing here changes which rows an
index run emits, only WHEN they become visible and how long a second writer waits.

## 1. SQLITE-BUSY-BEAT -- a writer waits while the holder makes progress

### Today
`ConnectWriter` arms a 120 s busy timeout (`WRITER_BUSY_TIMEOUT_MS`, env
`DRAGLINT_BUSY_TIMEOUT_MS`). A second writer whose `BEGIN IMMEDIATE` (FireDAC `xiSnapshot`)
meets a holder dies `database is locked` after 120 s, however busy -- not stuck -- the
holder is. A whole-DB resolve pass holds the write lock for up to ~37 min.

### Why not a native busy handler
The engine links FireDAC's STATIC SQLite (`FireDAC.Phys.SQLiteWrapper.Stat`, `{$L
sqlite3_x64.obj}`). `TSQLiteLib` exposes `sqlite3_busy_timeout` but not
`sqlite3_busy_handler`, and an `external` in another unit cannot bind to that object file.
`sqlite3_busy_timeout` from a watcher thread blocks on the waiting connection's mutex. So
the wait is extended at the application level, at the lock-acquisition point.

### Design
1. **Holder publication (ControlChannel).** A process-wide, refcounted set of database
   paths this engine has a WRITER store open on (`BeatWriterOpened` / `BeatWriterClosed`,
   called by `TSQLiteSymbolStore` on a write connect / destroy). The heartbeat pipe's
   `status` reply gains one field, ONLY when the request carries the new argument
   `writing`: `writing=<path>|<path>...` (full paths; `|` cannot occur in a Windows path).
   Older parsers never ask, so their reply shape is unchanged (as `role` / `beat`).
2. **Holder discovery (ControlChannel).** `SnapshotWritingBeats(ADbPath)`: enumerate this
   user's/session's `drag-lint-beat-*` pipes except our own pid, ask each
   `status<TAB>beat<TAB>writing` (short connect timeout), and keep (pid, seq) of every
   engine whose `writing=` names ADbPath (case-insensitive full path).
3. **Waiter rule (Storage.SQLite, `StartWriteTx`).** Every top-level
   `FConn.StartTransaction` of a writer store goes through one helper:
   * slice 1: the normal busy timeout W (120 s / env) inside SQLite -- unchanged;
   * on SQLITE_BUSY: take snapshot S1. No holder with a beat (old engine, a verb without
     a heartbeat pipe, a non-drag-lint writer) -> re-raise: **today's fixed timeout**.
   * otherwise retry one more slice W; on BUSY take S2; if ANY holder's seq advanced
     S1 -> S2, print a one-line NOTE (first time only) and retry with S1 := S2; else
     re-raise. So a progressing holder is waited out indefinitely; a holder whose beat is
     frozen for a whole slice is given up on after at most 2W.
   * the waiter never beats while it waits (two waiters must not keep each other alive).
4. Out of scope (residual, stays on the fixed W): autocommit writes outside a transaction
   (`SetMetaValue`, a bare `ExecSQL`) and the connect-time pragmas. The long holds that
   matter are transactions; the first lock a second writer meets is its BEGIN IMMEDIATE.
5. The index lock `<db>.indexing.lock` keeps its refuse-at-start design (#17 / IDX-LOCK):
   nothing waits on it today, and turning the refusal into a wait would change the IDE
   job queue's contract. Recorded as a decision, not done.

### Tests (two-process, `tests\autotest\run_busy_beat_guard.ps1`)
A python holder (`_fk_perp.py --hold-ms`) holds `BEGIN IMMEDIATE`; a PowerShell runspace
serves a fake heartbeat pipe; the victim is a real `index --resolve-only` with
`DRAGLINT_BUSY_TIMEOUT_MS=3000`.
* BB1 advancing beat naming the DB: the victim waits the 15 s hold out, exit 0 (RED today:
  `database is locked` at ~3 s).
* BB2 frozen beat: the victim gives up `database is locked` well before the hold ends.
* BB3 no beat pipe: gives up at about W (today's behaviour kept).
* BB4 an advancing beat that names ANOTHER db is not a holder: gives up (positive control
  for the db match).
* BB5 a real `index` publishes `writing=<db>` when asked, and a request without `writing`
  carries no such field.

## 2. IDX-HALFREAD -- readers mid-reindex

### Where a reader sees a half-written index (WAL: a reader sees the last COMMIT)
* **A. Stale resolver / `--resolve-only`.** `DoIndex` and the manifest path call
  `Store.ClearCallEdges` in AUTOCOMMIT (`DELETE FROM call_edges` + `UPDATE refs SET
  symbol_id = NULL`), then run the calls pass in its own transaction. For the length of the
  pass (~37 min on a 2 GB index) every reader sees ZERO resolved refs -- the "0 of 60k"
  observation (a resolver bump re-derives every DB).
* **B. The file walk.** File batches commit every 256 files / 5 s (PR #10, kept so readers
  and a resume never lag far). A re-emitted file's refs are new rows with `symbol_id NULL`
  and its call edges are cascaded away until the calls pass commits; a `--rebuild` empties
  the DB first. Visible by design; a single transaction for a multi-hour re-parse is not
  an option (WAL growth, the lock held for hours, resume lost).

### Fix
* **A -> previous complete state.** The clear moves INSIDE the calls pass's transaction:
  the CLI wraps clear + `ResolveCallTargets` in the store's outer batch transaction
  (`BeginFileBatch` / `EndFileBatch`; the pass's own `StartTransaction` nests as a
  SAVEPOINT). Same statements in the same order on the same connection, so the scoping
  decision (`CallEdgesNeedRebuild` sees the cleared table) and the emitted rows are
  identical; readers keep the old, complete edges until one COMMIT swaps them.
* **B -> a clear status.** A reader (every verb through `OpenReadOnlyStore`) whose
  database has a live `<db>.indexing.lock` (held by an index run; DELETE_ON_CLOSE, so it
  exists only while a holder lives) and that does not hold it itself prints once to stderr:
  `NOTE: an index run is writing <db> right now -- answers may reflect a partly written
  index until it finishes.` No stdout change, no exit code change.

### Tests (`tests\autotest\run_index_halfread_guard.ps1`)
Test seam `DRAGLINT_TEST_RESOLVE_DELAY_MS` (sleep once inside the calls transaction).
* HR1 two-process: during `index --resolve-only` (seam 6 s) a concurrent `sql` reader
  counts resolved refs; it never sees 0 when the DB had > 0 before (RED today).
* HR2 the run's final resolved count equals the count before (same rows).
* HR3 a reader while `<db>.indexing.lock` is held prints the NOTE; HR4 positive control:
  no lock -> no NOTE.
