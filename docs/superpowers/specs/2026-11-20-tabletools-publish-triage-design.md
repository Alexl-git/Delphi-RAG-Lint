# TableTools remainder -- publish-fb, column triage, FIB$ removal inventory (design)

Date: 2026-11-20. Lane SPEC-TT of the v1523 run (unattended; owner away until Sat 2026-11-21 ~19:00).
Status: DESIGN (controller reviews). Covers TableTools migration step M17 (`repo publish-fb`), spec phase 9
(column triage) and the FIB$ run-time reader inventory. Product code: none in this lane.

Parent design (read it for the table map, file format and verbs): `C:\Projects\Delphi-RAG-lint\docs\superpowers\specs\2026-11-16-tabletools-into-dl-design.md`
(sections 1a, 2.3, 3, 4, 8, 11). NOTE: that file and its phase-1 plan are UNTRACKED in the main working tree
(not in git on main or lane/v1522-int); lanes read them by the absolute path above.

Plans (one per lane, each executable alone):

| Lane (wave) | Plan |
|---|---|
| TT-PUBLISH (W3) | `docs\superpowers\plans\2026-11-20-tt-publish-fb.md` |
| TT-TRIAGE (W3) | `docs\superpowers\plans\2026-11-20-tt-column-triage.md` |
| TT-FIBREMOVE (W3) | `docs\superpowers\plans\2026-11-20-tt-fib-removal.md` |
| TT-PUBLISH-UI (W4, after TT-PUBLISH + TT-TRIAGE merged) | `docs\superpowers\plans\2026-11-20-tt-publish-ui.md` |

## 0. Binding rulings and defaults (no owner on hand -- recorded, not asked)

| Source | Ruling | Effect here |
|---|---|---|
| A1 (2026-11-17) | DL is the target master; Firebird keeps a copy until development is complete; later FIB$ removed or a secondary copy fed from DL | publish-fb = the "fed from DL" path. FIB$ is never dropped in this run |
| A4 | FIB$VERSION not carried in DL | publish never writes FIB$VERSION on UPDATE; see 2.5 for INSERT |
| Q8 DEFAULT a (v1523) | dry-run default; `--apply` needs an explicit `--connection`; tested ONLY on a scratch Firebird copy | 2.1, 2.6, plan TT-PUBLISH task 6 |
| Q9 DEFAULT a (v1523) | DL side only: inventory + plan + note to ORM3; no ORM3 edits, no DROP; triage = usage report + schema v2 migration behind dry-run; no column dropped without owner ruling | sections 3 and 4 |
| PLAN rule 8 | Firebird read-only everywhere; TT-PUBLISH writes only to a scratch DB copy it created | plan TT-PUBLISH task 6 fence |
| SPEC-TT decision D1 | Deletes in Firebird (rows in FIB$ but not in DL) are listed, and applied only with `--delete-missing` | 2.3 |
| SPEC-TT decision D2 | Triage fates live in a new table `DL_COLUMN_FATE` (schema v2), seeded with the default fates of 3.2; owner rulings change them by editing the text backup (reviewable diff) and `repo restore` | 3.3 |
| SPEC-TT decision D3 | `repo migrate` is dry-run by default, `--apply` writes (same shape as gen-orm), after a `before-migrate` text backup | 3.4 |
| SPEC-TT decision D4 | The editor grid is NOT changed by triage (PLAN listed FieldRepoEd.Grid.pas; dropped: nothing to show until the owner rules). Form.pas gets one line so DL_COLUMN_FATE is not an editor tab | plan TT-TRIAGE |
| SPEC-TT decision D5 | The ORM3 note is a file the controller forwards; it is committed in DL as part of `docs\PLAN-fib-removal.md` (section "Note to ORM3"), never written into the ORM3 tree | section 4 |

Brainstorming gate: skipped (owner away; Q8/Q9 defaults are binding). Every choice above is reversible
without data loss: nothing in this design drops a column, a table or a FIB$ row unless `--delete-missing`
is given together with `--apply`.

## 1. Facts this design rests on (read live 2026-11-20, read-only)

