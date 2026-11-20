# Plan TT-TRIAGE -- column triage: usage report + schema v2 migration (spec phase 9)

Spec: `docs\superpowers\specs\2026-11-20-tabletools-publish-triage-design.md` section 3 (criteria T1-T8, fate table 3.2,
schema 3.3), section 0 (D2-D4). Lane rules: `C:\TEMP\claude\lanes\v1522\COMMON-BRIEF.md` + `v1523\PLAN.md` section 1.
Wave W3, 1.53.0. Model: Opus recommended (Schema.pas is read by every TT feature; the v1 path must stay
byte-identical) -- sonnet acceptable if the controller judges the plan complete.

Worktree `C:\TEMP\claude\lanes\v153\TT-TRIAGE\wt`, branch `lane/v153-tt-triage` from `lane/v153-int`.

## File fence (differs from PLAN.md W3: Grid.pas dropped per D4; CLI unit added; Form.pas one line)

| File | Change |
|---|---|
| `src\sql\DRagLint.FieldRepo.Schema.pas` | v2 table, versioned table sets, open accepts 1..2, CreateRepository(pVersion), fate defaults, RepoIsEmpty skips DL_COLUMN_FATE |
| `src\sql\DRagLint.FieldRepo.TextBackup.pas` | `#DLREPO 1` / `#DLREPO 2` by repository version; restore rules of spec 3.3 |
| NEW `src\sql\DRagLint.FieldRepo.Triage.pas` | usage report + migration (pure over a connection) |
| NEW `src\cli\DRagLint.CLI.RepoTriage.pas` | `repo triage`, `repo migrate` (precedent: `DRagLint.CLI.RepoParamArray`) |
| `src\cli\DRagLint.CLI.Repo.pas` | HUB COMMIT (<= 12 lines): dispatch `triage`/`migrate`, IsImplementedSub, SUB_VERBS; RepoInfo + RepoRestore use the repository's own table set (they call RepoTables today, lines ~191/209) |
| `src\cli\drag-lint.dpr` + `.dproj` | the two new units |
| `src\tools\field-repo\DRagLint.FieldRepoEd.Form.pas` | ONE line: `IsEditableTable` also excludes `DL_COLUMN_FATE` |
| `src\tools\field-repo\dl-field-repo.dpr`, `dl-field-repo-std.dpr` | only if a new unit is pulled in (it should not be) |
| `tests\fieldrepo\SchemaTests.dpr`, `TextBackupTests.dpr` | updated + new cases |
| NEW `tests\fieldrepo\TriageTests.dpr`, `build\_build_fieldrepo_triage_tests_local.bat`, `tests\autotest\run_fieldrepo_triage.ps1` | |
| NEW `tests\fixtures\fieldrepo\golden_v2.txt` | a `#DLREPO 2` golden (the v1 golden + fate block) |
| `features\entries\field-repository.json` (featuregen only), `docs\wiki\field-repository.md` | cli subs, help lines, "Column triage" section with the 3.2 table |

CLI.Repo.pas is also touched by TT-PUBLISH and TT-FIBREMOVE in the same wave: keep this lane's CLI.Repo edit a
separate commit named `hub: repo triage/migrate dispatch`; the INT step unions the three `IsImplementedSub` /
`SUB_VERBS` edits. Confirm the fence with the index at start (`find-callers --name RepoTables`, `--name RepoIsEmpty`,
`--name OpenRepository` on the lane DB copy) -- callers today: CLI.Repo 176/191/209/230/245/344/380,
FbImport 353, SchemaSeed 793, TextBackup 422/507/871, DataServiceGen 357, editor Form/SelfTest (not in the CLI index).

## Schema.pas interface changes (DocInsight; remarks state the v1 compatibility rule)

