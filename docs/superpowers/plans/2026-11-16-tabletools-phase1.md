# TableTools into DL -- plan for phase 1 (repository + editor) and phase 2 (text backup)

Date: 2026-11-16. Target 1.52. Design (normative, read it first):
`docs\superpowers\specs\2026-11-16-tabletools-into-dl-design.md` -- section 4 is the column
contract, section 8 the text format, section 9 the import behaviour.

Written for sonnet implementers. Where this plan and the design disagree, STOP and report;
do not pick one.

## Owner rulings 2026-11-17 (A1-A6) -- THIS BLOCK OVERRIDES THE TEXT BELOW

Master plan and lane briefs: C:\TEMP\claude\lanes\v152\PLAN.md (migration inventory M1-M18 in section 6),
C:\TEMP\claude\lanes\v152\briefs\TT*.md. Design rulings: design section 1a and 9a.

* Lane names: A = TTA, B = TTB, C = TTC, D = TTD, E = TTE, F = the release INT. NEW lanes: TTS (seed / refresh from
  the Firebird schema, A5), TTCSV (FDMemTable from CSV), TTPA (Param Array assistants), TTGEN (ORM + DataService
  generators), TTIDE (IDE menu `DL > Field repository`) -- ruling A6: everything in TableTools migrates.
* A1: no lane writes to Firebird; `repo publish-fb` is NOT in 1.52. A2: one repository per DATABASE; lane TTE adds
  the `fieldRepository` project key (section 8 "out of scope" no longer lists it). A3: lane TTD -- the DevExpress
  build is the DEFAULT (`build\_build_field_repo_local.bat`), the TDBGrid build is the fallback
  (`build\_build_field_repo_std_local.bat`); the runner self-tests BOTH and FAILS when the DevEx build is missing.
  A4: lane TTA drops the `FIB$VERSION` column from `RepoTables` and from the tests; DL_ENUMVALUES stays.
* Scaffold: lane FRAME (master plan) creates every `DRagLint.FieldRepo.*` stub, lists the units in
  `drag-lint.dpr` / `.dproj` and adds the `repo` dispatch line + `--repo` / `--replace` flags to CLI.pas. Therefore
  lane E (TTE) edits ONLY `src\cli\DRagLint.CLI.Repo.pas` + its entry, wiki page and runners and is a sonnet lane;
  README / AI-USAGE / HelpText / generated pages are INT-only (HANDOVER lines).
* Verb family (TTE): `repo init / info / import-fb / seed-fb / refresh-schema / backup / restore / gen-memtable /
  gen-param-array`, and from TTGEN `repo gen-orm / update-orm / gen-dataservice`.
* Order: `FRAME F1 -> TTA -> { TTB, TTC, TTD, TTS } -> TTE -> { TTGEN, TTIDE }`; TTCSV and TTPA start at FRAME F1.
* Engine dir `lanes\v152\<lane>\engine\`; integration branch `lane/v152-int`.

## 0. Rules for every lane

* Source of truth for Firebird facts is the design, section 3/4. `C:\Projects\TableTools` and
  `C:\Projects\DB\ORM3` are READ ONLY. No lane writes to any Firebird database.
* `.pas`, `.dpr`, `.bat`, `.ps1`: 7-bit ASCII, CRLF, no BOM (Write/Edit emit LF -- normalise
  with `[IO.File]::ReadAllText` / `WriteAllText`, then run `tests\autotest\run_encoding_guard.ps1`).
* TDD: write the test, build, WATCH IT FAIL for the right reason, then implement. DocInsight
  `///` comments on every public type and routine; comment and test must agree.
* Tests are console programs: `PASS <name>` / `FAIL <name>` per check, a last line
  `SUMMARY run=<n> fail=<n>`, exit code 1 when fail > 0. Model:
  `src\tools\project-setup\tests\ProjectCtxTests.dpr`. Runner model:
  `tests\autotest\run_featuregen_tests.ps1` (build through a `build\_build_*_local.bat` with
  `Start-Process -Wait` and a log; FAIL on a missing exe; read `SUMMARY`).
* Build: `delphi-build` skill recipe only. Never `cmd /c x.bat` from the Bash tool, never the
  MCP build tool. Build/test output goes to a log; read only the summary lines.