* `FIB$FIELDS_INFO` 2117 rows, `FIB$DATASETS_INFO` 134, `FIB$ENUMVALUES` 51, `FIB$ERROR_MESSAGES` 0 (dev DB
  `C:\Projects\DB\SQL\MICRONITEV6A.FDB`, firebird MCP, SELECT only).
* Triggers: `FIB$DATASETS_INFO_BI/_BU` and `BI_/BU_FIB$ERROR_MESSAGES` ACTIVE; `FIB$FIELDS_INFO_BI/_BU` INACTIVE
  (every FIB$FIELDS_INFO.FIB$VERSION is 0).
* Non-default rows in FIB$FIELDS_INFO (of 2117): ALIGNMENT<>0 1097, VISIBLE=false 1375, FIELD_KIND<>0 2049,
  DISPLAY_LABEL 650, DEFAULTVAL 558, DISPLAY_WIDTH 553, DISPLAY_FORMAT 127, SEQUENCE_NAME 73, TRIGGERED 68,
  ISENUM 31, ENUMTYPE 31, CUSTOM_TYPE 31, UI_TAG 20, LOADFIELD 5, SAVEFIELD 5, ISCALCULATED 3;
  ZERO: EDIT_FORMAT, BG_COLOR, FG_COLOR, ISLOOKUP, DESTTABLE, SOURCEKEY, DESTKEY, DESTVALUE, DOCUMENTATION,
  UNIQUE_FLAG, real DOC_SUMMARY / DOC_REMARKS (all still 'Summary here' / 'Remarks here').
  FIB$DATASETS_INFO: CONDITIONS 0 of 134, NAME_GENERATOR 73, UPDATE_ONLY_MODIFIED_FIELDS=false 1.
  FIB$ENUMVALUES: DOCUMENTATION 0 of 51, EVALUE 51.
  (The 2026-11-16 spec listed CUSTOM_TYPE / SAVEFIELD / ALIGNMENT among neither list; they ARE used.)
* ORM3 index text hits for `FIB$` (query --text --substring, read-only): server DB 50 matches, client DB 43;
  run-time readers are the `[literal]` / `[format]` hits in `SERVER\uFIB_*_SERVER.pas`, `uDatasetsDef.pas`,
  `uPipeSessionBuilder.pas`, `uGenericTableRoute.pas`, `CLIENT\Blueprint4.ViewModel.pas`; the rest are comments.
* DL code (lane/v1522-int 45291e060): `DRagLint.FieldRepo.Schema` (RepoTables, OpenRepository rejects
  user_version <> 1), `FbImport` (OpenSourceConnection, CheckSourceColumns, dataset-fed import),
  `TextBackup` (`#DLREPO 1` magic, generic over RepoTables), `CLI.Repo` (sub-verbs, flags read with
  CommandLineFlag/CommandLineValue; `CLI.pas` ParseArgs raises on an unknown flag, so a NEW flag needs a
  one-line hub commit), editor `FieldRepoEd.Form` (button bar, no main menu), plugin
  `DragLint.Plugin.Cmd.FieldRepo` (six rows under `drag-lint > Field Repository`, `RunDryThenApply` helper).

## 2. `repo publish-fb` (M17)

### 2.1 Surface

```
drag-lint repo publish-fb --connection "<Firebird connection string>" (--repo <file> | --project <project file>)
                          [--table <DL_X,...>] [--apply [--delete-missing]] [--json]
```

* Without `--apply`: dry run. Reads FIB$ rows, prints the diff, writes NOTHING anywhere (not even DL_META).
* `--apply`: same diff, then writes it to Firebird in ONE transaction, then re-reads and verifies.
* `--delete-missing` (new flag, only with `--apply`): also deletes FIB$ rows whose key is not in DL.
* `--table`: limit to the named DL_ tables (default: DL_FIELDS_INFO, DL_DATASETS_INFO, DL_ENUMVALUES,
  DL_ERROR_MESSAGES). DL_META and DL_COLUMN_FATE are never published.

### 2.2 Diff model

