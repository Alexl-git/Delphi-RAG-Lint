<!-- dl:backlog status=open last-measured=2026-10-27 -->
# PLAN D2 -- split convrules\BDE-to-FireDAC.rules into a BDE book and a Data.DB "Book-2"

Lane d2 (converter stream), branch `conv/d2`, 2026-10-27. Classification + plan only; the
rule book is NOT edited by this document. Backlog: `docs\CONVERTER-BACKLOG.md` D2 -> SPLIT.

Sources read: the book (733 lines, 10 `#convert` blocks, 43 trailing `#migrate` lines at
663-733), `convrules\vendor\FireDAC_Migrate_BDE.rules` (the corpus), `docs\converter\convrules-dsl.md`,
`docs\INBOX-REPLY-2026-10-25-engine-to-converter-migrate-contract.md` (G1/G2/G5),
`docs\INBOX-engine-to-converter-chain1.md` (single pass), spec
`docs\superpowers\specs\2026-10-23-converter-migrate-slice1-design.md` section 2 (measured),
engine `src\report\DRagLint.Convert.Apply.pas:5125-5140`, `DRagLint.Convert.DfmReemit.pas:1080-1087`,
`DRagLint.Convert.Rules.pas:238-240`, editor `ConvRules.BlockFile.pas` (rbkTrailing, FILE_SCOPE const),
`ConvRules.ConvertRunner.pas:346-395` (book-major loop). Declaring units were looked up in
`C:\Projects\.drag-lint\library-Win64.sqlite` (`query --name X --exact`), not assumed.

## 0. Result in one paragraph

Classified by the DECLARING UNIT of the From symbol (the only mechanical, defensible criterion):
77 items are BDE (declared in `Bde.DBTables` / BDE units), 9 are not-BDE (declared in `Data.DB`,
shared by every TDataSet family), 11 are unsure (Data.DB-declared types that only BDE event
handlers use in practice). Blocks: 7 BDE / 3 not-BDE (`Data.DB.TParam`, `TParams`,
`TAutoIncField`). The 43 `#migrate` lines: 28 BDE / 5 not-BDE / 10 unsure. Preamble (44
file-scope lines): 42 BDE / 1 not-BDE (`#remove HasConstraints`) / 1 unsure (`#remove DFM: Origin`).
No engine-sense CHAIN (a rule's output being another rule's input) exists between the two books;
there is one CONTAINMENT dependency (Book-2's From classes live inside the datasets the BDE book
converts), which fixes the run order BDE book -> Book-2, reindex between -- the editor's
book-major loop already runs books in the given order with a reindex per book chunk.
Rule A is VALID for `#unuse` / `#remove` / `#mapping` (engine file-scope = before the first
`#convert`), and for `#migrate` it is SAFE but INERT: the engine never applies a `#migrate`
placed before the first header (Apply.pas:5137, G2(c)); today's trailer is just as inert
(it sits in the TBatchMove block for the engine, G5). Book-2 needs no preamble of its own
except the one `#remove` that travels with TAutoIncField.

## 1. Classification

Legend: **BDE** = From symbol declared in `Bde.DBTables` or a BDE unit; **not-BDE** = declared in
`Data.DB` (also used by TClientDataSet / TADOQuery / TIBQuery / TSQLQuery code, so a rename or
conversion is FireDAC-specific, not BDE-specific); **unsure** = Data.DB-declared, but in practice
only BDE handler signatures carry it -- owner call.

### 1.1 Preamble, file-scope lines (book lines 89-150, 44 lines)

