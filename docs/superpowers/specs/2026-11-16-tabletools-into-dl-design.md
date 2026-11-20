# TableTools into DL -- field repository, schema index, codegen (design)

Date: 2026-11-16. Owner request, target release 1.52. Status: DESIGN, no product code yet.
Plan for phases 1 + 2: `docs\superpowers\plans\2026-11-16-tabletools-phase1.md`.
Source project (READ ONLY, Mercurial): `C:\Projects\TableTools`.

## 1. Concepts (owner, 2026-11-16)

1. **Delphi has no field repository.** Field properties -- caption, display width, display
   and edit format, alignment, length, visibility, lookup wiring, enum type -- are retyped by
   hand on every form and every dataset. DL keeps them ONCE, centrally, and generates and
   updates code from them. TableTools does this today for the Micronite ORM: it writes the
   `i<TABLE>.PAS` / `u<TABLE>.PAS` units under `C:\Projects\DB\ORM3\COMMON\OBJECTS`
   (290 files) plus `u<TABLE>_SERVER.PAS` / `u<TABLE>_CLIENT.PAS`.
2. **DL learns (indexes) the schema.** A known schema plus the code index gives
   schema-aware lint. First target: constant lengths vs domains. Example:
   `CLIENT\Blueprint4.PDFImport.ViewModel.pas:1300` truncates DIMABBR to 35 while its domain
   `D_ABBR` is 10. DL generates `MSCLIST_DIMNAME_MAXLEN`-style constants from
   `RDB$FIELDS` / `RDB$RELATION_FIELDS`; generated output stays OUT of `{$REGION 'DB-RAD 2'}`.
3. **DL takes over TableTools' duties**; TableTools is retired when DL covers them.
4. **Phase 1 (now):** copy the Firebird registry tables into SQLite, renamed `DL_<...>`,
   keeping their EXISTING structure (unused columns are triaged later). One editing/viewing
   grid per table: `{$IFDEF USE_DevEx_Grid}` TcxGrid, else the standard TDBGrid. FireDAC SQLite.
5. **Phase 2:** backup / restore -- all repository data to a text file and back.

## 1a. Owner rulings 2026-11-17 (answers to section 12) -- THIS BLOCK OVERRIDES THE TEXT BELOW

| Q | Ruling | Effect on this design |
|---|---|---|
| Q1 / A1 | DL is the TARGET master. Until development is complete Firebird keeps a copy (no data loss); later the FIB$ tables are removed or stay a secondary copy fed from DL | 1.52 = import + seed + edit in DL, the Firebird copy is NOT written. `repo publish-fb` (phase 4) stays on the roadmap as the path to "DL master"; until it exists an edit made in DL does not reach the running application -- the editor status bar and the wiki say so |
| Q2 / A2 | ONE repository per DATABASE (Micronite: one DB shared by SERVER / CLIENT / PACKAGE -> one repository) | section 5: file `<primary project>\_DL-REPO\<DatabaseBaseName>.dlrepo`; every project using the database points at it with `"fieldRepository"` in `drag-lint-project.json` (pulled forward from phase 3). Table names are unique within one database, so per-database is sound; a second database is a second file |
| Q3 / A3 | ONE code base; `USE_DevEx_Grid` stays only so forks without DevExpress compile. The STANDARD shipped build is the DevExpress one | section 7: DevEx grid = default release build and what the installer ships; TDBGrid = fallback, still compiled and self-tested by the battery; the build box must have DevExpress (`DL_DEVEX_LIB`), a missing DevEx build is a FAIL |
| Q4 / A4 | skip FIB$VERSION for now; KEEP the enum values (later: enum code generation, drop-down / multiple-choice lists) | section 4: the `FIB$VERSION` column is not imported and not in the DL_ tables (re-added by a schema migration if a use appears); DL_ENUMVALUES is kept, editable, `EVALUE` stored as 0..255 |
| Q5 / A5 | FILL FROM SCHEMA in 1.52 by porting the extractor that lives in the TableTools exe | new section 9a below; phase 3's `repo refresh-schema` moves into 1.52 |
| Q6 / A6 | TableTools is DEPRECATED completely: EVERYTHING migrates to DL, in steps | section 11 is replaced by the migration inventory in C:\TEMP\claude\lanes\v152\PLAN.md section 6 (steps M1-M18): CSV -> FDMemTable, both Param Array assistants, the ORM / DataService generators and the IDE menu are 1.52 lanes; publish to Firebird, column triage and schema-aware lint stay later phases |

### 9a. Seed and refresh from the Firebird schema (1.52, lane TTS)

Units `DRagLint.FieldRepo.SchemaSeed` + `DRagLint.FieldRepo.FbTypes`: a port of `FieldsInfo.Model.pas`
`UpdateFieldsInfo`, `CleanOrphanFields`, `UpdateDatasetsInfo` and of the type-code dictionaries of
`TableTool.GlobalObject.pas` (codes 7, 8, 10, 12, 13, 14, 16, 23..29, 35, 37, 261; sub_type 1). No TDataModule, no
OTA, no CodeSite / EurekaLog; sources are passed in as datasets so the tests need no Firebird.