Per table, rows are matched by primary key (RepoTables PkOrder). Four outcomes per key:
`insert` (in DL only), `update` (both, at least one non-PK column differs; the changed columns are listed),
`delete` (Firebird only), `same`. Comparison is exact: NULL <> '' ; text compared code unit by code unit,
no trim; boolean as boolean; integer/smallint/byte as integers. FIB$VERSION is ignored on both sides.

Dry-run output (text): one header line per table `<DL table> -> <FIB$ table>: insert <i>, update <u>,
delete <d> (kept|applied), same <s>`, then per non-same row one line
`  + [<pk>]`, `  ~ [<pk>] COL1, COL2`, `  - [<pk>]` in PK order, capped at 200 lines per table with
`  ... <n> more` (the counts are never capped). `--json`: `{"tables":[{"table","source","insert","update",
"delete","same","rows":[{"op","key","columns"}]}],"applied":bool,"database":"<Database value only>"}`.

### 2.3 Acceptance criteria (EARS)

* P1 THE publish SHALL be a dry run unless `--apply` is given, and a dry run SHALL open the Firebird
  connection read-only in intent: no INSERT/UPDATE/DELETE statement is prepared or executed.
* P2 IF `--apply` is given without `--connection` THEN the verb SHALL exit 1 before opening anything
  (there is no default, config or environment connection for publish).
* P3 IF a FIB$ table's columns differ from the DL table's columns (FIB$VERSION excepted) THEN the verb
  SHALL exit 2 naming the extra/missing columns and SHALL write nothing (reuses CheckSourceColumns).
* P4 IF a FIB$ table is missing THEN the verb SHALL exit 2 and write nothing (publishing creates no tables).
* P5 WHEN `--apply` is given THE verb SHALL first write `<repo>.before-publish-<yyyymmdd-hhnnss>.txt`, a
  `#DLREPO` text backup of the Firebird side as read (all published tables), and print its path; this file
  restored into a fresh repository and published back undoes the publish.
* P6 WHEN `--apply` is given THE verb SHALL apply every insert and update (and, with `--delete-missing`,
  every delete) in ONE Firebird transaction; any error SHALL roll back the whole publish and exit 1.
* P7 WHEN the apply commits THE verb SHALL re-read the FIB$ tables and exit 0 only when the new diff is
  empty (deletes excepted when `--delete-missing` was not given); otherwise exit 1 naming the first
  differing key.
* P8 IF `--delete-missing` is not given THEN Firebird-only rows SHALL be kept and reported as `delete <d> (kept)`.
* P9 THE verb SHALL never write FIB$VERSION in an UPDATE; an INSERT SHALL set FIB$VERSION = 0 (the value of
  every existing FIB$FIELDS_INFO row; an active BI trigger overwrites it).
* P10 THE verb SHALL write EVALUE (rckByte) as a one-byte BINARY(1) value and SHALL read it back equal.
* P11 THE verb SHALL never print, log or store the connection string or password; DL_META gets
  `published_at_utc` and `published_to` (Database value only) after a committed apply, nothing after a dry run.
* P12 THE verb SHALL print, after a committed apply, the line
  `note: a running Micronite server caches FIB$FIELDS_INFO -- restart it to see the change`.
* P13 Round trip: WHEN a repository imported from database X is edited (one caption changed, one row added,
  one enum string changed) and published to X with `--apply`, THEN `repo import-fb --replace` from X into a
  second repository SHALL give a text backup equal byte for byte to the edited repository's backup
  (DL_META lines excepted).

### 2.4 Testability without Firebird

The diff and the writer are separated behind an interface so the battery needs no Firebird:

* `ComputePublishDiff(pRepo: TFDConnection; const pTable: TRepoTable; pTarget: TDataSet): TPublishTableDiff`
  -- target fed from any TDataSet (TFDMemTable in tests, a FB query live).
* `IPublishSink` (Insert / Update / Delete of one row by key) with two implementations: a recording sink
  (tests) and `TSqlPublishSink` over any TFDConnection, generating dialect-neutral SQL with quoted
  identifiers (`"FIB$FIELDS_INFO"`) and parameters. The SQL sink is tested against a SCRATCH SQLITE file
  holding tables named `"FIB$..."` with the same columns (+ FIB$VERSION) -- this exercises the real SQL text,
  binding, transaction and verify loop without Firebird. Only BINARY(1) binding differs; it gets its own
  live check (P10) in the scratch-Firebird step.