| Lines | Directive(s) | Class | Reason |
|---|---|---|---|
| 89-94 | `#unuse BDE.DBTables`, `BDE.BDEConst`, `DBTables`, `BDEConst`, `BDEMTS`, `BDE` (6) | BDE | BDE unit names (corpus) |
| 97 | `#remove SessionName` | BDE | TSession / TDatabase / TTable property (corpus) |
| 98 | `#remove PrivateDir` | BDE | TSession property (corpus) |
| 99 | `#remove DFM: Origin` | unsure | corpus; drops the BDE-format `Origin` value (`DBDEMOS.CUSTOMER.CUSTNO`) persisted on fields under a converted BDE dataset; the only block that `#link`s Origin is TAutoIncField (not-BDE, line 604) -- see Q3 |
| 110, 111, 114, 117, 122, 127, 129, 133 | `#remove AbortOnKeyViol`, `AbortOnProblem`, `ChangedTableName`, `Destination`, `KeyViolTableName`, `ProblemTableName`, `RecordCount`, `Transliterate` (8) | BDE | derived from the TBatchMove block's unmapped properties |
| 113, 121, 123, 124, 125, 130 | `#remove AutoSessionName`, `KeepConnections`, `NetFileDir`, `OnPassword`, `OnStartup`, `SQLHourGlass` (6) | BDE | derived from the TSession block |
| 112, 116, 120, 128, 131, 132 | `#remove AutoRefresh`, `DefaultIndex`, `IndexFiles`, `Ranged`, `StoreDefs`, `TableType` (6) | BDE | derived from the TTable block |
| 118 | `#remove HandleShared` | BDE | derived from the TDatabase block |
| 115, 126 | `#remove Constrained`, `ParamCheck` (2) | BDE | derived from the TQuery (and TStoredProc) blocks |
| 119 | `#remove HasConstraints` | not-BDE | derived ONLY from the TAutoIncField block (`#ignore HasConstraints`, line 627); travels with that block |
| 140-143 | `#mapping BdeTransIsolation` (4) | BDE | `Bde.DBTables.TTransIsolation`; `#apply`'d in the TDatabase block (184) |
| 145-150 | `#mapping BdeBatchMode` (7) | BDE | `Bde.DBTables.TBatchMode`; `#apply`'d in the TBatchMove block (634) |

Preamble totals: BDE 42 / not-BDE 1 / unsure 1.

### 1.2 `#convert` blocks (10)

| Header line | Block | Class | Reason |
|---|---|---|---|
| 156 | `Bde.DBTables.TSession -> TFDManager` | BDE | Bde.DBTables |
| 176 | `Bde.DBTables.TDatabase -> TFDConnection` | BDE | Bde.DBTables; consumes `#mapping BdeTransIsolation` |
| 217 | `Bde.DBTables.TTable -> TFDTable` | BDE | Bde.DBTables; `UpdateObject` needs TUpdateSQL in the same run (same book) |
| 337 | `Bde.DBTables.TQuery -> TFDQuery` | BDE | Bde.DBTables; same UpdateObject condition |
| 442 | `Bde.DBTables.TUpdateSQL -> TFDUpdateSQL` | BDE | Bde.DBTables; referenced by the three datasets' UpdateObject |
| 452 | `Bde.DBTables.TStoredProc -> TFDStoredProc` | BDE | Bde.DBTables |
| 556 | `Data.DB.TParam -> FireDAC.Stan.Param.TFDParam` | not-BDE | Data.DB; a Params item of ANY dataset; only right when the owning dataset becomes FireDAC |
| 568 | `Data.DB.TParams -> FireDAC.Stan.Param.TFDParams` | not-BDE | same |
| 580 | `Data.DB.TAutoIncField -> FireDAC.Comp.DataSet.TFDAutoIncField` | not-BDE | Data.DB; a persistent field of ANY dataset; only right under a FireDAC dataset |
| 629 | `Bde.DBTables.TBatchMove -> TFDBatchMove` | BDE | Bde.DBTables; consumes `#mapping BdeBatchMode` |

Block totals: BDE 7 / not-BDE 3 / unsure 0.

### 1.3 The 43 trailing `#migrate` lines (663-733)