* `repo seed-fb --connection "..."` on an EMPTY repository: one DL_FIELDS_INFO row per `(table, column)` of
  `RDB$RELATION_FIELDS` with the schema-derived columns of section 2.1 filled and the hand-maintained ones at their
  defaults; DL_DATASETS_INFO generated for every user table with a PK. This is how a non-Micronite project starts.
* `repo refresh-schema --connection "..."` on a filled repository = the old "Update Fields Info": overwrites ONLY the
  schema-derived columns, keeps every hand-maintained column, marks vanished columns `ISCALCULATED`, regenerates
  DL_DATASETS_INFO. Prints added / changed / orphaned counts; `--dry-run` prints the diff and writes nothing.
* `repo import-fb` (section 9) stays the Micronite path: it copies the FIB$ rows as they are.
* Acceptance on live data: a seed of an empty repository from the Micronite dev database equals `import-fb` on every
  schema-derived column; differences are listed, not hidden. Firebird is read-only in every lane.

## 2. TableTools inventory (what exists today)

Package `TableTools370P.dproj` (Win32, design-time BPL; requires `designide`, FireDAC,
DevExpress RS37, Spring.Core, CodeSite, EurekaLog, the ORM3 `Interfaces` package). A second
package `MemTableFieldWizard.dpk` holds an older single-purpose wizard.

| Unit | Role |
|---|---|
| `TableTool.Init.pas` | `TTablesMenuWizard`: adds the IDE main-menu item `Tables` and 10 entries (below) |
| `TableTool.GlobalObject.pas` | `TGlobalObject`: settings in `C:\ProgramData\MICRONITE\MICRONITE.INI` + the Firebird type-code -> accessor (`AsInteger`...) and -> Delphi type (`integer`...) dictionaries (codes 7, 8, 10, 12, 13, 14, 16, 23..29, 35, 37, 261; `+SUBTYPE_ADD` for sub_type 1) |
| `TableTool.Interfaces.pas` / `ContainerSetup.pas` | `IGlobalObject`, Spring4D container wiring |
| `FieldsInfo.Model.pas` (4450 lines, TDataModule) | the engine: `UpdateFieldsInfo`, `CleanOrphanFields`, `UpdateDatasetsInfo`, `GenerateORMSource`, `UpdateORMSource` (`UpdateFileRegions`), `GenerateDataServiceUnits`, `GenerateSection1..15` |
| `uSetup.pas/.dfm` | settings dialog (5 paths, DevExpress layout) |
| `uPrepareFieldsInfo.pas` | empty unit |
| `ToolsAPIHelper.pas` | OTA facade (add unit to project, editor writes) |
| `uFireDACParamArrayAssistant.pas` | Array-DML code assistant (unrelated to the registry) |
| `MemTableFieldWizard.pas` | FDMemTable field wizard from CSV |

Menu `Tables` (TableTool.Init.pas:181-224): FDMemTable Create from CSV; FireDAC Param Array
Assistant Project / Single; Setup; **Update Fields Info**; **Generate ORM PAS source**;
**UPDATE / REFRESH ORM PAS source**; **Generate DataService units**; Table 9; Table 10 (stubs).

Settings actually in use on this machine (`MICRONITE.INI [General]`):

| Key | Value |
|---|---|
| `edtDBPath` | `C:\Projects\DB\SQL\MICRONITEV6A.FDB` |
| `edtCodePath` | `C:\Projects\DB\ORM3\COMMON\OBJECTS` |
| `edtServer` | `C:\Projects\DB\ORM3\SERVER\MicroniteMW1Service.DPROJ` |
| `edtClient` | `C:\Projects\DB\ORM3\CLIENT\Micronite2027.DPROJ` |
| `edtPackage` | `C:\Projects\DB\ORM3\TestMicroniteObjects.DPROJ` |

The firebird MCP is connected to the SAME database (`C:\Projects\DB\SQL\MICRONITEV6A.FDB`,
local xnet, SYSDBA), so every fact in section 3 was read live on 2026-11-16.

### 2.1 What "Update Fields Info" does

