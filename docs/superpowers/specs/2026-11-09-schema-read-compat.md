# Schema read-compat: a schema-24 engine reads a schema-23 index (wave 150, lane SC)

Status: DESIGN, 2026-11-09. Owner of the code: lane SC. SCHEMA_VERSION itself is flipped by INT only.

## Problem (measured, 149 INT REPORT "For the 150 planner"; LEDGER 08:11:40 / 08:23:06)

* `TSQLiteSymbolStore.Create` builds its prepared SELECTs (`PrepareStatements`) only when
  `IsSchemaCurrent` (stored `schema_version >= SCHEMA_VERSION`). A read-only open of an
  OLDER index therefore leaves every prepared query nil; the first reader that touches one
  (TLibraryOracle -> FindSymbolsByExactName) dies with an access violation.
* With SCHEMA_VERSION 24 every library index (built at 23) is older. 556ad9d7e made
  `OpenLibraryStores` SKIP such a library: no AV there, but every bind runs WITHOUT the
  library until it is re-parsed (9 library-dependent guards failed: "ancestry stops at
  TComponent"), and three other openers (PPUnitSource.OpenStores.OpenAll, the lint-tree
  store factory in CLI.pas, CLI.UsesRecover.LoadSourceNames) were still unguarded.
* Read verbs that check `IsSchemaCurrent` refuse a project index one version old, although
  nothing they read changed.

## Options

A. Keep SCHEMA_VERSION 23; EX2's three tables stay additive + probed (149 INT's choice).
   Safe, but every future additive table repeats the argument and the version stops meaning
   anything.
B. Bump to 24 and skip / refuse stale indexes (556ad9d7e): safe from AVs once every opener is
   guarded, but functionally degraded until every library and project DB is re-parsed (hours;
   the libraries are re-parsed FIRST after a deploy, so the window is the re-parse itself plus
   any machine that has not re-parsed yet).
C. **Read-compat range** (chosen): `SCHEMA_READ_MIN` (= 23) <= stored <= SCHEMA_VERSION opens
   for READING with full functionality; a WRITER at stored < SCHEMA_VERSION upgrades through
   `Migrate` exactly as today; stored < SCHEMA_READ_MIN is refused with a named reason.
D. Per-reader feature probes only (no range): every reader already probes the additive
   tables, but the nil-statement trap is in the constructor, not in the readers -- D does not
   remove the AV.

## Chosen design (C)

1. `DRagLint.Storage.Schema`:
   * `SCHEMA_READ_MIN = 23` -- the oldest stored schema this engine READS without migrating.
   * `function IsSchemaReadable(AFound: Integer): Boolean` = `AFound >= SCHEMA_READ_MIN`.
     A NEWER index (AFound > SCHEMA_VERSION) stays readable, as today (`IsSchemaCurrent`
     returned True for it); writers keep refusing it (`EIndexNewerThanEngine`,
     `RefuseIfEngineOlderThanDb`).
   * `function SchemaUnreadableReason(AFound: Integer): string` -- the one refusal text:
     `index schema vN is older than this engine reads (vREAD_MIN..vSCHEMA_VERSION); re-index it`
     (`v0` = not a drag-lint index / no schema_meta).
2. `TSQLiteSymbolStore.Create` prepares its statements when `IsSchemaReadable` (was
   `IsSchemaCurrent`). That single line is what makes a 23 library usable by a 24 engine:
   every caller that opened it and then queried now gets working statements.
3. `TSQLiteSymbolStore.OpenReadable(ADbPath, out AReason): ISymbolStore` -- the ONE opener
   predicate for read-only store construction: opens read-only, probes the schema, returns
   nil + `SchemaUnreadableReason` below READ_MIN (store released), nil + the exception text
   when the open fails. Unguarded and hand-rolled sites call it instead of
   `TSQLiteSymbolStore.Create(Db, True)` + their own check.
4. `IsSchemaCurrent` keeps its meaning (stored >= SCHEMA_VERSION = "no migration pending"),
   used by WRITERS and by "needs re-index" notes; READ gates move to `IsSchemaReadable`.

### Invariant that makes the range sound

Everything between SCHEMA_READ_MIN and SCHEMA_VERSION is ADDITIVE and PROBED: a reader of a
table or column added after READ_MIN checks for it (`HasFileFacts`, `HasDataFlows`,
`HasMemberAccesses`, `FindField`, `TableExists`) and degrades to "no rows". The 24 additions:

| added in 24 | writer | readers (all probe) |
|---|---|---|
| file_includes (F4) | PutFileFacts | GetFileIncludes -> `if not HasFileFacts then Exit` |
| dfm_objects (F5) | PutFileFacts | GetDfmObjects -> `if not HasFileFacts then Exit` |
| pp_regions (F6) | PutFileFacts | GetPpRegions -> `if not HasFileFacts then Exit` |

(`PutFileFacts` itself also checks `HasFileFacts`.) Any 150 lane that adds schema to 24
(EX3 project fact, W2 comment facts) MUST add a probe and a row here; a non-probed reader is
a defect against this spec. If a change cannot be made additive, it raises SCHEMA_READ_MIN to
the new version in the same commit (and the range collapses to "current only" -- option B).

### Reversible assumptions

* READ_MIN = 23, not lower: v20-v22 also only added columns, but nothing proves every reader
  of those probes; refusing them costs one re-index of an index older than 1.29.
* A refused (< READ_MIN) library is SKIPPED by the library openers with the reason as a note
  (556ad9d7e's behaviour); a refused PROJECT index on a read verb exits with the existing
  stale-schema exit code and text, now naming the readable range.
* Library readiness (`ProbeLibraryReadiness`) reports a readable-but-older library as ready
  for READING; the extractor-version stamp (not the schema) still decides "stale-extractor".

## Proof (guard `tests\autotest\run_schema_read_compat.ps1`)

* Fixture library at schema 23 (built by the base engine from tests fixtures) + a project
  fixture whose ancestry needs it; a 24 engine (lane wt with SCHEMA_VERSION 24 for the repro
  ONLY, or INT's real flip): `index --library-db`, `lint-all` with a pp-unresolved rule,
  `lint-tree`, `uses-recover` -- exit 0/1, no EAccessViolation, and "ancestry stops at
  TComponent" must NOT appear (positive control: the same arm on the base 1.49 build at 24
  without this change shows the AV / the skip).
* A hand-downgraded schema-22 copy is refused with `SchemaUnreadableReason` text, no AV.
* The guard takes `-Exe` (default: the wt build) so INT reruns it on the real 24 flip.

## Docs

`schema` verb output prints the readable range; docs\wiki\Index-DB-Schema.md:
"23 readable by 24; re-index to write".