### 2.5 Not in scope

No DDL against Firebird, no trigger/generator changes, no publish of DL_META/DL_COLUMN_FATE, no automatic
publish from the editor without the confirm step, no publish to a database other than the one named by
`--connection`.

## 3. Column triage (spec phase 9)

### 3.1 What triage is in this run

Report + reversible schema change; nothing is dropped. Two verbs:

```
drag-lint repo triage  (--repo <file> | --project <project file>) [--json]          read-only usage report
drag-lint repo migrate (--repo <file> | --project <project file>) [--apply]         v1 -> v2, dry run by default
```

### 3.2 Default fates (owner may overrule each row; a later v3 acts only on `retire-candidate` rows the owner turned into `retire`)

Fate values: `keep` (hand-maintained, used), `schema-cache` (overwritten by refresh-schema),
`keep-planned` (unused today, named in the owner's concept or read by a DL generator),
`retire-candidate` (unused, no planned use), `retire` (owner ruling only; never seeded).

| Table | Columns | Fate | Reason |
|---|---|---|---|
| DL_FIELDS_INFO | TABLE_NAME, FIELD_NAME | keep | primary key |
| DL_FIELDS_INFO | FIELD_AS_TYPE, VAR_TYPE, FIELD_SIZE, STRING_SIZE, NULL_FLAG, FIELD_KIND, FIELD_TYPE, FIELD_SUBTYPE, FIELD_LENGTH, FIELD_SCALE, PRIMARY_KEY, SEQUENCE_NAME, TRIGGERED | schema-cache | written by refresh-schema (spec 2.1) |
| DL_FIELDS_INFO | DISPLAY_LABEL, VISIBLE, DISPLAY_FORMAT, DISPLAY_WIDTH, ALIGNMENT, DEFAULTVAL, ISENUM, ENUMTYPE, CUSTOM_TYPE, LOADFIELD, SAVEFIELD, UI_TAG, ISCALCULATED | keep | non-default rows in section 1 |
| DL_FIELDS_INFO | DOC_SUMMARY, DOC_REMARKS | keep-planned | read by repo gen-orm / update-orm (Documentation regions) |
| DL_FIELDS_INFO | EDIT_FORMAT, ISLOOKUP, DESTTABLE, SOURCEKEY, DESTKEY, DESTVALUE | keep-planned | "edit format" and "lookup wiring" are in the owner's repository concept (spec 1) |
| DL_FIELDS_INFO | BG_COLOR, FG_COLOR | retire-candidate | 0 rows; a BOOLEAN colour carries no colour |
| DL_FIELDS_INFO | DOCUMENTATION | retire-candidate | 0 rows; duplicates DOC_SUMMARY |
| DL_FIELDS_INFO | UNIQUE_FLAG | retire-candidate | 0 rows; unique constraints belong to the schema index (phase 3) |
| DL_DATASETS_INFO | all but CONDITIONS | keep | SQL text is generated and read at run time |
| DL_DATASETS_INFO | CONDITIONS | retire-candidate | 0 of 134 rows (pending the TT-FIBREMOVE reader list: if an ORM3 reader reads it, keep-planned) |
| DL_ENUMVALUES | all but DOCUMENTATION | keep | enum values (ruling A4) |
| DL_ENUMVALUES | DOCUMENTATION | keep-planned | enum code generation (A4) |
| DL_ERROR_MESSAGES | all | keep-planned | table empty; schema kept (spec 3) |

The default rows carry `RULED_BY = 'default-2026-11-20'`.

### 3.3 Schema v2

* New table `DL_COLUMN_FATE` (in RepoTables, after DL_ERROR_MESSAGES): `TABLE_NAME VARCHAR(63) NOT NULL` (pk 1),
  `COLUMN_NAME VARCHAR(63) NOT NULL` (pk 2), `FATE VARCHAR(20) NOT NULL`, `REASON VARCHAR(220)`,
  `RULED_BY VARCHAR(63)`. No Firebird source (SourceName ''). Not an editor tab; not published; not
  counted by RepoIsEmpty; carried by the text backup like any other table.
* `REPO_SCHEMA_VERSION = 2`; `repo init` creates v2 with the default fate rows.
* OpenRepository accepts user_version 1 and 2 and validates the table set OF THAT VERSION (v1 = the five
  v1 tables, v2 = six). A v1 repository keeps working everywhere; triage on v1 reports the static defaults.
* Text backup: a v2 repository writes `#DLREPO 2`; a v1 repository writes `#DLREPO 1` exactly as today.
  Restore accepts both: a `#DLREPO 1` file into a v2 repository restores the five tables and re-seeds
  DL_COLUMN_FATE with the defaults; a `#DLREPO 2` file into a v1 repository is refused (exit 2, "migrate first").
  `repo restore` into a MISSING repository creates it at the FILE's version (a `#DLREPO 1` file gives a v1
  repository), so the existing golden fixtures (`tests\fixtures\fieldrepo`, `#DLREPO 1`) keep their byte
  round trip (run_repo_cli_roundtrip.ps1 R2/R3) unchanged. Only `repo init` and import/seed into a missing
  file create v2.