```pascal
const
  REPO_SCHEMA_VERSION = 2;          // version that init/import/seed create
  REPO_SCHEMA_MIN_VERSION = 1;      // oldest version OpenRepository accepts
  REPO_FATE_TABLE = 'DL_COLUMN_FATE';
type
  TRepoColumnFate = record TableName, ColumnName, Fate, Reason: string; end;
function RepoTablesFor(pVersion: Integer): TArray<TRepoTable>;   // 1 -> 5 tables, 2 -> 6
function RepoTables: TArray<TRepoTable>;                          // = RepoTablesFor(REPO_SCHEMA_VERSION)
function RepoVersion(pConnection: TFDConnection): Integer;        // PRAGMA user_version
procedure CreateRepository(const pFileName: string; pVersion: Integer = REPO_SCHEMA_VERSION);
function DefaultColumnFates: TArray<TRepoColumnFate>;             // spec 3.2, one row per column, every data-table column exactly once
const FATE_WORDS: array[0..4] of string = ('keep', 'schema-cache', 'keep-planned', 'retire-candidate', 'retire');
```

* `ValidateRepository`: application_id as today; user_version in [MIN..CURRENT] else ERepoSchemaError (the
  existing "user_version 99" test stays); validate `RepoTablesFor(version)`.
* `CreateRepository(f, 2)` seeds DL_COLUMN_FATE from DefaultColumnFates (`RULED_BY = 'default-2026-11-20'`) in
  the same transaction; `CreateRepository(f, 1)` = today's bytes exactly.
* `RepoIsEmpty` ignores DL_META and DL_COLUMN_FATE and iterates the repository's own version's tables.
* DL_COLUMN_FATE columns: `Str('TABLE_NAME',63,True,1)`, `Str('COLUMN_NAME',63,True,2)`, `Str('FATE',20,True)`,
  `Str('REASON',220)`, `Str('RULED_BY',63)`; SourceName ''.

## Triage.pas

```pascal
type
  TColumnUsage = record TableName, ColumnName, Fate, Reason: string; Rows, NonNull, NonDefault: Integer;
    Conflict: Boolean; end;
function ColumnUsageReport(pRepo: TFDConnection): TArray<TColumnUsage>;   // v1: fates from DefaultColumnFates; v2: from the table
function UsageReportLines(const pUsage: TArray<TColumnUsage>): TArray<string>;
function UsageReportJson(const pUsage: TArray<TColumnUsage>): string;
function MigrationPlan(pRepo: TFDConnection): TArray<string>;            // [] when already current
procedure MigrateRepository(pRepo: TFDConnection);                        // one transaction; caller wrote the backup
```

Non-default (T1): `NOT NULL` and `<> DEFAULT` when the column has DefaultSql (compare in SQL:
`SUM(CASE WHEN "C" IS NOT NULL AND "C" <> <DefaultSql> THEN 1 ELSE 0 END)`); without a default: strings
`<> ''`, numbers `<> 0`, booleans `<> 0`. Text defaults (`'Summary here'`) compare as text. One SELECT per table.
Unknown fate word -> an error row (T8). Conflict (T2): fate retire-candidate/retire and NonDefault > 0.

## Tasks (TDD; RED on the INT build first, GREEN after; both runs named in REPORT)

1. **Versioned schema.** SchemaTests: 1a RepoTablesFor(1) = 5 tables and RepoTables = 6 (update the "5" checks);
   new S1 `CreateRepository(f,1)` file validates with user_version 1; S2 `CreateRepository(f)` = v2, fate rows =
   Length(DefaultColumnFates) and every column of the four data tables appears exactly once (and no unknown
   column: positive + negative control); S3 user_version 3 and 0 rejected; S4 RepoIsEmpty true on a fresh v2
   (fate rows present) and false after one DL_ENUMVALUES row; S5 DefaultColumnFates rows match spec 3.2
   (assert 6 named rows: BG_COLOR retire-candidate, DOC_SUMMARY keep-planned, ALIGNMENT keep,
   FIELD_TYPE schema-cache, CONDITIONS retire-candidate, EVALUE keep).