* Every test creates its files under `$env:TEMP\dl-fieldrepo-<lane>-<pid>\` and never touches
  a real project's `_DL-REPO` or `_D-RAG`.
* Lint-clean: after the last edit reindex the project DB incrementally, run `lint <unit>` per
  changed unit and `lint-all`, both with
  `--enable magic-literal,multiple-statements-per-line,commented-out-code`; fix or `dl:ok` each
  finding; report commands + counts.
* Commit with a pathspec only (`git commit -m "..." -- <paths>`). No push. No engine deploy.
* `DRAGLINT_EXTRACTOR_VERSION` is NOT bumped (nothing here changes extraction).
* A lane uses its own worktree and a PRIVATE engine copy; one waiter per background job, no
  poll loops.

## 1. Lanes

| Lane | Content | Files it owns (nobody else edits them) | Needs | Model |
|---|---|---|---|---|
| A | Schema core (the contract) | `src\sql\DRagLint.FieldRepo.Schema.pas`; `tests\fieldrepo\SchemaTests.dpr`; `build\_build_fieldrepo_schema_tests_local.bat`; `tests\autotest\run_fieldrepo_schema.ps1` | -- | sonnet |
| B | Firebird import core | `src\sql\DRagLint.FieldRepo.FbImport.pas`; `tests\fieldrepo\FbImportTests.dpr`; `build\_build_fieldrepo_fbimport_tests_local.bat`; `tests\autotest\run_fieldrepo_fbimport.ps1` | A merged | sonnet |
| C | Text backup core (phase 2) | `src\sql\DRagLint.FieldRepo.TextBackup.pas`; `tests\fieldrepo\TextBackupTests.dpr`; `tests\fixtures\fieldrepo\*.txt`; `build\_build_fieldrepo_textbackup_tests_local.bat`; `tests\autotest\run_fieldrepo_textbackup.ps1` | A merged | sonnet |
| D | Editor app | everything under `src\tools\field-repo\`; `build\_build_field_repo_local.bat`; `build\_build_field_repo_devex_local.bat`; `build\_build_field_repo_tests_local.bat`; `tests\autotest\run_fieldrepo_editor.ps1` | A merged (D5 also C) | sonnet |
| E | CLI verbs, docs, registry | `src\cli\DRagLint.CLI.Repo.pas` (new); edits in `src\cli\DRagLint.CLI.pas`, `DRagLint.CLI.HelpText.pas`, `src\cli\drag-lint.dpr` / `.dproj`; `README.md`; `docs\AI-USAGE.md`; `features\entries\field-repository.json`; `docs\wiki\field-repository.md`; `tests\autotest\run_repo_cli_roundtrip.ps1`; `tests\autotest\run_repo_cli_import_fb_live.ps1` | A, B, C merged | session model (2 MB hot unit, docs guards, featuregen) |
| F | Integration + review | no product files of its own | all | session model |

Order: A alone -> B, C, D in parallel (file-disjoint) -> E -> D5 can run beside E -> F.
HPS wall-clock estimate: A 1.5 h; B/C/D 3 h in parallel; E 3 h; F 2 h + battery.

## 2. Lane A -- schema core

### A1. Unit `DRagLint.FieldRepo.Schema` (interface is FIXED -- lanes B, C, D compile against it)

```pascal
unit DRagLint.FieldRepo.Schema;

interface

uses
  System.SysUtils, FireDAC.Comp.Client;

const
  cRepoSchemaVersion = 1;
  cRepoApplicationId = $444C4652;      // 'DLFR'
  cRepoFileExt       = '.dlrepo';
  cRepoFolderName    = '_DL-REPO';
  cRepoMetaTable     = 'DL_META';

type
  ERepoError       = class(Exception);
  ERepoSchemaError = class(ERepoError);

  TRepoColKind = (rckString, rckInteger, rckSmallint, rckBoolean, rckText, rckByte);

  TRepoColumn = record
    Name      : string;        // exact column name, e.g. 'FIB$VERSION'
    Kind      : TRepoColKind;
    MaxLen    : Integer;       // rckString only, else 0
    NotNull   : Boolean;
    DefaultSql: string;        // SQL literal ('0', '1', '''UNIQUE'''), '' = no default
    PkOrder   : Integer;       // 1-based position in the PK, 0 = not a key column
  end;

  TRepoTable = record
    Name      : string;        // 'DL_FIELDS_INFO'
    SourceName: string;        // 'FIB$FIELDS_INFO'; '' for DL_META
    Columns   : TArray<TRepoColumn>;
    function PkColumns: TArray<TRepoColumn>;      // in PkOrder
    function FindColumn(const pName: string; out pColumn: TRepoColumn): Boolean;
  end;