### 3.4 Acceptance criteria (EARS)

* T1 THE `repo triage` verb SHALL open the repository read-only and print, per column of the four data
  tables: rows, non-null, non-default, fate, reason; `--json` gives the same as an array.
  Non-default = NOT NULL and differs from the DDL default; for a column without a default, NOT NULL and
  not '' (strings) / not 0 (numbers) / not false (booleans).
* T2 IF a column whose fate is `retire-candidate` or `retire` has non-default rows THEN `repo triage` SHALL
  mark it `CONFLICT` and exit 1 (a database other than Micronite uses it; the owner must rule).
* T3 THE `repo migrate` verb SHALL be a dry run without `--apply`: print `v1 -> v2: create DL_COLUMN_FATE,
  seed <n> rows, user_version 2` and change no byte of the file (file hash before = after).
* T4 WHEN `repo migrate --apply` runs on a v1 repository THE verb SHALL write
  `<repo>.before-migrate-<yyyymmdd-hhnnss>.txt` first, then create + seed + set user_version and
  DL_META schema_version in ONE transaction.
* T5 WHEN `repo migrate` runs on a v2 repository THE verb SHALL print `already at schema 2` and exit 0.
* T6 THE migration SHALL drop, rename or alter no column: every v1 column and every row value is unchanged
  (backup of the migrated repo = the v1 backup with `#DLREPO 2` and the DL_COLUMN_FATE block added).
* T7 Byte round trip, both versions: restore(F) then backup SHALL equal F byte for byte for a `#DLREPO 1`
  file into a v1 repository and for a `#DLREPO 2` file into a v2 repository.
* T8 IF a fate value is not one of the five fate words THEN `repo triage` SHALL report it as an error with
  table and column, exit 1.

## 4. FIB$ removal inventory (DL side only)

### 4.1 Surface

```
drag-lint repo fb-readers --db <index DB of the consuming project> [--all] [--json]
```

Read-only over a drag-lint index DB (the ORM3 server and client DBs, ALWAYS a copy in a lane). Needs no
repository (dispatched before the repository path is resolved, like gen-param-array).

### 4.2 Classification

Input: every text hit of `FIB$` (store SearchText, substring mode, pas + dfm + sql sources).
Each hit gets one class:

| Class | Rule |
|---|---|
| `sql-write` | literal/format text containing INSERT, UPDATE, DELETE, `UPDATE OR INSERT`, MERGE together with FIB$ |
| `sql-read` | literal/format text containing SELECT ... FROM ... FIB$ (or a FIB$ table in a JOIN) |
| `pipe-table` | literal/format text `TABLE=FIB$...` (pipe protocol table load) |
| `name-literal` | any other literal/format naming a FIB$ table or the FIB$FIELD_INFO_VERSION generator |
| `mention` | comment / doc hits; listed only with `--all` |