| Lines | Line(s) | Class | Reason |
|---|---|---|---|
| 663-666 | `TUpdateKind -> TFDUpdateRequest`, `ukModify`, `ukInsert`, `ukDelete` (4) | unsure | `Data.DB.TUpdateKind` (library index); in BDE code only `OnUpdateRecord` handlers carry it, but TDataSetProvider / TClientDataSet handlers use the same type and would be broken by a unit-wide rename |
| 668-673 | `TUpdateAction -> TFDErrorAction`, `uaFail`, `uaAbort`, `uaSkip`, `uaRetry`, `uaApplied` (6) | unsure | `Data.DB.TUpdateAction`, same argument |
| 675-679 | `TDBScreenCursors -> TFDGUIxScreenCursor`, `dcrDefault`, `dcrHourGlass`, `dcrSQLWait`, `dcrOther` (5) | not-BDE | `Data.DB.TDBScreenCursor` (singular; the corpus line names a type that does not exist -- the enum values do) |
| 682 | `Session.* -> FDManager.*` (1) | BDE | the Bde.DBTables global `Session` |
| 683-692 | `IsAlias`, `AddAlias`, `DeleteAlias`, `ModifyAlias`, `GetAliasParams`, `GetAliasNames`, `FindDatabase`, `OpenDatabase`, `CloseDatabase`, `GetDatabaseNames` (10, member form) | BDE | `Bde.DBTables.TSession` methods |
| 693 | `TDatabase:Execute -> ExecSQL` (1, scoped) | BDE | Bde.DBTables.TDatabase |
| 697-700 | `TTransIsolation -> TFDTxIsolation`, `tiDirtyRead`, `tiReadCommitted`, `tiRepeatableRead` (4) | BDE | `Bde.DBTables.TTransIsolation` |
| 701 | `TransIsolation -> TxOptions.Isolation` (1, member form) | BDE | TDatabase property; the DFM side is already `#apply BdeTransIsolation` in the TDatabase block |
| 702-707 | `TBatchMode -> TFDBatchMoveMode`, `batAppend`, `batUpdate`, `batAppendUpdate`, `batDelete`, `batCopy` (6) | BDE | `Bde.DBTables.TBatchMode` |
| 711 | `UpdateRecordTypes -> FilterChanges` (1, member form) | BDE | `Bde.DBTables.TBDEDataSet.UpdateRecordTypes` (TTable / TQuery / TStoredProc) |
| 730 | `TBlobStream -> TFDBlobStream` | BDE | `Bde.DBTables.TBlobStream` |
| 731 | `EDBEngineError -> EFDDBEngineException` | BDE | Bde.DBTables |
| 732 | `TDBDataSet -> TFDRDBMSDataSet` | BDE | Bde.DBTables |
| 733 | `TBDEDataSet -> TFDRDBMSDataSet` | BDE | Bde.DBTables |

`#migrate` totals: BDE 28 / not-BDE 5 / unsure 10.

Grand total (97 items): BDE 77 / not-BDE 9 / unsure 11.

## 2. How the engine scopes book-wide lines (rule A checked)

| Kind | Engine scope | Evidence |
|---|---|---|
| `#unuse` / `#use` / `#useswap`, `#remove`, `#mapping` | FILE-scope. Each block runs "the file-scope rules before the first #convert, the block's own rules, and every #convert, #mapping and #note line of the book" | `DfmReemit.pas:1080-1087`; `Rules.pas:239` ("[0] is the region before the first #convert"); DSL doc line 29 |
| `#migrate` | BLOCK-scope only. A block is a header up to the next header or EOF (G5). "A file-scope #migrate (before the first #convert) is not a member migration and is left alone" | `Apply.pas:5137-5138`; contract G2(c) (silent, no item); measured on the `global` fixture (spec section 2) |

Consequences:

* **Rule A ("the BDE book keeps its book-wide lines above the first `#convert` header") is
  valid** for the 44 preamble lines -- that is exactly where the engine reads them.