function RepoTables: TArray<TRepoTable>;
function FindRepoTable(const pName: string; out pTable: TRepoTable): Boolean;
function QuoteRepoIdent(const pName: string): string;
function RepoTableDdl(const pTable: TRepoTable): string;
function DefaultRepoPath(const pProjectFile: string): string;
procedure CreateRepository(const pFileName: string);
function OpenRepository(const pFileName: string; pReadOnly: Boolean): TFDConnection;
procedure ValidateRepository(pConnection: TFDConnection);
function RepoRowCount(pConnection: TFDConnection; const pTableName: string): Integer;
function RepoIsEmpty(pConnection: TFDConnection): Boolean;
procedure SetRepoMeta(pConnection: TFDConnection; const pKey, pValue: string);
function GetRepoMeta(pConnection: TFDConnection; const pKey: string): string;
```

Semantics:

* `RepoTables` returns, in this order: `DL_META`, `DL_FIELDS_INFO`, `DL_DATASETS_INFO`,
  `DL_ENUMVALUES`, `DL_ERROR_MESSAGES`, with EXACTLY the columns, order, kinds, lengths,
  not-null flags, defaults and PKs of design section 4. Table lookup is case-insensitive.
* `QuoteRepoIdent` returns the name in double quotes (needed for `FIB$VERSION`); every SQL
  statement in every lane quotes identifiers through it.
* `RepoTableDdl`: `CREATE TABLE "<name>" (...)` -- per column the SQLite declaration of the
  design's type map, `NOT NULL`, `DEFAULT <DefaultSql>`, `CHECK (length("c") <= n)` for
  `rckString`, `CHECK ("c" BETWEEN 0 AND 255)` for `rckByte`; a table-level
  `PRIMARY KEY (...)`, except a single `rckInteger` key column, which is declared inline
  `INTEGER NOT NULL PRIMARY KEY` (DS_ID).
* `DefaultRepoPath('C:\P\App.dproj')` = `C:\P\_DL-REPO\App.dlrepo`.
* `CreateRepository`: raises `ERepoError` when the file exists; creates the folder; sets
  `application_id`, `user_version`, `journal_mode=DELETE`; creates the 5 tables in one
  transaction; writes `DL_META.schema_version`.
* `OpenRepository`: raises `ERepoError` when the file is missing (it never creates);
  FireDAC `DriverID=SQLite`, `OpenMode=ReadOnly` or `ReadWrite`, `LockingMode=Normal`,
  `Synchronous=Full`, `foreign_keys=ON`; calls `ValidateRepository`; the caller frees the result.
* `ValidateRepository` raises `ERepoSchemaError` naming the cause: wrong `application_id`,
  `user_version` <> `cRepoSchemaVersion`, a missing table, a missing or unexpected column
  (`PRAGMA table_info`).
* `RepoIsEmpty` ignores `DL_META`.

### A2. Tests `tests\fieldrepo\SchemaTests.dpr` (write FIRST)

Acceptance -- each bullet is at least one PASS line:

1. `RepoTables` has 5 tables in the stated order; column counts 2 / 41 / 13 / 6 / 4.
2. Spot contract checks: `DL_FIELDS_INFO.TABLE_NAME` string 68 not-null PkOrder 1;
   `FIELD_NAME` PkOrder 2; `VISIBLE` boolean not-null default `1`; `DOC_SUMMARY` text default
   `'Summary here'`; `FIB$VERSION` is the last column of FIELDS_INFO, DATASETS_INFO and the
   third of ERROR_MESSAGES; `DL_ENUMVALUES.EVALUE` byte default `0`;
   `DL_ERROR_MESSAGES.CONSTR_TYPE` not-null default `'UNIQUE'`;
   `DL_DATASETS_INFO.UPDATE_ONLY_MODIFIED_FIELDS` default `1`.
3. `CreateRepository` on a new path, then `OpenRepository(.., True)` succeeds and
   `PRAGMA application_id` / `user_version` read back the constants.
4. `CreateRepository` on an existing file raises `ERepoError`; `OpenRepository` on a missing
   file raises `ERepoError` and does NOT create the file.
5. A plain SQLite file with one unrelated table raises `ERepoSchemaError` (positive control:
   the same call on a real repository does not raise).
6. A repository whose `user_version` was set to 99 raises `ERepoSchemaError`.
7. Insert a minimal `DL_FIELDS_INFO` row (only the two key columns): `VISIBLE` reads True,
   `TRIGGERED` False, `DOC_SUMMARY` 'Summary here'.
8. A second row with the same key raises (PK); a 69-char `TABLE_NAME` raises (CHECK); a
   68-char one is accepted (positive control); `EVALUE = 256` raises, 255 is accepted.
9. FireDAC field classes on `SELECT *`: string -> `TWideStringField` with `Size = MaxLen`,
   boolean -> `TBooleanField`, smallint/byte -> `TSmallintField`, text -> `TWideMemoField`,
   integer -> `TIntegerField` or `TLargeintField`/`TFDAutoIncField` for `DS_ID` (print the
   actual class in the PASS line; if string columns do not come back as `TWideStringField`,
   set `StringFormat=Unicode` in `OpenRepository` and re-run).
10. `SetRepoMeta` / `GetRepoMeta` round-trip; a read-only connection rejects `SetRepoMeta`.
11. `DefaultRepoPath` returns the path stated above.

### A3. Runner `tests\autotest\run_fieldrepo_schema.ps1` + `build\_build_fieldrepo_schema_tests_local.bat`

Bat: `rsvars` -> `cd` to `tests\fieldrepo` -> `dcc64 -B -NUdcu -E. -U"..\..\src\sql" -NSSystem;Winapi;System.Win;Data;FireDAC SchemaTests.dpr`
-> `echo BUILD_EXITCODE=%errorlevel%`. Runner: copy the featuregen runner's structure.
Done when the runner exits 0 and prints `fail=0`, and exits 1 when one check is made to fail
on purpose (show that once, then revert).

## 3. Lane B -- Firebird import core

### B1. Unit `DRagLint.FieldRepo.FbImport`

```pascal
type
  TRepoImportStat = record
    TableName  : string;    // DL_ name
    SourceRows : Integer;   // -1 when the source table does not exist
    CopiedRows : Integer;
  end;