For every `(table, column)` in `RDB$RELATION_FIELDS` it upserts a `FIB$FIELDS_INFO` row:
schema-derived columns are OVERWRITTEN each run (`FIELD_AS_TYPE`, `VAR_TYPE`, `FIELD_SIZE`,
`STRING_SIZE`, `NULL_FLAG`, `FIELD_KIND`, `FIELD_TYPE`, `FIELD_SUBTYPE`, `FIELD_LENGTH`,
`FIELD_SCALE`, `PRIMARY_KEY`, `SEQUENCE_NAME`, `TRIGGERED`); hand-edited columns are kept
(`DISPLAY_LABEL`, `VISIBLE`, `DISPLAY_FORMAT`, `EDIT_FORMAT`, `DISPLAY_WIDTH`, `ALIGNMENT`,
`DEFAULTVAL` once set, lookup/enum/doc columns). Then `CleanOrphanFields` marks rows whose
column vanished as `ISCALCULATED = TRUE` (kept on purpose since 2026-05-19: they are legacy
calculated/display fields), and `UpdateDatasetsInfo` regenerates one `FIB$DATASETS_INFO` row
per user table with a PK (SELECT / INSERT / UPDATE / DELETE / REFRESH SQL).

This split -- **schema-derived vs hand-maintained columns** -- is the key fact for every later
phase: only the hand-maintained columns are "repository" data; the rest is a schema cache.

### 2.2 What the codegen does

`GenerateORMSource` writes new `i<T>.PAS` + `u<T>.PAS` (ASCII) and adds them to the server,
client and package projects. `UpdateORMSource` rewrites ONLY the text between
`{$REGION 'DB-RAD <id>'}` and `{$ENDREGION ... DB-RAD ...}` (ids 1, 1A, 2..15; `IsRegionStart`
at FieldsInfo.Model.pas:4285), so hand code outside the regions survives. Each property gets
a `{$REGION 'Documentation'}` block fed by `DOC_SUMMARY` / `DOC_REMARKS`. `$` in a table name
becomes `_` in the unit name. Hand-maintained length constants already exist OUTSIDE the
region (`iMSCLIST.PAS:1401-1408`: `MSCLIST_DIMNAME_MAXLEN = 35`, `MSCLIST_DIMABBR_MAXLEN = 10`,
with the comment "until the Table Tools domain generator replaces these").

### 2.3 The registry is ALSO read at run time (not only by the IDE wizard)

| Consumer | Reads |
|---|---|
| `ORM3\COMMON\uFieldsInfoCache.pas:135` (`TFieldsInfoCache.LoadFrom`) | `FIB$FIELDS_INFO` over the pipe (`TABLE=FIB$FIELDS_INFO\|BLOBS=0`) |
| `ORM3\SERVER\uDatasetsDef.pas:167` | `FIB$FIELDS_INFO` + `FIB$DATASETS_INFO` -> SELECT lists for `cmdTableLoad` |
| `ORM3\SERVER\uPipeSessionBuilder.pas:443-585` | table load driven by both tables |
| `ORM3\SERVER\uFIB_FIELDS_INFO_SERVER.pas` | Load / `UPDATE OR INSERT` data service |
| `ORM3\CLIENT\Blueprint4.ViewModel.pas` | client `TFDMemTable` schema built by `TFieldsInfoFactory` from `FIB$FIELDS_INFO` |

Consequence: **the Firebird tables cannot simply move into DL.** The shipped Micronite
server needs them in the customer database. The DL repository is the design-time master
COPY; a later phase needs a publish step (DL -> Firebird). See owner question Q1.

### 2.4 Prior art already in DL

* `drag-lint fb-snapshot --connection "..." --db <sql.sqlite>` (`src\sql\DRagLint.Sql.FbSnapshot.pas`):
  copies `RDB$RELATIONS`, `RDB$RELATION_FIELDS` and a SUBSET of the three FIB$ tables into
  `fb_relations`, `fb_columns`, `fb_field_info`, `fb_datasets`, `fb_enum_values` of an index
  DB. Lossy and disposable -- a snapshot, not a repository. It stays; phase 4 extends it.
* `drag-lint link-orm` (`DRagLint.Sql.OrmLinker.pas`): links `T<X>`/`I<X>`/`F<Y>` to table X /
  column Y by naming convention.
* `drag-lint export enums --format firebird-sql|csv|json|delphi-const`.

## 3. The Firebird registry (live, 2026-11-16)

Four tables, prefix `FIB$` (a FIBPlus-era convention), all charset UTF8:

| Table | Rows | PK | Notes |
|---|---|---|---|
| `FIB$FIELDS_INFO` | 2117 | `(TABLE_NAME, FIELD_NAME)` | 137 distinct tables, none missing from `RDB$RELATIONS`; 64 rows describe the FIB$ tables themselves |
| `FIB$DATASETS_INFO` | 134 | `DS_ID` (1..139, no generator) | all 5 SQL blobs filled; longest SELECT 1381 chars; column position 12 was dropped |
| `FIB$ENUMVALUES` | 51 | `(ENUMTYPE, EORDER)` | 8 enum types |
| `FIB$ERROR_MESSAGES` | 0 | `CONSTRAINT_NAME` | empty; schema kept |

No foreign keys, no secondary indexes. One generator, `FIB$FIELD_INFO_VERSION` (current
value 9098). Triggers `BI`/`BU` set `FIB$VERSION = GEN_ID(FIB$FIELD_INFO_VERSION, 1)`; they are
ACTIVE on `FIB$DATASETS_INFO` and `FIB$ERROR_MESSAGES` and INACTIVE on `FIB$FIELDS_INFO`
(every `FIB$VERSION` there is 0). No non-ASCII character in any `DISPLAY_LABEL` today.