* **For the 43 `#migrate` lines rule A is safe but inert.** Above the first header the engine
  applies NONE of them and reports nothing. Today they sit, for the engine, inside the
  TBatchMove block (G5): the 26 lines with unit tails / a `Class:` scope / a `*` wildcard are
  refused with a rule-level `migrate-check` ("uses units after a member #migrate are not
  added" / "a scoped #migrate ... is not applied yet" / "replacement templates are not applied
  yet"), and the 17 plain member-form lines could only rewrite member sites of a CONVERTED
  TBatchMove instance -- none of them names a TBatchMove member, so they rewrite nothing.
  Net effect of moving them up: identical rewrites (none), minus the migrate-check echo in
  the rare unit that converts a TBatchMove. The editor side gains an unambiguous model
  (preamble = file-scope) and the `rbkTrailing` special case can be retired, as the owner
  said.
* Only two of the 43 could ever become engine ACTION, by moving INTO their owning block:
  `TransIsolation -> TxOptions.Isolation` (TDatabase block, PAS sites of converted TDatabase
  instances) and `UpdateRecordTypes -> FilterChanges` (TTable, TQuery, TStoredProc blocks).
  The 10 `Session.*` method lines are reached through the global `Session` variable, not a
  converted instance, so no block can carry them today. This re-homing is step 6, optional,
  separately verified (the TransIsolation case may be refused as "book line K already converts
  TransIsolation" because of `#apply BdeTransIsolation` -- the dry run decides).
* **Book-2 needs no book-wide lines of its own**, with one exception: `#remove HasConstraints`
  is derived only from the TAutoIncField block and moves with it. Its `#convert` headers
  carry their own To-units (`FireDAC.Stan.Param`, `FireDAC.Comp.DataSet`); no `#unuse` is
  needed because `Data.DB` stays in `uses` (every field class still needs it). `#remove DFM:
  Origin` is Q3. The 15 Data.DB `#migrate` lines (if they move) go above Book-2's first
  header -- inert there, exactly as in the BDE book.
* Editor model today: `ConvRules.BlockFile` splits the closing run of file-scope directives
  into `rbkTrailing` precisely because of these 43 lines (`BlockFile.pas:158-163`, FILE_SCOPE
  const comment 441-444). After the move the comments go stale and the `rbkTrailing` path has
  no producer in the shipped books (keep the code; a book from elsewhere may still end in
  file-scope lines) -- update the comments in the same commit.

## 3. Cross-book dependencies and run order

Checked against the engine's single-pass semantics (chain1 note: rules match the ORIGINAL
source; an output is never re-matched; uses swaps "ADD wins"; `#migrate` sites are collected
once).

| Kind | Found? | Detail |
|---|---|---|
| Type chain (`#convert X -> Y` in one book, `#convert Y -> Z` in the other) | NO | every To is a `FireDAC.*` class; no From is a FireDAC class. No two headers share a From either. |
| Uses chain (`#unuse` / `#use` of the same unit across books) | NO | the BDE book removes `BDE*` units; Book-2 only adds `FireDAC.Stan.Param` / `FireDAC.Comp.DataSet` through its headers |
| `#mapping` declared in one book, `#apply`'d in the other | NO | both mappings and both `#apply` lines are BDE (TDatabase, TBatchMove) |
| `#check-ref ConnectionName TDatabase.DatabaseName, TFDConnection.ConnectionName` (TTable 223, TQuery 343, TStoredProc 458) | same book | a cross-BLOCK reference check inside the BDE book; untouched |
| `UpdateObject` same-run condition (TTable 304, TQuery, TStoredProc -> TUpdateSQL) | same book | all four blocks are BDE; the condition is unchanged |
| CONTAINMENT (not a chain): Book-2's instances are persistent fields / Params items INSIDE the datasets the BDE book converts | YES | mechanically order-free (each book matches the original class); semantically the intermediate state after Book-2-first is a FireDAC field under a BDE dataset (form does not load), after BDE-first a Data.DB field under a FireDAC dataset (loads). |
| `#remove DFM: Origin` (BDE book) vs `#link Origin <- Origin` + the "COMPLEMENTARY" note (Book-2, 604-615) | cross-book NOTE | the Book-2 note must say "the BDE book's `#remove DFM: Origin`"; whether the BDE run already strips Origin on CHILD fields of a converted dataset is measured in step 4 (decides Q3) |

**Run order: the BDE book first, then Book-2, with a reindex between** (convert-apply
reindexes by default; the editor's book-major loop `RunConversionBatched` runs `ABooks` in
the given order and emits `rpReindexAfter` per book chunk, `ConvertRunner.pas:346-383`). Both
books in ONE editor job, in that order, on the SAME unit set. Lane chain1's warning is not
triggered (no chain); a containment dependency is a different class of warning and is out of
chain1's scope -- say so to that lane, do not widen CHAIN-1.

## 4. Split steps (one commit each; nothing here is done yet)

1. **Fixture + baseline first** (section 5 steps 1-2) -- the single-book dry-run JSON is the
   oracle every later step is compared against. No book edit before `base.json` exists.
2. **Create `convrules\DataDB-to-FireDAC.rules`** (name: Q5). Header comment: origin (split
   from BDE-to-FireDAC.rules on <date>, D2), the containment rule ("run AFTER
   BDE-to-FireDAC.rules on the same units"), 7-bit ASCII CRLF. Body, moved VERBATIM in this
   order: `#remove HasConstraints` (119); the 15 Data.DB `#migrate` lines (663-679, Q2 may keep
   10 of them in the BDE book) with their section comment; then blocks TParam (556-566),
   TParams (568-578), TAutoIncField (580-627). Fix the one cross-book note (section 3, Origin).
3. **Edit `convrules\BDE-to-FireDAC.rules`**: delete the moved lines; move the remaining 28
   (or 38) `#migrate` lines with their section-4 comments to a new section between section 2
   (`#mapping`) and section 3 (first `#convert`, line 156) -- rule A; fix the header comment
   paragraphs that describe section 4 "at the bottom" and the "three Data.DB blocks"; update
   the counts in the editor comments `BlockFile.pas:160` and `441-444` (DSL doc line 29 stays
   true). Every other byte of both books is unchanged -- verify with a diff that shows only
   moves (`git diff --color-moved=plain`).
4. **Per-book dry runs and the comparison** (section 5 steps 3-4) must be equal to the baseline
   before anything else is touched.
5. **Model tests + battery**: `tests\ConvRulesModelTests.exe` (expect 2950 / 0 / 20 without an
   engine, 3068 / 0 / 0 on the pin) -- the `tests\fixtures\validate\BDE-to-FireDAC.rules` copy
   pins the PRE-split shape and is not touched (Q7); the six engine autotests that name the
   book (`run_convert_lazy_paths.ps1` uses it as its default `$Book`; the other five only in
   comments) stay green because the BDE file name is kept.
6. **Optional, separate commit, Q4b**: re-home `TransIsolation -> TxOptions.Isolation` into the
   TDatabase block and `UpdateRecordTypes -> FilterChanges` into TTable / TQuery / TStoredProc,
   then a dry run that must show NEW `migrate-applied` edits (or a `migrate-check` refusal,
   which is then recorded as the reason to leave them where they were).
7. Docs: `docs\converter\convrules-dsl.md` (mention two shipped books and the order),
   `docs\CONVERTER-BACKLOG.md` D2 -> done, the convrules-editor wiki page for the Convert tab
   (two books in one job) if it names the book; `featuregen` entry only if a registered
   surface changes (none expected; the books are data).

## 5. Verification -- a convert-apply dry run per book against the single-book result

Rules: never on a real project; engine = a COPY of the pin
`third_party\engine-pinned\1.35.1-alpha-20261026-134311` in the lane scratch
(`C:\TEMP\claude\lanes\1027conv\agent-d2\engine\`); always pass `--db` explicitly (a no-`--db`
run can write a real project DB); no `--apply` = plan only, no file is written.

1. **Fixture** `tests\autotest\fixtures\bdesplit\` (new): `BdeSplit.dpr`, `BdeSplitForm.pas` /
   `.dfm` (ASCII, CRLF). The form carries one instance of every From class of both books and
   every property the trailer could touch: `Session1: TSession` (AutoSessionName, SQLHourGlass),
   `Database1: TDatabase` (DatabaseName 'DBDEMOS', TransIsolation = tiReadCommitted,
   HandleShared, KeepConnection), `Table1: TTable` (DatabaseName, TableName 'customer.db',
   IndexName, UpdateObject = UpdateSQL1, persistent fields `Table1CustNo: TAutoIncField` with
   `Origin = 'DBDEMOS.customer.CustNo'` and `Table1Company: TStringField` with an Origin),
   `Query1: TQuery` (Params with two items, UpdateObject = UpdateSQL1, an `OnUpdateRecord`
   handler whose signature uses `TUpdateKind` / `TUpdateAction`), `StoredProc1: TStoredProc`
   (Params), `UpdateSQL1: TUpdateSQL`, `BatchMove1: TBatchMove` (Mode = batAppendUpdate, Source
   = Table1, Destination, Mappings). Code sites: `Session.FindDatabase`, `Database1.TransIsolation
   := tiDirtyRead`, `Table1.UpdateRecordTypes := [rtModified]`, a `TDBScreenCursor` local, an
   `except on E: EDBEngineError`, a `TBlobStream.Create`, `Database1.Execute('...')`.
   Index it: `drag-lint index --project tests\autotest\fixtures\bdesplit\BdeSplit.dproj --db
   <scratch>\bdesplit.sqlite` (a `.dproj` is needed; copy the shape of an existing fixture
   project in `tests\autotest\fixtures\`).
2. **Baseline, before any book edit**: `drag-lint convert-apply --unit <fixture>\BdeSplitForm.pas
   --rules convrules\BDE-to-FireDAC.rules --db <scratch>\bdesplit.sqlite --db
   C:\Projects\.drag-lint\library-Win64.sqlite --no-reindex --json > base.json`. Also capture it
   with `--no-warn-unlinked` off (default) so the unlinked NEAR-MISS warnings are in the oracle.
3. **After the split**: the same call with `--rules convrules\BDE-to-FireDAC.rules` -> `bde.json`,
   then with `--rules convrules\DataDB-to-FireDAC.rules` -> `book2.json` (same original fixture;
   the dry run writes nothing, so the second run sees the original bytes, which is what the
   real BDE-first order would give for Book-2's From classes anyway).
4. **Compare** with a new guard `tests\autotest\run_convert_book_split.ps1`: the multiset of
   planned edits / items (key: `kind`, `instance`, `path`, `value`, `old_value`, `file`, `line`;
   `rule_line` and `text` excluded because book line numbers move) of `bde.json` UNION
   `book2.json` equals `base.json`'s, and the `warnings[]` / `todos[]` / `access_sites[]`
   unions are equal AFTER removing the expected differences, which the guard names explicitly:
   the rule-level `migrate-check` texts that today come from the TBatchMove block (26 lines)
   and vanish once the lines are above the first header. **Positive control**: a scratch copy of
   the BDE book with one `#link` deleted must make the comparison FAIL; a copy of Book-2 with
   the TAutoIncField header's To-unit dropped must FAIL (the guard must be able to go red).
   Read `--json` with the real field names (`start_line` style traps: inspect the raw shape
   first, map, then assert).
5. **Order check**: a convert-apply of Book-2 on a fixture copy already converted by the BDE
   book (run the BDE book WITH `--apply` on a scratch COPY of the fixture, reindex that copy,
   then the Book-2 dry run) plans exactly the edits `book2.json` planned on the original --
   proves the containment order BDE -> Book-2 needs no chaining.
6. **Editor**: open both books in ConvRulesEditor launched from the pin copy (Save round-trips
   byte for byte; `BookPlaces` / Work list show the moved `#migrate` lines as file-scope); a
   `drive-convert-tab.ps1`-style job with `ABooks = [BDE, Book-2]` is a follow-up driver, not a
   gate for this split.
7. Model tests and the battery as in section 4 step 5; `run_encoding_guard.ps1` on both books.

## 6. Owner questions (with the recommendation)

| # | Question | Options | Recommendation |
|---|---|---|---|
| Q1 | What goes into Book-2? | (a) the Data.DB-declared rules: 3 blocks + 5-15 `#migrate` lines + `#remove HasConstraints`; (b) nothing -- every rule here exists only for the BDE conversion, so keep ONE book and only move the trailer up | (a). It is the one mechanical criterion, and it isolates the three conversions that are WRONG on a non-BDE dataset (a TClientDataSet's TAutoIncField or Params) so they can be run on a chosen unit set. If the owner's "unrelated to BDE" meant something else, say which rule and the table is re-cut. |
| Q2 | The 10 unsure lines (`TUpdateKind` x4, `TUpdateAction` x6) | BDE book (only BDE handlers use them in this code base) or Book-2 (Data.DB-declared; a unit-wide rename would break provider / ClientDataSet handlers) | Book-2, with the Data.DB group. They are inert type renames either way; the declaring unit keeps the rule explainable. |
| Q3 | `#remove DFM: Origin` | keep in the BDE book only; copy into Book-2; move to Book-2 | keep in the BDE book; after step 5.4, if the BDE dry run does NOT drop `Origin` on the child fields of a converted dataset, also copy it into Book-2 (a `#remove DFM:` twice is harmless). |
| Q4a | Where do the BDE `#migrate` lines go? | rule A (above the first header: engine-inert as today, editor file-scope, `rbkTrailing` retired) or leave the trailer as it is | rule A. Nothing the engine does changes (section 2), and the editor/engine disagreement about who owns the tail ends. |
| Q4b | Re-home the two member-form lines that have an owning block (`TransIsolation`, `UpdateRecordTypes`)? | yes, as step 4.6 with its own dry run; no | yes, as a separate commit after the split is green -- it is the only way any of the 43 lines ever becomes an engine action. |
| Q5 | File names | keep `BDE-to-FireDAC.rules` + new `DataDB-to-FireDAC.rules`; or rename both | keep the BDE name (six engine autotests and the docs name it; `run_convert_lazy_paths.ps1` loads it) and add `DataDB-to-FireDAC.rules`. |
| Q6 | Run scope of Book-2 | same units as the BDE run, in the same editor job, second; or a separate job later | same job, second. The book-major loop already does it; a job that lists Book-2 FIRST should get a validation warning ("Book-2 before the BDE book") -- a small `ValidateScope` rule, not CHAIN-1. |
| Q7 | `src\tools\convrules-editor\tests\fixtures\validate\BDE-to-FireDAC.rules` (38 KB copy used by `convlib.bde2fd.*`) | leave (pins the pre-split shape) or split it in lockstep | leave; add one model test that loads the shipped Book-2 and asserts its 3 headers + `#remove HasConstraints` + no `#apply` without a `#mapping`. |

## 7. Incidental facts worth a line elsewhere

* The corpus line `#migrate TDBScreenCursors -> TFDGUIxScreenCursor, FireDAC.UI.Intf` names a
  type that does not exist: `Data.DB` declares `TDBScreenCursor` (singular). Vendor typo, carried
  verbatim; it can never match.
* `docs\INBOX-engine-to-converter-chain1.md` cites `src\convert\DRagLint.Convert.Apply.pas`;
  the unit lives in `src\report\` (no `src\convert` folder exists). Line numbers were right.
* The project index `src\cli\_D-RAG\drag-lint.sqlite` reports "8 of 228 files changed" and
  the editor index "11 of 36" -- both answered this plan's questions, but reindex before any
  lint on those projects.