procedure CheckSourceColumns(pSource: TDataSet; const pTable: TRepoTable;
  out pExtra, pMissing: TArray<string>);
function ImportTableFromDataSet(pSource: TDataSet; pTarget: TFDConnection;
  const pTable: TRepoTable): Integer;
function ImportFromFirebird(const pConnectionString: string; pTarget: TFDConnection;
  pReplace: Boolean): TArray<TRepoImportStat>;
```

* `CheckSourceColumns`: names compared case-insensitively against `pTable.Columns`.
* `ImportTableFromDataSet`: raises `ERepoError` listing the names when extra or missing is
  non-empty. Copies every row with a parameterised INSERT built from `pTable` (identifiers via
  `QuoteRepoIdent`). NULL stays NULL; '' stays ''. Kind conversion: string/text `AsWideString`
  (NO trimming), integer/smallint `AsInteger`, boolean `AsBoolean`, byte = first byte of
  `AsBytes` when the source field is a bytes/var-bytes field, else `Ord` of the first char.
  Does not start or commit a transaction (the caller owns it). Returns the row count.
* `ImportFromFirebird`: parses the connection string as `DRagLint.Sql.FbSnapshot`'s
  `ConnectFb` does (find it with `drag-lint outline --file src\sql\DRagLint.Sql.FbSnapshot.pas`),
  adds `DriverID=FB` and `CharacterSet=UTF8` when absent, `LoginPrompt=False`. Target not
  empty and not `pReplace` -> `ERepoError`, nothing changed. One target transaction: delete
  the rows of the 4 data tables, import each `SourceName` with `SELECT * FROM "<SourceName>"`
  (a table missing in `RDB$RELATIONS` gives `SourceRows = -1`, 0 copied, no error), set
  `DL_META` `source_database`, `imported_at_utc` (ISO 8601 UTC), `fb_field_info_version`
  (`SELECT GEN_ID(FIB$FIELD_INFO_VERSION, 0) FROM RDB$DATABASE`; '' when the generator is
  missing). Any exception rolls the whole import back. Never writes a password anywhere.

### B2. Tests `tests\fieldrepo\FbImportTests.dpr` (FIRST; no Firebird -- sources are `TFDMemTable`)

Helper: build a mem table with the columns of a `TRepoTable` (string -> `ftWideString`,
text -> `ftWideMemo`, byte -> `ftBytes` size 1, ...).

1. 3 rows into `DL_FIELDS_INFO` -> returns 3, `RepoRowCount` = 3, values equal per column.
2. NULL vs '' : a row with `DISPLAY_LABEL` NULL and `DISPLAY_FORMAT` '' reads back NULL and ''.
3. Leading/trailing spaces and a non-ASCII char (`#$00E9`) in `DISPLAY_LABEL` survive.
4. Multi-line `SELECT_SQL` with CRLF survives byte for byte.
5. Byte column: `ftBytes` value `$07` -> 7; a second mem table with `ftFixedChar` size 1
   holding `#7` -> 7; NULL -> NULL.
