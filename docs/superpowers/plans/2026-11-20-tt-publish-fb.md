# Plan TT-PUBLISH -- `drag-lint repo publish-fb` (M17)

Spec: `docs\superpowers\specs\2026-11-20-tabletools-publish-triage-design.md` section 2 (criteria P1-P13), section 0
(rulings). Lane rules: `C:\TEMP\claude\lanes\v1522\COMMON-BRIEF.md` + `C:\TEMP\claude\lanes\v1523\PLAN.md` section 1.
Wave W3, 1.53.0. Model: sonnet (fully specified) -- escalate to Opus if task 4 (SQL sink on the SQLite stand-in)
needs a design change.

Worktree `C:\TEMP\claude\lanes\v153\TT-PUBLISH\wt`, branch `lane/v153-tt-publish` from `lane/v153-int`.

## File fence

| File | Change |
|---|---|
| NEW `src\sql\DRagLint.FieldRepo.FbPublish.pas` | diff + sink + apply + verify |
| `src\cli\DRagLint.CLI.Repo.pas` | sub-verb `publish-fb` (RepoFbVerb list, IsImplementedSub, SUB_VERBS) |
| `src\cli\DRagLint.CLI.pas` | HUB COMMIT ONLY: one ParseArgs arm `(Result.Command = 'repo') and (A = '--delete-missing')` (flag, no value). `--apply`, `--table`, `--json`, `--connection` already parse |
| NEW `tests\fieldrepo\FbPublishTests.dpr` | console PASS/FAIL tests (no Firebird) |
| NEW `build\_build_fieldrepo_fbpublish_tests_local.bat` | copy of `_build_fieldrepo_fbimport_tests_local.bat`, dpr name changed |
| NEW `tests\autotest\run_fieldrepo_fbpublish.ps1` | copy of `run_fieldrepo_fbimport.ps1` shape (FAIL when toolchain/exe missing) |
| NEW `tests\autotest\run_repo_cli_publish_fb_live.ps1` | live scratch round trip; SKIP when `DL_TEST_FB_CONNECTION` unset |
| `src\cli\drag-lint.dpr` + `src\cli\drag-lint.dproj` | add `DRagLint.FieldRepo.FbPublish in '..\sql\DRagLint.FieldRepo.FbPublish.pas'` after line 231 (DataServiceGen) and the matching DCCReference; then `drag-lint reconcile-project src\cli\drag-lint.dproj --json` (read-only, no --db) shows no gap |
| `features\entries\field-repository.json` | via `featuregen` edit only: cli sub `publish-fb`, usage + help line, flags `--delete-missing` |
| `docs\wiki\field-repository.md` | section "Publish to Firebird" |

Confirm the list at lane start with the index (`drag-lint query --name ImportTableFromDataSet --db <lane db copy>`,
`query --text "import-fb"`). Anything else = stop and ask the controller.

## Interface to write (DocInsight on every public symbol; the summary/remarks carry the P-criterion wording)

```pascal
unit DRagLint.FieldRepo.FbPublish;
interface
uses System.SysUtils, Data.DB, FireDAC.Comp.Client, DRagLint.FieldRepo.Schema;
type
  TPublishOp = (popInsert, popUpdate, popDelete);
  TPublishRow = record
    Op: TPublishOp;
    Key: TArray<Variant>;          // PK values in PkOrder
    KeyText: string;               // 'A|B' for output, PK order
    Columns: TArray<string>;       // changed columns (update) / all non-PK (insert) / empty (delete)
  end;
  TPublishTableDiff = record
    Table: TRepoTable;
    Rows: TArray<TPublishRow>;     // PK ascending, deterministic
    Same: Integer;
    function Count(pOp: TPublishOp): Integer;
  end;
  IPublishSink = interface
    procedure InsertRow(const pTable: TRepoTable; pRepoRow: TDataSet);        // values from the current DL row
    procedure UpdateRow(const pTable: TRepoTable; pRepoRow: TDataSet; const pColumns: TArray<string>);
    procedure DeleteRow(const pTable: TRepoTable; const pKey: TArray<Variant>);
  end;
  TPublishOptions = record
    Tables: TArray<string>;        // DL_ names; empty = the four data tables
    Apply: Boolean;
    DeleteMissing: Boolean;
  end;

function ComputePublishDiff(pRepo: TFDConnection; const pTable: TRepoTable; pTarget: TDataSet): TPublishTableDiff;
procedure ApplyPublishDiff(pRepo: TFDConnection; const pDiff: TPublishTableDiff; const pSink: IPublishSink;
  pDeleteMissing: Boolean);
function CreateSqlPublishSink(pTarget: TFDConnection): IPublishSink;   // dialect-neutral SQL, quoted idents
function FormatPublishDiff(const pDiffs: TArray<TPublishTableDiff>; pApplied, pDeleteMissing: Boolean;
  pMaxRowsPerTable: Integer): TArray<string>;
function PublishDiffJson(const pDiffs: TArray<TPublishTableDiff>; pApplied: Boolean; const pDatabase: string): string;
/// orchestration used by the CLI and (W4) the editor: opens nothing itself
function RunPublish(pRepo, pTarget: TFDConnection; const pOpt: TPublishOptions;
  out pDiffs: TArray<TPublishTableDiff>; out pVerifyError: string): Boolean;
```

