# field-repository

The field repository is the TableTools field registry (`FIB$FIELDS_INFO`,
`FIB$DATASETS_INFO`, `FIB$ENUMVALUES`, `FIB$ERROR_MESSAGES`) kept in ONE SQLite file
(`.dlrepo`) instead of tables in the Firebird database. The five tables are `DL_META`,
`DL_FIELDS_INFO`, `DL_DATASETS_INFO`, `DL_ENUMVALUES` and `DL_ERROR_MESSAGES`.
**Firebird is not modified**: every verb that reads it only runs SELECTs. The one exception is
`repo alter-table --apply` ([[repo-alter-table]], 1.54).

## Where the repository lives

One repository per DATABASE: Firebird table names are unique within one database, so
several projects that use the same database share one repository file.

Path resolution, first match wins:

1. `--repo <file>`.
2. The `fieldRepository` key of `<project folder>\_D-RAG\drag-lint-project.json`
   (relative to the project folder), when `--project <project file>` is given:
   `{ "fieldRepository": "..\\SERVER\\_DL-REPO\\Micronite.dlrepo" }`.
3. `"fieldRepository"` on the project's section of the manifest `drag-lint.json` (next to its database path).
4. The default for `--project`: `<project folder>\_DL-REPO\<project base name>.dlrepo`.

`drag-lint resolve-dbs --project <x.dproj>` names the result: `repo: <path>` (or `repo: none`) on stderr, and
a `"repo"` key in its `--json` object; stdout stays the bare database path. The resolver is one unit,
`DRagLint.FieldRepo.Locate`.

Neither `--repo` nor `--project`: usage error, exit 1.

## The verbs

```
drag-lint repo init           (--repo <file> | --project <project file>)
drag-lint repo info           (--repo <file> | --project <project file>) [--json]
drag-lint repo import-fb      --connection "<Firebird connection string>" (--repo | --project) [--replace]
drag-lint repo seed-fb        (--connection "<Firebird connection string>" | --ddl <file.sql>[;...]) (--repo | --project) [--apply | --select <id file>] [--json]
drag-lint repo refresh-schema (--connection "<Firebird connection string>" | --ddl <file.sql>[;...]) (--repo | --project) [--apply | --select <id file>] [--json]
drag-lint repo backup         (--repo | --project) [--output <file>]
drag-lint repo restore        --in <backup file> (--repo | --project) [--replace]
drag-lint repo gen-memtable   --in <csv file> [--name <Name>] [--output <file>]
```

| Verb | What it does | Exit |
|---|---|---|
| `init` | Creates an empty repository (all five tables) and prints its path. | 0; 1 when the file exists |
| `info` | Path, schema version, rows per table and the `DL_META` keys; `--json` prints one object (`path`, `schema_version`, `tables`, `meta`). | 0; 1 when the file is missing or not a repository |
| `import-fb` | The Micronite path: copies the four `FIB$` tables as they are (the `FIB$VERSION` column is not carried). Creates the repository when missing. A non-empty repository needs `--replace`, which first writes `<repo>.before-import-<yyyymmdd-hhnnss>.txt` (a text backup) and prints its path. Prints `<table>: <n> rows (source <m>)` per table; exit 0 only when every n equals m. | 0; 1 failure; 2 when a source table does not match the repository columns (nothing written) |
| `seed-fb` | The non-Micronite start: fills an EMPTY repository from the Firebird schema (`--connection`) or a DDL script (`--ddl`). It prints the change set (all inserts, checked) and writes NOTHING unless `--apply` or `--select <id file>` is given. | 0; 1 (not empty, no or two sources, read error) |
| `refresh-schema` | The old "Update Fields Info", as a change set (db-to-repo): new tables, fields, domains, constraints and generators are checked inserts, changed schema-derived values are checked updates, rows whose source vanished are UNCHECKED deletes. Hand-kept columns never appear. No flag = dry run; `--apply` writes the checked changes and keeps the vanished rows; `--select <id file>` writes exactly the listed ids (one per line or `all`), which is how a vanished row is deleted. | 0; 1 |
| `backup` | Writes the diffable text backup (default `<repo>.txt`). Deterministic: the same rows give the same bytes. | 0; 1 |
| `restore` | Reads a text backup into the repository, creating it when missing. A non-empty repository needs `--replace`. The whole file is validated first; a malformed file prints `line <n>: ...` and changes nothing (a missing repository is not left behind). | 0; 1; 2 malformed backup |
| `gen-memtable` | Prints (or writes with `--output`) the Pascal source of `Create<Name>Fields`, a procedure that builds the fields of a `TFDMemTable` from a CSV (`FieldName,FieldType,Size,FieldKind,...`). `--name` defaults to `FDMemTable`. | 0; 1; 2 bad CSV |