6. An extra source column `NEWCOL` raises `ERepoError` whose message contains `NEWCOL`; a
   missing `UI_TAG` raises with `UI_TAG`; in both cases the target row count is unchanged
   (positive control: the same data without the defect imports).
7. A duplicate key in the source raises and, wrapped in the caller's transaction + rollback,
   leaves 0 rows.
8. `CheckSourceColumns` on an exact match returns two empty arrays.

### B3. Runner + build bat (as A3). `ImportFromFirebird` itself is exercised live in lane E.

## 4. Lane C -- text backup core (phase 2)

### C1. Unit `DRagLint.FieldRepo.TextBackup`

```pascal
type
  ERepoBackupFormatError = class(ERepoError)
  public
    LineNo: Integer;     // 1-based; also in the message as 'line <n>: ...'
  end;

function EscapeRepoValue(const pValue: string; pInHeader: Boolean): string;
function UnescapeRepoValue(const pText: string): string;
procedure BackupRepositoryToStrings(pConnection: TFDConnection; pLines: TStrings);
procedure BackupRepository(pConnection: TFDConnection; const pFileName: string);
procedure RestoreRepositoryFromStrings(pConnection: TFDConnection; pLines: TStrings;
  pReplace: Boolean);
procedure RestoreRepository(pConnection: TFDConnection; const pFileName: string;
  pReplace: Boolean);
```

Implements design section 8 rules 1-8 exactly. Additional decisions:

* Rows are read with `SELECT * FROM "<t>" ORDER BY <pk columns>` (SQLite BINARY collation).
* `BackupRepository` writes bytes itself: every char must be < 0x80 after escaping (assert),
  CRLF, no BOM, and writes to `<file>.tmp` then renames over the target.
* Restore: parse + validate everything into memory first. Errors (`ERepoBackupFormatError`
  with `LineNo`): first line not `#DLREPO 1`; unknown table; unknown column; a PK column in
  the body; wrong number of PK values; a NOT NULL column missing (even one with a default); bad escape;
  non-ASCII byte; a body line outside a record; `#end` count <> records read; a table
  appearing twice or out of order; a missing `#end` for any of the 5 tables; a value that
  does not parse for its kind (`true`/`false`, decimal). Then: repository not empty and not
  `pReplace` -> `ERepoError`. Then ONE transaction: delete all rows of all 5 tables, insert.
  A column omitted in the file is inserted as NULL explicitly (never the column default).
* `RestoreRepository` reads the file as raw bytes and rejects any byte >= 0x80; it accepts
  LF-only line ends on input.

### C2. Fixtures `tests\fixtures\fieldrepo\`

* `golden.dlrepo.txt` -- hand-written, canonical: `DL_META` 1 row; `DL_FIELDS_INFO` 6 rows over
  2 tables; `DL_DATASETS_INFO` 2 rows with 3-line SQL (one CRLF text, one LF text);
  `DL_ENUMVALUES` 3 rows; `DL_ERROR_MESSAGES` 1 row.
* `edge.dlrepo.txt` -- NULL vs empty string; trailing space; tab; backslash; `\u00E9`; a PK
  value containing `|` and `]`; TEXT ending in LF; an empty table.
* `bad_*.dlrepo.txt` -- one file per error class of C1, each a copy of `golden` with ONE
  defect, and the expected error line number in its NAME (`bad_unknown_column_L7.dlrepo.txt`).

### C3. Tests `tests\fieldrepo\TextBackupTests.dpr` (FIRST)

1. Escape/unescape pairs for every rule-7 case; `UnescapeRepoValue(EscapeRepoValue(s)) = s`
   for a string holding every char 0..0x2FF.
2. GOLDEN: restore `golden` into a new repository, `BackupRepository` to a temp file -> the
   bytes equal the fixture's bytes. Same for `edge`.