Output rows are grouped by enclosing routine: `file, routine, class, table(s), first line`. A reader =
a routine with at least one non-mention hit. Exit 0; exit 2 on an unreadable DB.

### 4.3 Acceptance criteria (EARS)

* R1 THE classifier SHALL be a pure function over `TArray<TStringLitMatch>` (testable without a DB).
* R2 WHEN run on the fixture project (`tests\fieldrepo\fbreaders\`, indexed into a temp DB by the runner)
  THE verb SHALL list exactly the fixture's planted readers with the planted classes, and SHALL list the
  planted comment only with `--all` (positive and negative control in one test).
* R3 THE verb SHALL open the DB read-only and SHALL never write to it (DB size and mtime unchanged).
* R4 `docs\PLAN-fib-removal.md` SHALL list every reader the verb reports on copies of the ORM3 server and
  client DBs (counts in the doc equal the verb's counts), each with a replacement and a stage:
  stage 1 (now) FIB$ stays as a secondary copy fed by `repo publish-fb`; stage 2 (ORM3 team, later) the
  reader switches to the replacement; stage 3 (owner ruling) DROP. Nothing in ORM3 is edited.

## 5. Publish UI (W4)

* Editor: a sixth toolbar button `Publish to Firebird...` (the editor has a button bar, not a File menu;
  the PLAN's "File > Publish" is realised as this button). Flow: save pending edits -> ask the connection
  string (masked) -> run the dry run in-process (same unit as the CLI) -> show the per-table counts and
  first 30 diff lines -> confirm -> apply -> status `published: <i> inserts, <u> updates` or the error.
  `--delete-missing` is NOT offered in the UI (CLI only).
* IDE: a seventh row `drag-lint > Field Repository > Publish to Firebird...` (id
  `field-repository-07-publish`) running `repo publish-fb --project ... --connection "..."` dry run, then
  confirm, then `--apply` (the existing RunDryThenApply helper).
* U1 THE editor self test SHALL exercise the publish dry run against a scratch SQLite target with FIB$-named
  tables (no Firebird) and print `PASS publish-dry-run`.
* U2 THE editor and the IDE row SHALL never apply without a confirm after a dry run that exited 0.
* U3 The registry entry `field-repository` SHALL carry the full menu path
  `drag-lint > Field Repository > Publish to Firebird...` and the cli sub `publish-fb`, and
  `featuregen blast-radius --menu-path "drag-lint > Field Repository"` SHALL be run before the change.

## 6. Risks

1. First DL code that WRITES Firebird. Fences: dry-run default, explicit connection, one transaction,
   pre-publish backup, verify-after, scratch-only testing; the lane report names every Database value used.
2. `gbak -b` on the dev DB garbage-collects unless `-g` is given: the scratch copy procedure uses `-g`.
3. Credentials: no lane has them by contract. The live steps run only when `DL_TEST_FB_CONNECTION` (pointing
   at the SCRATCH copy) is set; otherwise they SKIP and become an owner step on the test page.
4. Schema v2 touches Schema.pas / TextBackup.pas that other TT features read: the v1 path must stay
   byte-identical (T7) and every existing fieldrepo test must stay green.
5. Running Micronite server caches FIB$FIELDS_INFO: a publish is invisible until restart (P12).
6. CONDITIONS fate depends on the reader inventory; TT-TRIAGE seeds `retire-candidate`, TT-FIBREMOVE
   reports if a reader reads it and the controller flips the default before merge.
7. Three W3 lanes edit `src\cli\DRagLint.CLI.Repo.pas` (publish-fb, triage/migrate, fb-readers). Each keeps
   its logic in its own unit and its CLI.Repo edit in ONE separate `hub:` commit; the INT step unions the
   `IsImplementedSub` / `SUB_VERBS` lines. The PLAN.md W3 file lists for TT-TRIAGE and TT-FIBREMOVE did not
   name CLI.Repo.pas; the plans here add it (and new CLI units) -- controller grants.
8. Schema v2 changes what `RepoTables` returns: every caller (CLI.Repo RepoInfo/RepoRestore, TextBackup,
   editor Form/SelfTest) must use the repository's own version's table set or the v1 path breaks.