Usage of `FIB$FIELDS_INFO` columns (non-default rows of 2117), for the later triage:
`DISPLAY_LABEL` 650, `DISPLAY_WIDTH` 553, `DEFAULTVAL` 558, `PRIMARY_KEY` 192,
`DISPLAY_FORMAT` 127, `TRIGGERED` 68, `ISENUM` 31, `UI_TAG` 20, `LOADFIELD` 5,
`ISCALCULATED` 3; **zero rows**: `EDIT_FORMAT`, `BG_COLOR`, `FG_COLOR`, `ISLOOKUP`,
`DOCUMENTATION`, real `DOC_SUMMARY`. (Phase 1 copies them all regardless.)

## 4. Firebird -> DL table map

Rule: table `FIB$<X>` becomes `DL_<X>`; column names are kept EXACTLY (including
`FIB$VERSION`, which must be double-quoted in SQLite SQL). Column order is kept.

Type map (declared types are chosen so FireDAC's SQLite driver yields the right `TField`
class; SQLite itself only uses the affinity):

| Firebird | SQLite declaration | TField | Kind in code |
|---|---|---|---|
| `VARCHAR(n)` UTF8 | `VARCHAR(n)` + `CHECK (length(col) <= n)` | `TWideStringField` size n | `rckString` |
| `BOOLEAN` | `BOOLEAN` (0/1) | `TBooleanField` | `rckBoolean` |
| `SMALLINT` | `SMALLINT` | `TSmallintField` | `rckSmallint` |
| `INTEGER` | `INTEGER` | `TIntegerField` (`DS_ID`: see below) | `rckInteger` |
| `BLOB SUB_TYPE TEXT` | `TEXT` | `TWideMemoField` | `rckText` |
| `BINARY(1)` (`D_BYTETAG`) | `SMALLINT` + `CHECK (col BETWEEN 0 AND 255)` | `TSmallintField` | `rckByte` |

`NOT NULL` and `DEFAULT` are carried over. A domain-level `NOT NULL` (D_BOOLEAN) counts.
The length CHECK keeps the repository publishable back to Firebird without overflow.
`DS_ID INTEGER NOT NULL PRIMARY KEY` becomes the SQLite rowid alias (FireDAC may report
`ftAutoInc`); that is accepted -- a new row in the editor gets the next id -- and pinned by a test.

### DL_FIELDS_INFO (from FIB$FIELDS_INFO), PK (TABLE_NAME, FIELD_NAME)

| # | Column | FB domain | Kind | Len | Not null | Default |
|---|---|---|---|---|---|---|
| 0 | TABLE_NAME | D_FBNAME | string | 68 | Y | |
| 1 | FIELD_NAME | D_FBNAME | string | 68 | Y | |
| 2 | DISPLAY_LABEL | D_STRTAG40 | string | 40 | | |
| 3 | VISIBLE | D_BOOLEAN | boolean | | Y | 1 |
| 4 | DISPLAY_FORMAT | D_STRTAG20 | string | 20 | | |
| 5 | EDIT_FORMAT | D_STRTAG20 | string | 20 | | |
| 6 | TRIGGERED | D_BOOLEAN | boolean | | Y | 0 |
| 7 | DISPLAY_WIDTH | D_INTEGER | integer | | | 0 |
| 8 | FIELD_AS_TYPE | D_STRTAG20 | string | 20 | | |
| 9 | VAR_TYPE | D_STRTAG20 | string | 20 | | |
| 10 | BG_COLOR | D_BOOLEAN | boolean | | Y | 0 |
| 11 | FG_COLOR | D_BOOLEAN | boolean | | Y | 0 |
| 12 | ALIGNMENT | D_SMALLINT | smallint | | | |
| 13 | DEFAULTVAL | D_STRTAG50 | string | 50 | | |
| 14 | FIELD_SIZE | D_SMALLINT | smallint | | | |
| 15 | STRING_SIZE | D_SMALLINT | smallint | | | |
| 16 | NULL_FLAG | D_SMALLINT | smallint | | | |
| 17 | UNIQUE_FLAG | D_BOOLEAN | boolean | | Y | 0 |
| 18 | FIELD_KIND | D_SMALLINT | smallint | | | |
| 19 | PRIMARY_KEY | D_BOOLEAN | boolean | | Y | 0 |
| 20 | SEQUENCE_NAME | D_STRTAG35 | string | 35 | | |
| 21 | CUSTOM_TYPE | D_BOOLEAN | boolean | | Y | 0 |
| 22 | ISCALCULATED | D_BOOLEAN | boolean | | Y | 0 |
| 23 | ISLOOKUP | D_BOOLEAN | boolean | | Y | 0 |
| 24 | ISENUM | D_BOOLEAN | boolean | | Y | 0 |
| 25 | DESTTABLE | D_STRTAG35 | string | 35 | | |
| 26 | SOURCEKEY | D_STRTAG35 | string | 35 | | |
| 27 | DESTKEY | D_STRTAG35 | string | 35 | | |
| 28 | DESTVALUE | D_STRTAG35 | string | 35 | | |
| 29 | DOC_SUMMARY | D_TEXTBLOB | text | | | 'Summary here' |
| 30 | DOC_REMARKS | D_TEXTBLOB | text | | | 'Remarks here' |
| 31 | ENUMTYPE | D_STRTAG | string | 25 | | |
| 32 | DOCUMENTATION | D_STRTAG220 | string | 220 | | |
| 33 | LOADFIELD | D_STRTAG50 | string | 50 | | |
| 34 | SAVEFIELD | D_STRTAG50 | string | 50 | | |
| 35 | FIELD_TYPE | D_SMALLINT | smallint | | | |
| 36 | FIELD_SUBTYPE | D_SMALLINT | smallint | | | |
| 37 | FIELD_LENGTH | D_SMALLINT | smallint | | | |
| 38 | FIELD_SCALE | D_SMALLINT | smallint | | | |
| 39 | UI_TAG | D_SMALLINT | smallint | | | 0 |
| 40 | FIB$VERSION | D_INTEGER | integer | | | |