3. Values: after restoring `edge`, the NULL column `IsNull`, the empty column is '' and not
   NULL, the trailing-space value has its space, the TEXT values have the exact CR/LF bytes.
4. Stability: backup twice -> identical bytes; insert rows in reverse key order in a second
   repository -> identical bytes.
5. Output hygiene: no byte >= 0x80, no LF without CR, no BOM, last line is the
   `#end DL_ERROR_MESSAGES <n>` trailer + CRLF.
6. Every `bad_*` fixture raises `ERepoBackupFormatError` with `LineNo` = the number in its
   file name, and the repository (pre-filled from `golden`) is byte-identical afterwards
   (compare a backup before/after). Positive control: `golden` restores with `pReplace`.
7. Restore into a non-empty repository without `pReplace` raises `ERepoError`; with it,
   succeeds and old rows are gone.
8. A column default does not leak: a row omitting `DOC_SUMMARY` restores as NULL, not
   'Summary here'; a row omitting the NOT NULL column `VISIBLE` is a format error.

### C4. Runner + build bat (as A3).

## 5. Lane D -- editor `src\tools\field-repo\`

No `.dfm` anywhere in this lane: all UI is created in code (design section 7).

| File | Content |
|---|---|
| `dl-field-repo.dpr` | parse args, `--selftest` path, else `Application.Run` |
| `FieldRepo.Data.pas` | `TRepoSession`: owns the connection + one `TFDQuery` + `TDataSource` per data table |
| `FieldRepo.GridHost.pas` | `IRepoGridHost`, `CreateRepoGridHost` (the only `{$IFDEF USE_DevEx_Grid}`) |
| `FieldRepo.GridHost.Std.pas` | TDBGrid implementation |
| `FieldRepo.GridHost.DevEx.pas` | TcxGrid implementation (compiled only with the define) |
| `FieldRepo.MainForm.pas` | `TFieldRepoMainForm` (`CreateNew`): menu, page control, tabs, status bar |
| `FieldRepo.SelfTest.pas` | `RunSelfTest(pSession, pReportFile): Integer` |
| `tests\FieldRepoDataTests.dpr` | console tests of `TRepoSession` |

### D1. `TRepoSession` (tests first, `tests\FieldRepoDataTests.dpr`)

```pascal
TRepoSession = class
  constructor Create(const pRepoFile: string; pReadOnly: Boolean);
  function TableCount: Integer;                              // 4 (DL_META is not shown)
  function TableName(pIndex: Integer): string;
  function DataSet(pIndex: Integer): TFDQuery;
  function DataSource(pIndex: Integer): TDataSource;
  function MemoFieldNames(pIndex: Integer): TArray<string>;  // the rckText columns
  property ReadOnly: Boolean;
end;
```

Queries: `SELECT * FROM "<t>" ORDER BY <pk>`; `UpdateOptions.UpdateTableName`, `KeyFields` =
PK columns, `RequestLive`; each `TField.DisplayLabel` = the column name; `TField.Required`
from `NotNull` when there is no default. Tests: (1) 4 tables in schema order; (2) edit
`DISPLAY_LABEL`, `Post`, reopen with a NEW session -> value persisted; (3) append a row with
only key fields -> defaults applied after refresh; (4) duplicate key on `Post` raises and the
dataset can `Cancel`; (5) a read-only session raises on `Edit`/`Post` and the file's bytes are
unchanged; (6) `MemoFieldNames` for `DL_DATASETS_INFO` = the 6 TEXT columns in order.
Seed data: create rows with plain INSERTs in the test (do not depend on lanes B/C).

### D2. Grid hosts

`Attach` creates the grid on `pParent` (`alClient`), bound to `pSource`, one column per
dataset field in field order; TEXT fields are shown read-only as `(memo)` in the grid and
edited in the memo panel; boolean columns as check boxes (`TDBGrid`: a pick list
`True`/`False` is acceptable; `TcxGrid`: `TcxCheckBoxProperties`). `ReadOnly` session ->
grid not editable. DevEx variant: `TcxGrid` + `TcxGridDBTableView`, `DataController.CreateAllItems`,
`OptionsView.ColumnAutoWidth = False`, incremental search + filter row on, NO skin controller.

### D3. Main form

