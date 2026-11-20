# Plan TT-FIBREMOVE -- FIB$ run-time reader inventory + removal plan (DL side only)

Spec: `docs\superpowers\specs\2026-11-20-tabletools-publish-triage-design.md` section 4 (criteria R1-R4), section 0
(Q9, D5). Lane rules: `C:\TEMP\claude\lanes\v1522\COMMON-BRIEF.md` + `v1523\PLAN.md` section 1. Wave W3, 1.53.0.
Model: sonnet (fully specified). NO ORM3 edits, no DROP, no Firebird access at all in this lane.

Worktree `C:\TEMP\claude\lanes\v153\TT-FIBREMOVE\wt`, branch `lane/v153-tt-fibremove` from `lane/v153-int`.

## File fence

| File | Change |
|---|---|
| NEW `src\sql\DRagLint.FieldRepo.FbReaders.pas` | pure classifier over `TArray<TStringLitMatch>` + grouping + text/JSON output |
| NEW `src\cli\DRagLint.CLI.RepoFbReaders.pas` | opens the DB read-only (`DRagLint.CLI.Common.OpenReadOnlyStore`), calls `ISymbolStore.SearchText('FIB$', 'substring', <source>, <limit>)` for pas, dfm, sql; feeds the classifier |
| `src\cli\DRagLint.CLI.Repo.pas` | HUB COMMIT (<= 6 lines): in `RunRepoVerb`, before `IsImplementedSub`, `if SameText(pSub, 'fb-readers') then Exit(RunFbReaders(CommandLineValue('--db',''), CommandLineFlag('--all'), pJson));` + SUB_VERBS text |
| `src\cli\drag-lint.dpr` + `.dproj` | the two new units |
| NEW `tests\fieldrepo\FbReadersTests.dpr`, `build\_build_fieldrepo_fbreaders_tests_local.bat`, `tests\autotest\run_fieldrepo_fbreaders.ps1` | |
| NEW `tests\fieldrepo\fbreaders\` | fixture project (below) |
| NEW `docs\PLAN-fib-removal.md` | the inventory + replacement plan + "Note to ORM3" |
| `features\entries\field-repository.json` (featuregen), `docs\wiki\field-repository.md` | sub `fb-readers`, `status` of the sub = internal is NOT possible per sub -> document it publicly as read-only |

`--db`, `--all`, `--json` already parse for `repo` (confirm: `drag-lint query --text "--all" --db <lane db copy>`
shows the ParseArgs arm; if `--db` is rejected for `repo`, add ONE ParseArgs arm in a hub commit to CLI.pas).
CLI.Repo.pas is shared with TT-PUBLISH / TT-TRIAGE this wave: separate commit `hub: repo fb-readers dispatch`.

## Classifier (FbReaders.pas)

```pascal
type
  TFbRefClass = (frcSqlWrite, frcSqlRead, frcPipeTable, frcNameLiteral, frcMention);
  TFbReader = record FilePath, Routine: string; Classes: set of TFbRefClass; Tables: TArray<string>;
    FirstLine, Hits: Integer; end;
function ClassifyFbHit(const pHit: TStringLitMatch): TFbRefClass;
function GroupFbReaders(const pHits: TArray<TStringLitMatch>; pIncludeMentions: Boolean): TArray<TFbReader>;
function FbReadersLines(const pReaders: TArray<TFbReader>): TArray<string>;
function FbReadersJson(const pReaders: TArray<TFbReader>): string;
```

Rules (spec 4.2), applied in this order, case-insensitive, on `pHit.Text`, only when `pHit.Kind` is a literal/format
kind (`comment`/`doc` -> frcMention): `TABLE=FIB$` -> frcPipeTable; INSERT|UPDATE|DELETE|MERGE word together
with `FIB$` -> frcSqlWrite; SELECT or FROM/JOIN followed by `FIB$` -> frcSqlRead; else frcNameLiteral.
Table names = every `FIB$[A-Z0-9_$]+` token (deduplicated, sorted). Grouping key = FilePath + EnclosingQName
(empty routine -> `<unit>`). Order: file, then first line. Hits without `FIB$` in Text are ignored (the store's
substring mode is case-insensitive -- check `fib$` in a comment counts as mention). Never more than the cap:
the CLI asks SearchText for 5000 rows and prints `capped` when it gets 5000.

## Tasks (TDD; RED on INT first, then GREEN)

1. **Classifier tests** (FbReadersTests.dpr, fed hand-built TStringLitMatch arrays; no DB): K1 each rule with a
   positive and a negative example (e.g. `'SELECT * FROM FIB$FIELDS_INFO'` read, `'UPDATE OR INSERT INTO
   FIB$FIELDS_INFO'` write, `'TABLE=FIB$FIELDS_INFO|BLOBS=0'` pipe, `'FIB$ENUMVALUES'` name-literal, a comment
   mention); K2 grouping: two hits in one routine -> one reader with both classes; K3 mentions hidden unless
   pIncludeMentions; K4 table extraction `FIB$DATASETS_INFO JOIN FIB$FIELDS_INFO` -> both; K5 generator name
   `GEN_ID(FIB$FIELD_INFO_VERSION, 1)` -> name-literal with table `FIB$FIELD_INFO_VERSION`.