## gen-orm, update-orm, upgrade-orm-headers, gen-dataservice

Ports of the TableTools ORM / DataService generators, fed by `DL_FIELDS_INFO` (rows with `FIELD_KIND = 1`).
Every verb prints a dry-run diff (`new` / `changed` / `unchanged` per file, then the hunks) and writes only with
`--apply` (7-bit ASCII; an existing file is first copied to `<file>.BCKn` unless `--no-backup`).

| Sub-verb | Folders | What it writes |
|---|---|---|
| `gen-orm` | `--code-dir` | new `i<T>.PAS` + `u<T>.PAS` per table (`--table T,...`; empty = every table) |
| `update-orm` | `--code-dir` [`--server-dir`] [`--client-dir`] | ONLY the lines inside the `{$REGION 'DB-RAD <id>'}` regions of the existing units; every other byte, line ends included, is kept. A missing file or a table without `FIELD_KIND = 1` rows is skipped and named |
| `upgrade-orm-headers` | `--code-dir` | one time (1.54): in the existing `u<T>.PAS`, the generated text AROUND regions 4 / 6 (`if not (Source is T) then inherited else with Source as T do`) becomes `if Source is not T then inherited else`, and the `StreamSize` / `ByteTemp` locals of `Reader` go when nothing uses them. Only the exact generated shape is recognised, in any layout; a hand-edited header is listed as `skipped` and left alone |
| `gen-dataservice` | `--server-dir` `--client-dir` | new `u<T>_SERVER.PAS` + `u<T>_CLIENT.PAS` and the two DI container units; prints `add to project:` per new file |

**Assign / AssignTo (1.54).** TableTools wrote `fX:= X` inside `with Source as T do` and `X:= fX` inside
`with Dest as T do`: both copy the other object onto itself, so nothing was ever copied. Regions 4 / 6 now name
both objects (`var LSource:= TmcT(Source); Self.fX:= LSource.X;`), which is right inside the old `with` header and
without it. A list or stream the generator creates and frees itself (regions 14 / 15: `TStringList`, the stream type) is
copied by content into the receiver's own object (nil source empties it, nil destination or `Source = Self` is skipped); a
class column it does not own (`TPicture`) is copied by reference. `AssignI` and the property setters still
share the list (`AssignI` is unchanged). Order for existing
units: `update-orm`, build, then `upgrade-orm-headers`; commit both. A table with a column named `SOURCE` / `DEST`
needs `upgrade-orm-headers` first (`update-orm` skips such a unit and says so).

Other 1.54 changes of the generated text: a placeholder summary (`Summary here`) becomes `DOCUMENTATION`, or a text
built from the row (`Column CAUSLIST.NAME ("Cause").`), and `Remarks here` is dropped; a column `NAME` gets
`GetNAME` / `SetNAME` (`reintroduce`) instead of `GetZNAME` / `SetZNAME`, so regenerate the `i` and `u` units
together; region 11 declares its own local; a new unit's `uses` lists exactly what its text needs (a column type
added later may need its unit added by hand: the compiler names it). The text needs Delphi 13 (`is not`; inline
`var` alone needs 10.3).

`--save-form legacy|current` picks how region 9 (Save) binds its parameters. `legacy` (the default) is the form
the ORM3 units carry (TableTools before 2026-05-19): the `FIELD_AS_TYPE` accessor (`.AsString`, `.AsInteger`, ...),
`.AsString` for a `TStringList`, `.AsByte` for an enum, a timestamp without a NULL guard. `current` is TableTools
2026-05-19: `.Value`, `.AsWideMemo` (FB-338), `Set1Byte` for an enum, `Clear` when the timestamp `Year = 0`.