Menu `File`: `Open repository...`, `Reload`, `Exit`; (`Backup to text...`, `Restore from
text...` added in D5). One tab per table, caption = the DL_ table name. Each tab: top
`TDBNavigator`, client = grid host, bottom panel (splitter) with one `TDBMemo` per TEXT column
on a small inner `TPageControl` (hidden when the table has no TEXT column). Status bar: repo
path, `READ ONLY` when applicable, `<table>: <n> rows` for the active tab, grid kind.
Unposted edits are posted or cancelled (ask) on tab change and on close.

### D4. Self-test, build bats, runner

`dl-field-repo.exe --repo <f> --selftest <report>`: create the form WITHOUT showing it,
activate each tab, write per tab `TAB <table> rows=<RecordCount after FetchAll> cols=<grid
VisibleColumnCount> grid=<std|devex>`, then `SELFTEST OK` and exit 0; any exception ->
`SELFTEST FAIL <class>: <message>`, exit 1. Missing `--repo`/`--project` in selftest mode ->
exit 2. No message box may appear in selftest mode.

`build\_build_field_repo_local.bat`: `dcc64 -B -NUdcu -E. -U"..\..\sql" -NSSystem;Winapi;System.Win;Vcl;Data;FireDAC dl-field-repo.dpr`
(TDBGrid). `build\_build_field_repo_devex_local.bat`: same plus `-DUSE_DevEx_Grid` and
`-U"%DL_DEVEX_LIB%"`; when `DL_DEVEX_LIB` is empty it prints
`BUILD_SKIPPED DL_DEVEX_LIB not set` and `BUILD_EXITCODE=3` (owner question Q3).

`tests\autotest\run_fieldrepo_editor.ps1`: build the data tests + the std exe; run the data
tests; create a repository with a tiny helper path of the DATA TEST exe
(`FieldRepoDataTests.exe --make-sample <file>` writes a repository with 3 / 2 / 2 / 1 rows);
run `--selftest`; assert exit 0, `SELFTEST OK`, exactly 4 `TAB` lines, rows 3/2/2/1, cols
41/13/6/4, `grid=std`. Negative: `--selftest` on a non-repository file exits 1 with
`SELFTEST FAIL` (positive control = the run above). The DevEx build is verified by the same
selftest with `grid=devex` only when `DL_DEVEX_LIB` is set; otherwise the runner prints
`SKIP devex (DL_DEVEX_LIB not set)` and still passes.

### D5. Phase 2 menu (after lane C is merged)

`File > Backup to text...` (save dialog, default `<repo>.txt`) -> `BackupRepository`;
`File > Restore from text...` (open dialog, confirm "replaces ALL rows") ->
`RestoreRepository(..., True)` then reload every dataset; a format error shows the message
with its line number and changes nothing. Selftest gains `--selftest-backup <file>`: performs
the backup through the same handler code path (no dialog) so the runner can assert that the file
restores into a new repository (`RestoreRepository` via the data test exe helper
`--restore-backup <file> <newrepo> <out>`) and backs up again to the same bytes.

## 6. Lane E -- CLI verbs, docs, registry

Never read `DRagLint.CLI.pas` whole (2 MB). Anchors: `DoFbSnapshot` (about line 19474) is
the model for a Firebird-connecting verb and uses `TArgs.FbConnection` (`--connection`); the
verb dispatch chain is at about line 40650 (`else if Args.Command = '...'`). Find the
two-word-verb parsing with `drag-lint query --text "export enums" --db <db>`.

### E1. `src\cli\DRagLint.CLI.Repo.pas` -- one public entry

`function RunRepoVerb(const pSub, pRepo, pProject, pConnection, pInFile, pOutFile: string;
pReplace, pJson: Boolean): Integer;` -- all logic here; `DRagLint.CLI.pas` gets only: the
`TArgs` fields `RepoPath` (`--repo`) and `Replace` (`--replace`), their parsing, and one
dispatch line for `repo`. Add the three core units and this unit to `drag-lint.dpr` /
`.dproj` (then `drag-lint lint --project src\cli\drag-lint.dproj --rule unit-not-in-dpr` = 0).

| Verb | Behaviour | Exit |
|---|---|---|
| `repo init` | `CreateRepository`; prints the path | 0; 1 when it exists |
| `repo info [--json]` | path, schema version, per table row count, the DL_META keys | 0; 1 not a repository |
| `repo import-fb --connection "..." [--replace]` | design section 9, incl. the `before-import` text backup and the count check | 0; 1 failure; 2 schema drift |
| `repo backup --output <file>` | `BackupRepository` (default `<repo>.txt`) | 0 / 1 |
| `repo restore --in <file> [--replace]` | creates the repository when missing, then `RestoreRepository`; a format error prints `line <n>: ...` | 0; 1; 2 format error |