2. **Fixture project** `tests\fieldrepo\fbreaders\FbFixture.dpr` + a minimal `FbFixture.dproj` listing the units + `uFbReaderA.pas` (one SELECT literal, one
   Format with `UPDATE OR INSERT INTO FIB$FIELDS_INFO`), `uFbReaderB.pas` (`'TABLE=FIB$DATASETS_INFO|BLOBS=0'`),
   `uFbMention.pas` (FIB$ only in a comment), `uFbClean.pas` (no FIB$; negative control). 7-bit ASCII, CRLF.
   Runner R2: copy the lane engine; `index --project tests\fieldrepo\fbreaders\FbFixture.dproj --db <temp>.sqlite
   --rebuild` (a NEW temp DB; never a real one); `repo fb-readers --db <temp> --json` -> exactly 3 readers with the
   planted classes and no uFbClean/uFbMention; with `--all` uFbMention appears as mention; R3: temp DB size and
   mtime unchanged by fb-readers.
3. **CLI**: exit 2 when `--db` missing or the file does not exist / is not an index DB; text output
   `<file>:<line>  <routine>  <classes>  <tables>` + `readers: <n> (write <w>, read <r>, pipe <p>, name <l>)`.
4. **Inventory run** (read-only, on COPIES): copy `C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite`
   and `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` into the lane folder (check `Get-Process
   drag-lint` first and that the source mtimes are older than 10 min -- do not copy a DB being written); run
   `repo fb-readers --db <copy> --json` on each; save the JSON beside the REPORT. Baseline from SPEC-TT
   (2026-11-20): server 50 text matches, client 43 (incl. mentions); readers expected in
   `SERVER\uFIB_FIELDS_INFO_SERVER.pas`, `uFIB_DATASETS_INFO_SERVER.PAS`, `uFIB_ENUMVALUES_SERVER.PAS`,
   `uFIB_ERROR_MESSAGES_SERVER.PAS`, `uDatasetsDef.pas`, `uPipeSessionBuilder.pas`, `uGenericTableRoute.pas`,
   `CLIENT\Blueprint4.ViewModel.pas` (+ `COMMON\uFieldsInfoCache.pas` via the pipe -- check whether its hit is
   comment-only; if so, record that the client reads FIB$ only through the server's pipe table load).
   A reader the spec 2.3 table names but the verb misses = an index gap: log it (`draglint-gaps.log`) and file
   `docs\INBOX-fbreaders-<topic>.md` per the global rules.
5. **`docs\PLAN-fib-removal.md`** (R4): header with date, DB copies used, verb counts; table `reader | file:line |
   classes | tables | replacement | stage`; stage 1 = FIB$ stays a secondary copy fed by `repo publish-fb`
   (all readers keep working, nothing to do in ORM3); stage 2 replacements to propose per class: sql-read of
   FIELDS_INFO/DATASETS_INFO -> a DL-generated unit or resource from the repository (`repo gen-...`, to be
   specified), pipe-table -> served from that generated data, sql-write (the uFIB_*_SERVER data services) ->
   retired with the FIB$ tables, name-literal -> constant from the generated unit; stage 3 = owner ruling + DROP
   (not planned). Also: whether any reader reads DL_DATASETS_INFO.CONDITIONS or the retire-candidate columns of
   spec 3.2 (search the reader routines' literals for the column names) -- report the result to the controller
   so the TT-TRIAGE default can be adjusted (spec risk 6). Section "Note to ORM3" (D5): 10-15 lines the
   controller forwards; no file is written into C:\Projects\DB\ORM3.
6. **Docs + lint** as COMMON-BRIEF; registry sub `fb-readers`, wiki paragraph.

## Acceptance (MERGE-READY)

K1-K5 + R2/R3 green; inventory JSON for both DB copies saved; PLAN-fib-removal.md counts equal the JSON counts;
no write to any real DB (size/mtime of both ORM3 DBs unchanged -- record them before and after); lint counts reported.