Golden (release gate): `tests\autotest\run_fieldrepo_ormgen_golden.ps1 -RequireForm -RepoFile <dev.dlrepo>` runs
`update-orm` over a COPY of ORM3: 521 of 528 units come out the same ignoring blanks and case, 260 of them only
after the 1.54 changes above are turned back (`@region` lines of the drift file), and nothing outside the regions moves; the 7 others are listed with their reason in `tests\fieldrepo\ormgen-golden-known-drift.txt`
(schema drift, a hand-ported unit, a hand-edited region). Byte parity is not the gate: the ORM3 units were
re-formatted after TableTools wrote them.

IDE: **drag-lint > Field Repository > Generate / Update ORM Source...** (pick the `i/u` folder; table names =
`gen-orm`, empty = `update-orm`, optionally with the `_SERVER` / `_CLIENT` folders) and **Generate DataService
Units...** run the dry run, show its summary and write after **Yes**. **Param Array Assistant...** runs
`gen-param-array --plan` on the unit in the active editor (optionally with `--prepare-queries`) and, after
**Yes**, `--apply --project` through the compile gate.

## gen-param-array

`drag-lint repo gen-param-array` ports the TableTools FireDAC Param Array assistant: it reads a unit's
text DFM (the table's fields, the parameterised `TFDQuery`'s params with their types), matches params to
fields by name and type, and produces the Array-DML loop (`Params.ArraySize`, one `Params[parX].AsY[I] :=
tblZ...AsW` line per pair, `Execute(I)` every `STEPSIZE` rows). It needs no repository.

| Call | What it does |
|---|---|
| `--in <unit.pas> [--dfm <file>]` | one unit; the DFM is `<unit>.dfm` beside it unless `--dfm` names it |
| `--project <X.dproj> --all [--only a,b]` | every `u*` unit of the project (the exclusion list: `uFolderCheck`, `uCOMPGRP`, `uTestHelper`) |
| no mode flag | prints the block (what the IDE assistant put on the clipboard) |
| `--plan` | prints the unified diff per unit, writes nothing |
| `--apply --project <X.dproj>` | inserts the block as a braced comment before the final `end.`, through ONE compile gate for the whole run (baseline build, all-or-nothing write under `.BCK<n>`, after build, rollback); a compile error retries once without the units dcc names |
| `--query <Name>` / `--table <Name>` | pick the components by name; the default is the LAST parameterised query and the LAST table. A named component that is absent is exit 1, never a fallback |
| `--step-size <n>` / `--progress-form <Form>` | `STEPSIZE` (default 20000); the loader-form progress lines of the original (default none) |
| `--json` | `{mode, units:[{unit, status, query, table, matched, type_mismatch, missing_params, missing_fields, plan?, block?, error?}], gate?:{applied, refusal, detail, rolled_back}}` |

Status words: `applied`, the plan-only word (a unit that would be written; see `--json`), `refused-by-gate`, `no-insert-point`, `no-block`, `excluded`,
`binary-dfm`, `missing-dfm`; a binary or missing DFM is reported per unit, never skipped silently.
Exit 0 = every processed unit is ready to write or written; 1 = a unit refused, no block (single unit), or the gate
rolled back; 2 = bad flags, a write failure, or a baseline that does not build.

The block is a fragment, not code: a column that does not match leaves a marker line (`##### TYPE
MISMATCH #####`, `// MISSING PARAMS`, `#### MISSING FIELDS ####`) for a human to finish. In 1.52 it is
therefore inserted as a comment, so the compile gate proves "the unit still builds" (and a block holding
`}` is refused before any build); live insertion at a `// dl:param-array` marker follows in 1.52.1.
The Loader2019 comparison is `tests\autotest\run_fieldrepo_paramarray_golden.ps1`: a report of assignment
triples, not text equality.

## Text backup

`repo backup` writes 7-bit ASCII with CRLF line ends and no BOM: fixed table order, rows in
key order, NULL columns left out, one `#end <table> <count>` trailer per table.
`restore(backup(F))` is byte for byte `F`, so the text file is the committed, reviewable form
of the repository; the binary `.dlrepo` is not committed.

## Connection strings