### DL_DATASETS_INFO (from FIB$DATASETS_INFO), PK (DS_ID)

| # | Column | FB domain | Kind | Len | Not null | Default |
|---|---|---|---|---|---|---|
| 0 | DS_ID | D_INTEGER | integer | | Y | |
| 1 | DESCRIPTION | D_STRTAG220 | string | 220 | | |
| 2 | SELECT_SQL | D_TEXTBLOB | text | | | |
| 3 | UPDATE_SQL | D_TEXTBLOB | text | | | |
| 4 | INSERT_SQL | D_TEXTBLOB | text | | | |
| 5 | DELETE_SQL | D_TEXTBLOB | text | | | |
| 6 | REFRESH_SQL | D_TEXTBLOB | text | | | |
| 7 | NAME_GENERATOR | D_FBNAME | string | 68 | | |
| 8 | KEY_FIELD | D_FBNAME | string | 68 | | |
| 9 | UPDATE_TABLE_NAME | D_FBNAME | string | 68 | | |
| 10 | UPDATE_ONLY_MODIFIED_FIELDS | D_BOOLEAN | boolean | | Y | 1 |
| 11 | CONDITIONS | D_TEXTBLOB | text | | | |
| 12 | FIB$VERSION | D_INTEGER | integer | | | |

### DL_ENUMVALUES (from FIB$ENUMVALUES), PK (ENUMTYPE, EORDER)

| # | Column | FB domain | Kind | Len | Not null | Default |
|---|---|---|---|---|---|---|
| 0 | ENUMTYPE | D_STRTAG15 | string | 15 | Y | |
| 1 | EORDER | D_INTEGER | integer | | Y | |
| 2 | NAME | D_STRTAG20 | string | 20 | Y | |
| 3 | ESTRING | D_STRTAG50 | string | 50 | Y | |
| 4 | DOCUMENTATION | D_STRTAG220 | string | 220 | | |
| 5 | EVALUE | D_BYTETAG | byte | | | 0 |

### DL_ERROR_MESSAGES (from FIB$ERROR_MESSAGES), PK (CONSTRAINT_NAME)

| # | Column | FB domain | Kind | Len | Not null | Default |
|---|---|---|---|---|---|---|
| 0 | CONSTRAINT_NAME | D_FBNAME | string | 68 | Y | |
| 1 | MESSAGE_STRING | D_STRTAG220 | string | 220 | | |
| 2 | FIB$VERSION | D_INTEGER | integer | | | |
| 3 | CONSTR_TYPE | D_STRTAG15 | string | 15 | Y | 'UNIQUE' |

### DL_META (new; no Firebird counterpart), PK (META_KEY)

`META_KEY VARCHAR(63) NOT NULL`, `META_VALUE VARCHAR(1000)`. Keys written by the tools:
`schema_version` (= `PRAGMA user_version`), `source_database` (path only, never a password),
`imported_at_utc`, `fb_field_info_version` (the generator value at import time).

### Deliberately NOT copied

* The `FIB$VERSION` triggers and the generator. In SQLite the column is carried DATA.
  Versions are assigned by the Firebird triggers when a later phase publishes back; a SQLite
  trigger would make restore non-idempotent (a restore would renumber every row).
* The domains themselves (`D_STRTAG40`...). They belong to the schema index (phase 4).

## 5. Where the repository lives

**A separate SQLite file per project, never inside the index DB.** The index DB
(`<project>\_D-RAG\<base>.sqlite`) is a rebuildable cache: `index --rebuild` recreates it and
`_D-RAG` is treated as disposable. Hand-edited data must not live there.