`RunPublish`: for each table: check columns (reuse `CheckSourceColumns` of FbImport on `SELECT * FROM "FIB$X"`
-- FIB$VERSION is already ignored there), compute diff; if not Apply -> return True. If Apply: StartTransaction on
pTarget, ApplyPublishDiff per table, Commit (Rollback + re-raise on any exception); then recompute every diff and
set pVerifyError to the first non-same key (deletes ignored when not DeleteMissing). Result = pVerifyError = ''.
The before-publish backup is NOT in this unit (the CLI does it, task 5) so the unit stays file-free.

Comparison (P-spec 2.2): NULL vs '' distinct; strings `=` (case-sensitive, no trim); booleans via AsBoolean;
integers via AsLargeInt; rckByte via the same byte decode as `FbImport.ByteOfField` (move that helper's logic
into a shared private copy -- do NOT change FbImport's interface). FIB$VERSION never compared.

SQL sink: INSERT lists every RepoTable column + `"FIB$VERSION"` = 0 when the target table has that column
(probe once per table with `SELECT FIRST 0`-free query: read `FieldDefs` of `SELECT * ... WHERE 1=0`);
UPDATE sets only pColumns, `WHERE` on the PK; DELETE by PK. Params typed per kind: rckString ftWideString,
rckText ftWideMemo, rckBoolean ftBoolean, rckInteger ftInteger, rckSmallint ftSmallint, rckByte ftBytes size 1
(TBytes of length 1). Never concatenate a value into SQL.

## Tasks (TDD: each test RED on the INT engine/build first, then GREEN; name both runs in REPORT)

1. **Test scaffolding.** `FbPublishTests.dpr` modelled on `tests\fieldrepo\FbImportTests.dpr` (Check/PASS/FAIL,
   SUMMARY line, temp files under `%TEMP%\dl-fbpublish-<pid>`). Helpers: `NewRepo` (CreateRepository + fixture
   rows inserted by SQL: 3 DL_FIELDS_INFO incl. one with NULL DISPLAY_LABEL and one with '' DISPLAY_LABEL,
   2 DL_DATASETS_INFO with multi-line CRLF SQL, 2 DL_ENUMVALUES with EVALUE 0 and 255), `MemTarget(table)`
   building a TFDMemTable with the FIB$ columns (+ FIB$VERSION) and given rows, `ScratchFbStandIn` creating a
   SQLite file with `CREATE TABLE "FIB$FIELDS_INFO"(...)` etc. derived from `RepoTableDdl` with the name
   replaced and `"FIB$VERSION" INTEGER` appended. Build bat + runner. RED: unit missing.
2. **Diff.** Tests D1 equal -> all same; D2 DL-only row -> insert; D3 FB-only row -> delete; D4 caption changed
   -> update listing exactly DISPLAY_LABEL; D5 NULL vs '' -> update (and '' vs '' -> same, positive control);
   D6 trailing blank differs -> update; D7 FIB$VERSION differs only -> same; D8 order = PK ascending
   (string PK BINARY order, integer PK numeric: DS_ID 2 before 10); D9 EVALUE 255 vs 255 same, 255 vs 0 update;
   D10 extra column in target -> ERepoError naming it, missing column -> names it (P3).
3. **Format/JSON.** F1 text header line exact (`DL_FIELDS_INFO -> FIB$FIELDS_INFO: insert 1, update 1, delete 1 (kept), same 1`);
   F2 cap: 205 inserts with max 200 -> 200 lines + `  ... 5 more`, counts uncapped; F3 JSON parses, `applied`
   false, has `database`, contains no `Password` substring when the connection string had one (P11, feed a string
   with `Password=secret` through the CLI path in task 5 instead if the unit never sees it -- then assert in the ps1).
4. **Sink + apply + verify on the SQLite stand-in.** A1 recording sink receives exactly the diff ops; A2 SQL sink on
   the stand-in: apply -> recompute diff -> all same (P7); A3 delete NOT applied without DeleteMissing, row still
   there, verify passes (P8); with DeleteMissing row gone; A4 inject a failure (stand-in table with an extra
   NOT NULL column without default -> insert fails) -> whole publish rolled back: row counts of every stand-in
   table unchanged (P6); A5 update never touches FIB$VERSION (set it to 7 in the stand-in, publish an update,
   still 7); insert writes 0 (P9); A6 text with CRLF, LF, tab and a non-ASCII char survives apply -> verify same.
   A7 dry run (Apply=False) on the stand-in: file hash before = after (P1).
5. **CLI.** `RepoPublishFb` in CLI.Repo: no `--connection` -> exit 1 before anything (P2; already true via
   RepoFbVerb -- assert); open repo READ-ONLY (`OpenRepository(Path, True)` -- publish never writes the repo
   except DL_META after a committed apply, which reopens read-write); open FB with `OpenSourceConnection`;
   on `--apply`: write `<repo>.before-publish-<yyyymmdd-hhnnss>.txt` = create a temp repository in
   `%TEMP%`, `ImportTableFromDataSet` each published FIB$ table into it, `BackupRepository`, delete the temp
   repo; print `before-publish backup: <path>` (P5); run; print lines; on success set DL_META `published_at_utc`,
   `published_to` (Database only) and print the P12 note. Exit: 0 ok, 1 failure/verify error, 2 column drift or
   missing FIB$ table (P3/P4). `--delete-missing` without `--apply` -> exit 1 with a usage line.
   Hub commit: the ParseArgs arm (one line). Tests: extend `run_repo_cli_roundtrip.ps1`? NO (other lanes' file);
   add cases to the new live runner's offline part instead: C1 `publish-fb` without --connection -> 1;
   C2 `--delete-missing` without `--apply` -> 1; C3 unknown table in `--table` -> 1 naming it.
6. **Scratch-Firebird round trip (P10, P13).** See procedure below. Script `run_repo_cli_publish_fb_live.ps1`
   SKIPs (exit 0, prints SKIP) when `DL_TEST_FB_CONNECTION` is unset, and REFUSES (exit 2) when the Database
   value of that string equals `C:\Projects\DB\SQL\MICRONITEV6A.FDB` or does not contain `\lanes\` or `scratch`
   (the scratch fence, PLAN rule 8). Cases: L1 import-fb into repo A; L2 edit A by SQL (one caption, one new
   DL_FIELDS_INFO row, one ESTRING); L3 publish-fb dry run -> `insert 1, update 1` on fields, `update 1` on enums,
   exit 0, FIB$ counts unchanged (count via `repo import-fb` into a throwaway repo); L4 `--apply` -> exit 0,
   before-publish file exists; L5 import-fb --replace into repo B -> backup(B) = backup(A) except DL_META lines
   (P13); L6 EVALUE 255 round trip; L7 restore the before-publish file into repo C, publish C `--apply
   --delete-missing` -> import again equals the L1 state (undo works).
7. **Docs.** featuregen entry (cli sub + help line + flag), `featuregen verify --id field-repository --by ENGINE`,
   wiki section, CHANGELOG line in REPORT. No `featuregen build --all`.
8. **Lint.** `lint <file> --enable magic-literal,multiple-statements-per-line,commented-out-code` on FbPublish.pas
   and CLI.Repo.pas = 0 on changed lines; lint-all on the lane DB copy (rebuilt with the lane engine).

## Scratch-DB procedure (task 6; Firebird read-only except the scratch copy)

```
$S = 'C:\TEMP\claude\lanes\v153\TT-PUBLISH\scratch'; New-Item -ItemType Directory -Force $S
# credentials: ISC_USER / ISC_PASSWORD from the environment ONLY; if absent -> SKIP task 6, owner step
& 'C:\Firebird\Firebird_4_0\gbak.exe' -b -g -user $env:ISC_USER -password $env:ISC_PASSWORD `
    'localhost:C:\Projects\DB\SQL\MICRONITEV6A.FDB' "$S\scratch.fbk"      # -g: NO garbage collection on the source
& 'C:\Firebird\Firebird_4_0\gbak.exe' -c -user $env:ISC_USER -password $env:ISC_PASSWORD `
    "$S\scratch.fbk" "localhost:$S\SCRATCH-TT-PUBLISH.FDB"
$env:DL_TEST_FB_CONNECTION = "Database=localhost:$S\SCRATCH-TT-PUBLISH.FDB;User_Name=$env:ISC_USER;Password=$env:ISC_PASSWORD;DriverID=FB"
pwsh -File tests\autotest\run_repo_cli_publish_fb_live.ps1 -Exe <lane exe>
```

Check the server version with `gbak -z` first (FB4 server: use the Firebird_4_0 tools). Never print the
connection string; REPORT lists the Database values used (scratch path only). Delete nothing; leave the scratch
files in the lane folder. If the credentials are not available: report "task 6 SKIPPED -- owner step" with the
exact commands above for the owner test page.

## Acceptance (MERGE-READY)

`run_fieldrepo_fbpublish.ps1` SUMMARY fail=0 with every D/F/A test; offline C1-C3 green; every existing
`run_fieldrepo_*.ps1` and `run_repo_cli_roundtrip.ps1` still green; live L1-L7 green OR explicitly SKIPPED with the
reason; lint counts reported; registry verified.