`--connection` is a FireDAC list separated by `;`, for example
`"Database=host:D:\data\micronite.fdb;User=SYSDBA;Password=...;DriverID=FB"`. `DriverID=FB` and
`CharacterSet=UTF8` are added when missing. The password is never printed or stored; the
repository keeps only the `Database` value (`source_database`).

(1.53) A connection string that names `OpenMode`, `CreateDatabase`, `DropDatabase`, `ConnectionDef` or `ConnectionDefName` is refused (import-fb, seed-fb, refresh-schema, fb-snapshot): `DropDatabase=Yes` used to delete the database. `refresh-schema --json` writes exactly one JSON document to stdout; a `--select` id that is not in the change set exits 2.

## Field kinds, schema 2 and `repo migrate` / `repo check` (1.53)

A repository created by 1.53 is **schema 2**; a 1.52 file (schema 1) still opens and is handled as
schema 1 until you run `repo migrate`. Schema 2 adds `DL_FIELDS_INFO.CALC_BODY` (the last column),
`DL_LAYOUT_EVENTS` and `DL_EXCEPTIONS`; nothing is dropped or renamed.

### Field kinds

`DL_FIELDS_INFO.FIELD_KIND` says what a row is (NULL reads as data):

| Code | Kind | Meaning |
|---|---|---|
| NULL / 1 | data | a real table column |
| 2 | calc | calculated; the Pascal body is in `CALC_BODY` |
| 3 | lookup | `SOURCEKEY` = key field(s) here, `DESTTABLE` = lookup table, `DESTKEY` = its key (empty = its primary key), `DESTVALUE` = result field |
| 4 | internal-calc | stored like calc |
| 5 | aggregate | the expression is in `CALC_BODY` |
| 10 | graphical | no data field: a grid column drawn by events |

`ISCALCULATED` must equal "kind is 2 or 4" and `ISLOOKUP` must equal "kind is 3". A calc body names
other fields of the same table with `{{FIELD}}` macros: `{{TOTAL}} := {{QTY}} * {{PRICE}};`
(`{{TABLE.FIELD}}` is reserved and an error; there are no escapes). The dependencies of a calc field are
every macro except its own assignment target.

The per-dataset field selection is NOT stored in the repository: the persistent fields on the dataset
(the DFM) are the selection. Event code of a graphical column on the common `TcxGridDBTableView` layout
stays in the field row; for any other layout type the code lives in `DL_LAYOUT_EVENTS`, keyed by
(`TABLE_NAME`, `FIELD_NAME`, `LAYOUT_TYPE`, `EVENT_NAME`) with the code in `EVENT_CODE`. A field row
"claims" the field; a layout-event row without a field row is a `repo check` finding.

### `repo migrate`

```
drag-lint repo migrate (--repo <file> | --project <project file>) [--apply]
```

Without `--apply` it prints `v1 -> v2: add DL_FIELDS_INFO.CALC_BODY, DOMAIN_NAME, CHAR_LENGTH, create
DL_LAYOUT_EVENTS, DL_EXCEPTIONS, DL_DOMAINS, DL_CONSTRAINTS, DL_CONSTRAINT_COLUMNS, DL_GENERATORS, FIELD_KIND 2 for N ISCALCULATED rows, user_version 2` and changes no byte. With
`--apply` it first writes `<repo>.before-migrate-<yyyymmdd-hhnnss>.txt` (the schema-1 text backup), then
runs one transaction; `FIELD_KIND` becomes 2 for the `ISCALCULATED` rows whose kind is NULL or 1. A
schema-2 file prints `already at schema 2` (exit 0).

### `repo check`

```
drag-lint repo check (--repo <file> | --project <project file>) [--json]
```