* Default path: `<project folder>\_DL-REPO\<project base name>.dlrepo`.
* Extension `.dlrepo`, NOT `.sqlite`: nothing that globs `*.sqlite` (resolve-dbs, `index --all`,
  cleanup scripts, the repo-wide `.gitignore`) can mistake it for an index DB.
* The file is identified by `PRAGMA application_id = 0x444C4652` ('DLFR') and
  `PRAGMA user_version = 1` (schema version), so a renamed file is still recognised and a
  wrong file is rejected with a clear message.
* `journal_mode = DELETE` (one self-contained file, copyable), `synchronous = FULL`,
  `foreign_keys = ON`, normal locking so the CLI can read while the editor is open.
* Phase 1 resolution: explicit `--repo <file>` wins; else `--project <X.dproj>` -> the default
  path. A registry shared by several projects (Micronite: SERVER + CLIENT + PACKAGE share ONE
  database) is addressed with an explicit `--repo` in phase 1; a `"fieldRepository"` key in
  `_D-RAG\drag-lint-project.json` is phase 3 (owner question Q2).
* Version control: the binary is not committed; the **text backup** (section 8) is the
  committed, reviewable form.

## 6. How DL code reads it

All access goes through three units in `src\sql\` (already on every search path; no index
types, no `TSQLiteSymbolStore`):

| Unit | Contract |
|---|---|
| `DRagLint.FieldRepo.Schema` | the ONE static description of the tables (`RepoTables`), DDL derived from it, `CreateRepository`, `OpenRepository(pFile, pReadOnly)`, `ValidateRepository`, `DefaultRepoPath` |
| `DRagLint.FieldRepo.FbImport` | Firebird -> repository copy, dataset-driven so it is testable without Firebird |
| `DRagLint.FieldRepo.TextBackup` | text backup / restore |

Everything else is derived from `RepoTables`: DDL, the import column list, the backup
column order, the editor's grid columns. A column added later is added in ONE place.

Later readers (codegen, lint) call `OpenRepository(path, True)` -- a read-only connection of
their own. They never ATTACH the repository to the index write connection. A lint run with
no repository file behaves exactly as today (the schema-aware rules are silent, not failing).

## 7. The editor application

* Location: `src\tools\field-repo\`, exe `dl-field-repo.exe` (Win64, like the engine).
  A standalone exe, not IDE-hosted: DevExpress and FireDAC stay out of the design-time BPL,
  and the IDE plugin later only launches it (`DL > Field repository...`).
* **One form with tabs, not a form per table.** One `TPageControl`, one tab per table
  (4 tabs), each tab = navigator + grid + a memo panel for the current row's TEXT columns.
  The four tables behave identically; four forms would be four copies of the same code.
* **The UI is built in code; there is no `.dfm`.** A DFM cannot be conditionally compiled, so
  a DFM holding either grid class would break the other build. The grid is created by a
  factory behind one interface:

  ```pascal
  IRepoGridHost = interface
    procedure Attach(pParent: TWinControl; pSource: TDataSource);
    function GridKind: string;      // 'std' or 'devex'
    function VisibleColumnCount: Integer;
  end;
  function CreateRepoGridHost: IRepoGridHost;
  // {$IFDEF USE_DevEx_Grid} -> FieldRepo.GridHost.DevEx (TcxGrid + TcxGridDBTableView)
  // {$ELSE}                 -> FieldRepo.GridHost.Std   (TDBGrid)
  ```

  The `{$IFDEF USE_DevEx_Grid}` appears in exactly two places: the factory unit's `uses` and
  its body. `build.bat` builds the TDBGrid variant with stock VCL (any machine, the battery);
  `build_devex.bat` adds `-DUSE_DevEx_Grid` and the DevExpress library path.
* Data: one `TFDConnection` from `OpenRepository`, one `TFDQuery` per table
  (`SELECT * ... ORDER BY <pk>`, `UpdateOptions.KeyFields` = the PK), row-level post, no
  cached updates. `--readonly` opens the file read-only and disables editing.
* Command line: `dl-field-repo.exe [--repo <file> | --project <X.dproj>] [--readonly]
  [--selftest <report.txt>]`. `--selftest` builds the form, loads every tab, writes one line
  per tab (`TAB <table> rows=<n> cols=<n> grid=<kind>`) and exits 0 / 1 without showing a
  window that needs a user -- the battery's proof that the grids really fill.
* Phase 2 adds `File > Backup to text...` and `File > Restore from text...`, calling the same
  unit as the CLI.

## 8. Text backup format (phase 2)

One file, default `<repo>.txt` next to the repository (`<base>.dlrepo.txt`).

```
#DLREPO 1
[DL_META schema_version]
META_VALUE=1