Path: `--repo` wins; else `--project` -> `DefaultRepoPath`; neither -> usage error exit 1.
Unknown sub-verb -> usage error naming the five.

### E2. Runners (write FIRST, watch them fail on "unknown command")

`run_repo_cli_roundtrip.ps1` (needs no Firebird): `repo restore --in tests\fixtures\fieldrepo\golden.dlrepo.txt --repo <tmp>`
-> exit 0 and the file exists; `repo info --json` -> row counts equal the fixture's `#end`
numbers (parse the JSON, print its raw shape once while writing the test); `repo backup
--output <tmp2>` -> bytes equal the fixture; second `repo restore` without `--replace` ->
exit 1 and counts unchanged; `repo restore --in bad_unknown_column_L7...` -> exit 2, stderr
has `line 7`; `repo init` on the existing file -> exit 1; `repo info` on a text file -> exit 1;
`--project <tmp>\X.dproj` resolves to `<tmp>\_DL-REPO\X.dlrepo`.

`run_repo_cli_import_fb_live.ps1`: when `$env:DL_TEST_FB_CONNECTION` is empty print
`SKIP live Firebird import (DL_TEST_FB_CONNECTION not set)` and exit 0. Otherwise: import
into a temp repository; for each of the 4 tables compare `repo info --json` with
the verb's own printed `<table>: <n> rows (source <m>)` line (the verb reads m with a
separate `SELECT COUNT(*)` on the source): n = m for all four, and n > 0 for `DL_FIELDS_INFO`; re-run without `--replace` -> exit 1; with `--replace` -> exit 0 and a
`before-import-*.txt` file exists and restores (`repo restore`) into a third repository with
the same counts.

### E3. Docs in sync + registry (same commit as E1)

`--help` banner lines for the five verbs with every flag on the verb's line; `README.md`
verb list; `docs\AI-USAGE.md` verb table; `featuregen add --id field-repository ...` with
surfaces `cli:repo init ;; cli:repo info ;; cli:repo import-fb ;; cli:repo backup ;;
cli:repo restore ;; tool:dl-field-repo.exe` (use the surface types `featuregen --help` lists;
no `ide-menu` surface yet); write `docs\wiki\field-repository.md` (what it is, the five verbs,
the editor, the text format summary, "Firebird is not modified"); `featuregen normalise`,
`featuregen build --all`, `featuregen verify --id field-repository --by ENGINE`. Guards that
must pass: `run_docs_sync_guard.ps1`, `run_feature_registry_guard.ps1`,
`run_encoding_guard.ps1`, `run_extractor_version_guard.ps1`.

## 7. Lane F -- integration and review (session model)

1. Merge A, B, C, D, E; build engine (`build\build_draglint_win64.bat` into a PRIVATE copy,
   no deploy without the owner's go) and both editor variants (DevEx when `DL_DEVEX_LIB` is set).
2. Run the six new runners + the four guards of E3, then the battery.
3. Live import, read-only on Firebird: `DL_TEST_FB_CONNECTION` = the Micronite dev database
   (`C:\Projects\DB\SQL\MICRONITEV6A.FDB`); expected on 2026-11-16 data: 2117 / 134 / 51 / 0
   -- compare with the live counts, the numbers are only a sanity hint. Then `repo backup`,
   `repo restore` into a second file, `repo backup` again -> identical bytes on REAL data.
   Open the imported repository in the editor (`--selftest`: cols 41/13/6/4).
4. Whole-branch lint sweep per the repo CLAUDE.md (full diff, `review-marker-stale` +
   `review-marker-unused` with the enabled rules).
5. Code review against the design: section 4 column contract vs `RepoTables` line by line;
   every doc comment vs its test.
6. Owner test page (skill `owner-test-page`): click-level steps -- run the import command,
   open `dl-field-repo.exe`, edit one caption, backup, diff the text file.

## 8. Out of scope here

Schema index, publish back to Firebird, domain constants, lint rules, codegen, IDE menu, the
`fieldRepository` project-file key, column triage (design section 11). Owner questions
Q1-Q6 (design section 12) do not block lanes A-D; Q1 and Q2 should be answered before lane E
ships its docs, Q3 before the DevEx variant can be verified.