Read-only. Reports kind/flag mismatches, lookup wiring that is incomplete or points at an unknown table
or field (a `DESTKEY` that is not the lookup table's primary key is a warning), calc macros that name an
unknown field, calc dependency cycles (named once, `A -> B -> A`) and layout-event rows for an unknown
field. Exit 0 when clean, 1 when there are findings.

### Text backup versions

A schema-2 repository writes `#DLREPO 2` (the two new tables last); a schema-1 file writes `#DLREPO 1`
byte for byte as before. Restoring `#DLREPO 1` into a schema-2 repository is accepted (new tables empty,
`CALC_BODY` NULL); restoring `#DLREPO 2` into a schema-1 file is refused with exit 2 ("migrate first");
restoring into a missing file creates the file at the backup's own version.

### Lint exceptions

`DL_EXCEPTIONS` (rule id or `*`, dataset, table, field, property, reason) lets the schema lint accept a
known deviation; a finding is silenced when every non-empty key column of some row matches it.

## Generated registry unit (`repo gen-const`, `repo check-const`, 1.53)

`repo gen-const` is the read-only replacement for the `FIB$` tables at run time: it turns the repository
into ONE Pascal unit that the SERVER and the CLIENT both use, so neither needs the registry tables in
Firebird.

```
drag-lint repo gen-const (--repo <file> | --project <project file>) [--unit uFieldRegistry] --output <file.pas>
                         [--table DL_X,...] [--datamodule <Name>] [--dry-run]
drag-lint repo check-const (--repo <file> | --project <project file>) --unit-file <file.pas>
```

* **Where it writes.** Only to `--output`; there is no default path. The shared folder (for example
  `ORM3\COMMON`) is your choice at the first generation; the output folder must already exist.
* **Tables.** By default `DL_FIELDS_INFO`, `DL_DATASETS_INFO`, `DL_ENUMVALUES`, `DL_ERROR_MESSAGES`. `--table`
  takes a comma list of these (case-insensitive). `DL_META`, `DL_EXCEPTIONS`, `DL_LAYOUT_EVENTS` and the schema
  tables (`DL_DOMAINS`, `DL_CONSTRAINTS`, `DL_CONSTRAINT_COLUMNS`, `DL_GENERATORS`) are never generated; an
  unknown or refused name exits 2, as does a `--unit` that is not an identifier or a missing `--output`.
  It works on schema 1 and schema 2 repositories (`CALC_BODY` appears in the schema 2 record).
* **Constant arrays (always).** Per table a record `T<TABLE>Row`, `<TABLE>_ROW_COUNT` and
  `<TABLE>_ROWS: array[0..N-1] of T<TABLE>Row` in primary-key order (an empty table gets only the count
  `= 0`: Delphi has no empty constant array). A column that holds a NULL somewhere gets a companion field
  `<Col>IsNull`, set to `True` on those rows. `<TABLE>_FIB_NAME` names the Firebird table it replaces.
  Text is written as 7-bit ASCII literals (`''` for an apostrophe, `#nnn` for control and non-ASCII
  characters, `#13#10` for a line break) in pieces of at most 200 characters joined by `+`, so no line passes
  250 characters.
* **Pre-filled data module (`--datamodule <Name>`).** Writes, INSTEAD of the constant unit, a data module unit and
  its text `.dfm` (class `T<Name>`, one `TFDMemTable` per table named `mt` + the table in PascalCase, for example
  `mtDlFieldsInfo`). The rows are the FireDAC binary `Content` of the form, so `TdmFieldRegistry.Create(nil)` gives open,
  filled, read-only tables under the `FIB$` names, types and sizes (`VARCHAR(n)` as `ftWideString` n, `BOOLEAN` as
  `ftBoolean`, text as `ftWideMemo`; NULL stays NULL), with no fill code. Run the verb twice to have both units. The
  unit name is the `--output` base name (`--unit` may only repeat it: the form is found by that name). No global
  variable is declared: the reader creates the module. `FireDAC.Stan.StorageBin` is in its uses clause.
* **Never edit the generated files.** The repository is the master. If a later Delphi reads the FireDAC stream
  differently, generate again.
* **Repository mark.** Both kinds of unit carry, in the header comment, a SHA-256 per table over its columns and its
  canonical `repo backup` text, one hash over all of them, and that hash again as the constant `REPO_CONTENT_HASH`
  (in the data module a constant of the class). It depends on the content only: not on the file time, `DL_META` or a
  table that is not generated. The data module's header also carries the hash of its `.dfm` (line ends do not count).
* **`repo check-const`** compares those marks with the repository: exit 0 `current`; 1 `STALE`, one line per changed
  table (or the missing / edited form); 2 when it cannot tell (no repository, no unit file, a file without a mark).
  It writes nothing. As a pre-build step of the project that uses the units (Project Options > Building > Build
  Events > Pre-build events, with "Cancel on error"; one line per unit, the path to your `drag-lint.exe` in front):

  ```
  drag-lint.exe repo check-const --project "$(PROJECTPATH)" --unit-file "..\COMMON\DL-REPO\uFieldRegistry.pas"
  drag-lint.exe repo check-const --project "$(PROJECTPATH)" --unit-file "..\COMMON\DL-REPO\uFieldRegistryDm.pas"
  ```

  A build then stops until the units are generated again; a stale unit never reaches the exe unseen.
* **Why preloaded.** Measured 2026-11-22 on 2,229 registry rows, Release, 30 fresh processes each, median time from
  nothing to the first row readable: constants plus generated fill code 31.7 ms (Win32) / 35.9 ms (Win64),
  hand-tuned fill code 21.8 / 23.9 ms, pre-filled data module 12.7 / 12.3 ms, a lookup in the constant array alone
  0.3 / 0.4 ms. Use the arrays where a dataset is not needed, the data module where it is. The fill procedures an
  early 1.53 build offered (`--memtable`) are gone.
* **Deterministic.** The same repository gives the same bytes (7-bit ASCII, CRLF), the form included (two
  uninitialised padding bytes in FireDAC's stream header are set to zero).
* `--dry-run` prints the row count per table and writes nothing.

Proof: `tests\autotest\run_fieldrepo_constgen.ps1` restores the golden fixtures into temp repositories, generates
both units, compiles a probe program against them with `dcc32` and `dcc64`, creates the data module and requires the
dump of its tables to equal `repo backup` of the four tables; it then changes one row and requires `check-const` to
exit 1 naming exactly that table.

## Schema facts in the repository (1.53)

The repository, not the project index, holds what the database says about itself: `DL_DOMAINS`,
`DL_CONSTRAINTS` (PK / UNIQUE / FK with rules), `DL_CONSTRAINT_COLUMNS` (ordered key columns) and
`DL_GENERATORS`, plus `DL_FIELDS_INFO.DOMAIN_NAME` and `CHAR_LENGTH`. The index tables `fb_*` of
`fb-snapshot` are unchanged. `DL_META` records `schema_read_at_utc`, `schema_source` (`live` or `ddl`) and
`schema_database` (the Database value only, never a password). Read them through
`DRagLint.FieldRepo.SchemaFacts` (`HasSchema`, `SchemaInfo`, `ColumnCharLength`, `PrimaryKey`).

`--ddl` reads one or more SQL files offline: CREATE DOMAIN / TABLE / GENERATOR / SEQUENCE and ALTER TABLE ADD
[CONSTRAINT]; CREATE INDEX is ignored, SET TERM blocks are skipped, unknown statements are listed with file and
line as warnings and never stop the run. A malformed CREATE TABLE is an error naming file and line and nothing is
written. With a DDL source only what the DDL declares can be proposed for deletion.

Every change set line reads `[id] op target prop: old -> new`; an unchecked change is followed by `  (unchecked)`
and the header ends `, U unchecked`. Dry runs change no byte of the repository.

### Three databases

The Firebird database is READ; the repository file (`.dlrepo`) is WRITTEN by `repo`; the project index
(`_D-RAG\<project>.sqlite`) holds only code facts and lint findings. Schema-aware features read the repository.

### Banded views are the table family

`TcxGridDBBandedTableView` derives from `TcxGridBandedTableView`, which derives from `TcxGridTableView`. The
banded view adds only four view events (plus the band-header events, which live on the band, not the view), so the
repository treats it as
the same family as the plain table view: one set of column properties, the extra events live in
`DL_LAYOUT_EVENTS`.

## Reading a form

`repo read-dfm` (1.54) reads the persistent fields, lookup wiring and calc code of a DFM: see [Read a form into the field repository](repo-read-dfm).

## Known limits

* Firebird is read only; writing the repository back to Firebird (`repo publish-fb`) is not in
  1.52, so the run-time `FIB$` readers of an application still need their Firebird copy.
* `repo info` of a file that is not a repository, and every other failure, print one line on
  stderr starting with `repo <verb>:` and exit 1.