[DL_FIELDS_INFO MSCLIST|DIMNAME]
DISPLAY_LABEL=Dim Name
VISIBLE=true
DISPLAY_WIDTH=12
...
#end DL_FIELDS_INFO 2117
[DL_DATASETS_INFO 1]
DESCRIPTION=Auto by TableTools 05/19/26 1:03:36 PM
SELECT_SQL:
 |SELECT A, B\r
 |FROM AREAOFINTEREST
UPDATE_ONLY_MODIFIED_FIELDS=true
...
#end DL_DATASETS_INFO 134
```

Rules (normative):

1. Bytes: 7-bit ASCII only, CRLF line ends, no BOM. First line `#DLREPO 1` (format version).
2. Tables in the fixed `RepoTables` order; after each table one trailer line
   `#end <TABLE> <row count>` (detects a truncated file). An empty table has only its trailer.
3. One record = a header `[<TABLE> <pk1>|<pk2>]`, then one line per NON-PK column in schema
   order, then one blank line. Records are ordered by PK ascending (SQLite BINARY collation
   for strings, numeric for integers).
4. A column whose value is NULL is OMITTED. An empty string is written as `NAME=`. Every
   non-NULL value is written, even when it equals the column default (a default that changes
   later must not silently change restored data).
5. Scalars: `NAME=value`. integer / smallint / byte in decimal; boolean `true` / `false`.
6. TEXT columns: `NAME:` then one line ` |<text>` per line of the value (split at LF). A CR
   before the LF is written as `\r` at the end of that line, so CRLF and LF text both
   round-trip exactly. A value ending in LF ends with an empty ` |` line.
7. Escapes inside any value: `\\` backslash, `\r`, `\t`, `\uXXXX` for every other code unit
   below 0x20 or above 0x7E, and for a trailing space (`\u0020`) so an editor that strips
   trailing blanks cannot change data. In a header PK value also `|` -> `\u007C` and
   `]` -> `\u005D`.
8. No timestamps, no row numbers, no machine names: the same data always gives the same bytes.

Why this and not CSV / JSON / SQL:

* **Diffable:** one property per line and one record per block means a changed caption is a
  ONE-line diff under a header that names the field; hg/git merge two people's edits to
  different fields without conflict. A 41-column CSV row is one unreadable changed line.
* **Multi-line SQL** (up to 1381 chars today) stays readable line by line; CSV and JSON
  would each put it on one escaped line.
* **Stable order + omitted NULLs + no volatile data** -> backup(restore(F)) = F byte for
  byte; this is the phase-2 acceptance test and it makes the file a trustworthy commit artifact.
* **7-bit ASCII** matches the repo rule for sources and survives any editor / code page; the
  `\uXXXX` escape keeps it lossless.
* **Not an SQL dump:** restore must validate before it writes (unknown table/column, bad
  escape, wrong trailer count -> error with a line number, nothing changed) and must never
  execute text from a file.

Restore parses and validates the WHOLE file first, then in ONE transaction deletes all rows
of every table and inserts the file's rows. A non-empty repository requires `--replace`.

## 9. The one-shot Firebird import: a CLI verb

`drag-lint repo import-fb --connection "Database=...;User=...;Password=...;DriverID=FB" (--repo <file> | --project <X.dproj>) [--replace]`

A CLI verb, not a separate tool and not (yet) an editor menu, because `drag-lint.exe`
already links the FireDAC Firebird driver and already has the connection-string handling
(`fb-snapshot`); it is scriptable for an unattended run; and an autotest runner can drive it.

Behaviour:

* Creates the repository when the file does not exist.
* Forces `CharacterSet=UTF8` when the connection string does not name one.
* Compares each source table's columns with `RepoTables` first: an unknown source column or a
  missing expected column is an ERROR naming it (exit 2, nothing written) -- the "existing
  structure" is the contract. A missing source TABLE is a warning and that DL_ table stays empty.
* Refuses a non-empty repository without `--replace`; with `--replace` it first writes
  `<repo>.before-import-<yyyymmdd-hhnnss>.txt` (a text backup) and reports its path.
* One transaction; prints `<table>: <n> rows` per table; exit 0 only when every DL_ count
  equals the source `count(*)`.

Verb family (two-word verbs, like `export enums`): `repo init`, `repo import-fb`,
`repo info [--json]`, and in phase 2 `repo backup --output <file>`, `repo restore --in <file> [--replace]`.
New flags: `--repo`, `--replace`. Docs-in-sync surfaces and the feature registry entry
(`field-repository`) ship in the same change.

## 10. Test strategy

TDD, comment + test agree. The repo's convention is plain console test programs printing
`PASS <name>` / `FAIL <name>` and exiting non-zero on any FAIL (see
`src\tools\project-setup\tests\ProjectCtxTests.dpr`), wrapped by `tests\autotest\run_*.ps1`
runners that the battery picks up. DUnitX is not used in this repo and is not introduced.