2. **Text backup by version.** TextBackupTests: B1 existing golden (`#DLREPO 1`) restore into a v1 repo then
   backup = same bytes (T7, v1; the existing test, now on an explicit v1 repo); B2 `golden_v2.txt` into a v2 repo
   round trip bytes equal (T7, v2); B3 `#DLREPO 1` file into a v2 repo -> five tables restored, fate rows =
   defaults; B4 `#DLREPO 2` file into a v1 repo -> ERepoBackupFormatError line 1 "migrate first", repo unchanged;
   B5 `#DLREPO 3` -> line 1 error. CLI: `repo restore` into a MISSING file creates the file's version
   (run_repo_cli_roundtrip.ps1 R1-R3 must stay green unchanged -- run it, do not edit it).
3. **Usage report.** TriageTests: U1 fixture repo (v2) with ALIGNMENT non-default in 2 rows, BG_COLOR all 0 ->
   ALIGNMENT NonDefault 2, BG_COLOR 0, no conflict; U2 set BG_COLOR=1 on one row -> Conflict, report exit code
   path returns 1 (T2) and the line says `CONFLICT`; U3 DOC_SUMMARY = 'Summary here' counts as default, other
   text counts (T1); U4 NULL DISPLAY_LABEL not counted, '' not counted, 'x' counted; U5 fate 'maybe' -> error row
   (T8); U6 v1 repo -> fates from defaults; U7 JSON parses with one object per column; U8 report opens read-only
   (file hash unchanged).
4. **Migration.** M1 MigrationPlan on v1 = the T3 line; on v2 = []; M2 dry run: file hash before = after (T3);
   M3 MigrateRepository: user_version 2, DL_META schema_version '2', fate rows = defaults; M4 T6: backup after
   migrate = v1 backup with line 1 `#DLREPO 2` and the DL_COLUMN_FATE block inserted after DL_ERROR_MESSAGES's
   trailer -- assert by building the expected text from the two pieces; M5 failure inside the transaction
   (pre-create a conflicting DL_COLUMN_FATE table in a v1 file) -> rollback, user_version still 1, error names
   the table.
5. **CLI.** `repo triage [--json]` (exit 0, 1 on conflict or bad fate); `repo migrate` dry run default, `--apply`
   writes `<repo>.before-migrate-<yyyymmdd-hhnnss>.txt` (BackupRepository on the v1 repo) then migrates, prints
   both; on v2 `already at schema 2`. Runner `run_fieldrepo_triage.ps1` also drives the exe: C1 init -> triage
   exit 0; C2 restore v1 golden -> migrate (dry) hash unchanged -> migrate --apply -> before-migrate file exists
   and `repo restore --in <it>` into a fresh path reproduces the v1 bytes; C3 triage --json parses.
6. **Editor.** Form.pas one line; run `run_fieldrepo_editor.ps1` (self test: still 4 tabs, both builds).
7. **Live check (read-only, optional).** If `DL_TEST_FB_CONNECTION` is set: import-fb into a temp repo, triage,
   compare the NonDefault counts with spec section 1 (record differences, do not fail on drift).
8. **Docs + lint.** Registry (subs `triage`, `migrate`; help lines; `featuregen verify --id field-repository --by ENGINE`),
   wiki "Column triage" with the 3.2 table and how to record an owner ruling (edit the fate line in the text
   backup, `repo restore --replace`). Lint as in the COMMON-BRIEF on every changed unit.

## Acceptance (MERGE-READY)

New and updated test programs SUMMARY fail=0; EVERY existing `run_fieldrepo_*.ps1`, `run_repo_cli_roundtrip.ps1`,
`run_fieldrepo_editor.ps1` green (they prove the v1 path is unchanged); no column dropped anywhere (grep the
diff for `DROP` = 0 hits outside comments); lint counts reported.