| Layer | Test |
|---|---|
| Schema | create -> validate; DDL has every column of section 4; PK violation and length CHECK reject; a non-repository SQLite file and a wrong `user_version` are rejected; FireDAC field classes per kind |
| Import | fed from `TFDMemTable` sources (no Firebird): row counts, NULL vs '' preserved, byte column, extra/missing column errors, non-empty target refused, `--replace` |
| Text backup | golden fixture: restore(F) then backup = F byte for byte; edge fixture (NULL vs empty, trailing space, tab, non-ASCII, CRLF and LF text, PK containing `\|`); every malformed fixture fails with its line number and leaves the DB unchanged; output is ASCII + CRLF |
| CLI | `repo init` -> `repo restore` -> `repo info --json` -> `repo backup` round trip; exit codes |
| Editor | `--selftest`: 4 tabs, row counts equal `repo info`, column counts equal the schema, grid kind |
| Live (optional) | `repo import-fb` against `DL_TEST_FB_CONNECTION`; SKIP (not FAIL) when the variable is unset; counts compared with the live `count(*)`, never with a constant |

Every negative assertion has a positive control in the same test (a guard that cannot fail
is not a guard).

## 11. Later phases (not planned in detail here)

| Phase | Content |
|---|---|
| 3 Schema index | Extend `fb-snapshot`: `RDB$FIELDS` domains (name, type, length, char length, scale, null, default), PK / unique / FK constraints, generators. Offline source too: DDL scripts (`DB\SQL\*.SQL`). `fieldRepository` key in `drag-lint-project.json`. `repo refresh-schema` = TableTools' "Update Fields Info" (overwrites ONLY the schema-derived columns of section 2.1, reclassifies orphans, regenerates DL_DATASETS_INFO). |
| 4 Publish | `repo publish-fb`: DL -> `FIB$*` in a target database (dry-run diff first), because the Micronite server reads them at run time. Decides which side is master (Q1). |
| 5 Domain constants | Generate `<TABLE>_<FIELD>_MAXLEN` (and domain-level) constants from the schema index into a generated unit or a marked block OUTSIDE `{$REGION 'DB-RAD 2'}`; drift check constants vs live schema. Replaces the hand block at `iMSCLIST.PAS:1401`. |
| 6 Schema-aware lint | Rules over index + schema + repository: literal length vs domain length (the `Blueprint4.PDFImport.ViewModel.pas:1300` class), `Copy`/`SetLength`/`MaxLength`/`Size` vs column length, field name not in schema, DFM `DisplayLabel` / `DisplayWidth` / `DisplayFormat` differing from the repository, SQL text naming an unknown column. |
| 7 Codegen | Port `GenerateORMSource` / `UpdateORMSource` / `GenerateDataServiceUnits`: template-driven, region-preserving (`DB-RAD <id>`), ASCII, dry-run diff; then generic "apply repository to form/dataset" (push captions, widths, formats into DFMs and persistent fields). Golden tests against today's 290 `COMMON\OBJECTS` units. |
| 8 IDE | `DL > Field repository...` (launch the editor on the active project's repository), `Refresh schema`, `Generate / Update ORM source`; featuregen entries with full menu paths. Port or drop the unrelated assistants (FDMemTable from CSV, Param Array Assistant) -- Q6. |
| 9 Column triage | Decide the fate of the unused columns (section 3 list); schema version 2 with a migration. |

## 12. Questions only the owner can answer

* **Q1 master copy.** The Micronite server and client read `FIB$FIELDS_INFO` / `FIB$DATASETS_INFO`
  at run time. Until `repo publish-fb` exists (phase 4), is Firebird still the master (edits
  made in the DL editor are lost by the next `import-fb --replace`), or is editing in DL
  frozen-in from day one and publish pulled forward into 1.52?
* **Q2 scope of one repository.** One per DATABASE (Micronite: one file shared by SERVER,
  CLIENT, PACKAGE) or strictly one per `.dproj`? And is `<project>\_DL-REPO\<base>.dlrepo`
  with the text backup beside it (committed to hg) the right home?
* **Q3 DevExpress build.** Which DevExpress library folder should `build_devex.bat` use for
  Win64 (a lookup of `HKCU\Software\Embarcadero\BDS\37.0\Library\Win64` "Search Path" on
  2026-11-16 returned no DevExpress entry -- unverified whether the key or the entry is missing), and is it right that
  the DEFAULT build -- the one the battery and the installer use -- is the TDBGrid one?
* **Q4 names.** Keep the column name `FIB$VERSION` as is (design default: yes, "existing
  structure"), and store `EVALUE BINARY(1)` as a 0..255 number?
* **Q5 non-Micronite projects.** Their repository starts empty (`repo init`) and is filled
  from the schema in phase 3 -- or should 1.52 already seed it from a schema?
* **Q6 the other TableTools duties.** FDMemTable-from-CSV, the two Param Array assistants and
  the DataService-unit generator: port, or leave in TableTools?
