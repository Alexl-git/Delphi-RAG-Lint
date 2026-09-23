<!-- dl:backlog status=open last-measured=2026-09-23 -->
# PLAN: the last four diagram questions (exception-paths, consumers, feeds-from, lands-where)

For a COLD session. Work ONLY under `charts\`. Twenty-one questions ship and are
the reference implementations; `charts\src\Test-Emitters.ps1` is the gate and
is GREEN on the 1.18 clones (commit `d009f409`; `A-AR1` now 563 / 2859 / 293 /
30716 -- the EUREKALOG block is live). Build-order step 0 is DONE.

`compare` is EXCLUDED by the owner. This plan covers the other four.

**Every number below was MEASURED on 2026-09-23 between 10:28 and 10:45
against the CLONES named below (indexed 10:11, COPIED ~10:30) after the
engine's full 1.18.0 re-parse (`v=1.18.0-alpha` / `r=1.6.0-alpha`).** They are
the post-re-parse BASELINE; nothing here needs a "re-measure" flag. Do not
re-derive them -- compare against them. A number that does not match is a
FINDING: investigate before "fixing" the number.

```
$E     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe'
$DOT   = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe'
$SRC   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\src'
$CLI   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\scratch\db\CLIENT-Micronite2027.sqlite'
$SRV   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\scratch\db\SERVER-MicroniteMW1Service.sqlite'
$DL    = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\scratch\db\DL-drag-lint.sqlite'
$SQL   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\scratch\db\SQL-drag-lint-sql.sqlite'
```

The `*.sqlite.pre-1.18` and `*.pre-reindex-0530` copies beside them are
history -- do not point anything at them.

## >>> READ THIS FIRST: three engine rulings that shape this plan <<<

1. **No `fb-snapshot` this cycle.** `orm_links` / `fb_*` stay at 0 rows (measured
   0 on all three project clones after the re-clone). The owner decides later.
   So the ONE shipping design for `consumers` / `feeds-from` / `lands-where` is
   **path A -- derived** (DFM bindings + Delphi SQL literals + the SQL-script
   index), every derived hop labelled `[inferred]`. Path B (`orm_links`) is a
   short "when it arrives" switch in section 7, not a design.
2. **The full re-parse is DONE for the project DBs and the clones are current.**
   `$SQL` was already at v=1.18 and is final. **The LIBRARY DBs are still being
   written -- keep avoiding them** (they are on the STOP list anyway).
3. **Do NOT run `drag-lint index` / `fb-snapshot` / `autodoc` on ANY database.**
   Reads are proven safe; only `index` re-resolves. `Get-CloneDb` refuses a
   non-clone path in every emitter -- keep it that way.

---

## 1. THE PREMISES -- every one measured, none assumed

Three batches in a row found wrong premises in fully-measured plans. Attack
column and verb SEMANTICS, not existence. Queries run through
`drag-lint sql --db <clone> --query ... --format json` unless stated; population
queries were PAGED past the silent 200-row cap.

### 1a. exception-paths (`$CLI` unless stated)

| # | premise | evidence | verdict |
|---|---|---|---|
| P1 | `refs.kind` has no raise/handle value | INBOX note, re-confirmed on the 1.18 clone: kinds are read / type_use / call / member-access / write / event-binding / attribute / di-* | CONFIRMED |
| P2 | **`refs.kind` ALREADY SPLITS raise from handler.** A `raise X.Create(...)` emits `kind='read'` on `X` (the class is an expression); an `on E: X do` emits `kind='type_use'` (a type annotation) | 430 candidate refs (`E[A-Z]..[a-z]` or `Exception`): read 171 / type_use 242 / call 8 / member-access 7 / write 2. Classified from the SOURCE token before each ref: **read -> raise 168** (the other 3 reads are `EOPart`/`EWclassconv`, non-exceptions -- P5); **type_use -> handle 185**, var-or-param decl 30, `class(` 17, `is` 8, `as` 2; call -> cast 8; member-access -> cast 4 + 3 `is`-tests whose qualifier holds an inline `{$IFDEF USE_NAMESPACES}System.SysUtils{$ELSE}SysUtils{$ENDIF}.` (`EExtraExceptionInfo.pas:235/250/274`). **Zero cross-over**: no read is a handler, no type_use is a raise | CONFIRMED -- the INBOX claim "produced identically" is WRONG in kind: the kinds differ, only the type_use bucket is mixed |
| P3 | the type_use bucket needs the source token to separate handler from declaration | 185 handle vs 30 decl vs 17 class-decl vs 8 `is` vs 2 `as` -- all `type_use` | CONFIRMED |
| P4 | **every candidate ref is UNBOUND** (`symbol_id IS NULL`), even for project-declared classes like `EMicroniteError` (declared `CommonExceptions.pas:23`) | CLIENT 430/430 unbound; SERVER 2,835/2,835; DL 161/161 | CONFIRMED -- so "filter by target kind" is impossible; filter by NAME against declarations instead |
| P5 | a name regex (`E` + capital) is a safe candidate filter | **WRONG.** CLIENT: `EOPart` (local_var, 3 rows), `EWclassconv` (const, 2), `EVentTimer` (a non-exception class, 10 decls), `ET` (local_var x9). SERVER: **`ERollback` 798 rows** -- it is the VARIABLE in `on ERollback: Exception do`. DL: `ELine`/`ECol`/`EKey`/`EIt`/`EIn2`/`EOk`/`EPath`/`EOut2` are all locals | WRONG -- see design: SYNTAX FIRST, name second |
| P6 | the index MISSES raises (a source scan finds more) | source `raise` keyword: 192 in the pas closure (178 `X.Create`, 12 bare `raise;`, 1 `raise E`, 1 `then raise`). 19 `X.Create` lines have NO raise-ref: 1 regex miss (`EdxException`, uStyles.pas:965 -- it HAS a read ref), **7 inside `{ ... }` block comments** (GLBLOAD.PAS 182-365 sit in a `{` opened at :175; iINSPRSLT:1722; MStreams:1481), **11 inside `{$IFDEF M2022_REFERENCE}`** (uJobList.pas 1085-1321 and 1402-1685; the symbol is never defined, and the index has NO routine spanning those lines) | WRONG -- **the index is right and a naive source scan is wrong.** Refs are the anchor; source text is read only AROUND a ref |
| P7 | `type_ancestors` gives the full exception chain | 17 `E*` classes, 17 with an ancestor row -- but rows carry ONLY ordinal 0 (direct parent): `EDataError -> EMicroniteError (class)`, `EMicroniteError -> Exception (kind '?')`, `EKeyViolation -> EDatabaseError ('?')` | OVERSTATED -- chain by walking; an external ancestor ends the walk with kind `?` |
| P8 | `on E: Exception` is the dominant handler | handler types: **Exception 169 of 185**, EZeroDivide 5, EConvertError 3, EOverflow 3, EDatabaseError 2, EInvalidCast / EOcrNotConfigured / EPrinter 1 each. Raise types: Exception 78, EDatabaseError 19, EDataError 11, EFileError 11, EMicroniteMessage 10, EValidationError 6, ... 22 distinct | CONFIRMED -- handler matching is mostly catch-all; the typed 16 are where ancestry matters |
| P9 | bare `except` (no `on`) and bare `raise;` have NO ref at all | by construction (no identifier). Source counts inside the 11,007 INDEXED impl spans, comment-stripped (line-preserving regex): **bare `except` 86 blocks in 56 routines**, `except` + `on` 180 blocks, **`raise;` 12**, **`raise <var>` 2**, `raise X.Create` 180 (vs 168 ref-classified -- the 12 extra are raises of types OUTSIDE the name filter, e.g. `EdxException`), `finally` 959; 154 routines have any `except`, 135 any `raise` | CONFIRMED -- these rows can only be `[inferred]` from a source scan bounded to an INDEXED impl span. And the 180-vs-168 gap is why the per-focus classifier scans ALL refs in the span, not the name-filtered ones (section 4) |
| P10 | `refs.start_col` is 1-based; `end_col` is exclusive | `EMicroniteError` at col 13, `IndexOf` = 12, `end_col` 22 = 13 + 9 | CONFIRMED |
| P11 | the clone's source on disk is what was indexed | sha256 of `files.sha256` vs disk, first 200 files: **CLIENT 199 same / 1 differs (`uMain.ViewModel.pas`)**, SERVER 200/200, DL 129 same / 1 differs (`TreeSitterLib.pas`). On the PRE-1.18 DL clone it was 18 of 128 and the classifier then read lines that no longer contained the ref's name (38 `type_use` rows with text like `threshold, so while the clocks are on summer time`) | OVERSTATED -- the emitter MUST compare sha256 before reading a line by column, and mark a mismatched file `[stale source]` rather than classify it. The re-clone shrank the exposure; it did not remove the mechanism |
| P12 | `refs.enclosing_symbol_id` names the routine for every raise/handle | 29 of 430 refs have NULL enclosing -- the 17 `class(` declarations and interface-section param decls, i.e. exactly the non-routine rows | CONFIRMED for raise/handle rows |
| P13 | callers are intact (the direction exception-paths walks UP) | `PersistScanToDB` -> d1 `AutoScanIfNeeded` -> d2 `ForceRescan` -> d3 none; `LoadInspectionNames` (7 raises) has **0 resolved callers**; `CopyRecords` 0; `Configure_ComPort` 0; `RunAutoTest` 0 | CONFIRMED but THIN -- 4 of 5 focus candidates have no caller at all (interface dispatch / event handlers). The chart must say "no resolved caller", never "handled nowhere" |

### 1b. consumers (`$SQL` final; `$SRV` / `$CLI` re-cloned)

| # | premise | evidence | verdict |
|---|---|---|---|
| P14 | the SQL index holds tables / columns / triggers / procs | symbols: sql_table **252**, sql_column **3,820**, sql_trigger **183**, sql_procedure **168**, sql_view 1, sql_index 26, sql_domain 104, sql_generator 73, sql_exception 4 | CONFIRMED |
| P15 | **252 tables is 252 tables** | **WRONG: 135 distinct names.** 117 names are declared MORE THAN ONCE across the 12 scripts (`MS2_OLDER_BCK.SQL` is history). sql_procedure 168 -> 90 distinct; sql_column 3,820 -> 1,323 distinct names; triggers 183/183 distinct. **This plan's own first pass fell into it**: counting a column's tables by ROW said `ID` is in 149 tables; by distinct NAME it is 77 (P34) | WRONG -- collapse on NAME, and say how many declarations were collapsed |
| P16 | the SQL index is the live schema | **Live Firebird, VALIDATION ONLY** (MCP, read-only, `C:\Projects\DB\SQL\MICRONITEV6A.FDB`): 139 tables / 1 view / 183 triggers / 91 procs / 2,349 columns / 4 `FIB$` tables. Index-only: `OPERATION` (dropped). **Live-only: `PDF_SCAN`, `PDF_SCAN_CHUNK`, `PDF_SCAN_ITEM`, `PDF_BALLOON`, `PDF_SCAN_REGION`** (5 tables never scripted) | OVERSTATED -- the chart must carry "script-derived: 135 names; 5 live tables absent from the scripts (as of 2026-09-23)". Emitters cannot reach the live DB; this is a human validation line, not a runtime check |
| P17 | `refs` in `$SQL` are column/table uses inside proc and trigger bodies | **WRONG.** 209 `sql_table_ref` rows, ALL unbound, ALL with NULL enclosing, ALL on a DECLARATION line: 183 = `CREATE TRIGGER x FOR <T>`, 26 = `CREATE INDEX ... ON <T>`. 209/209 name a known table. **Zero refs inside any body** | WRONG -- body facts do not exist in the index |
| P18 | trigger / proc symbols carry a body span | `start_line == end_line` on every one of the 351 | WRONG -- bodies must be read from the `.SQL` source |
| P19 | trigger bodies are scannable from source | scanning from `start_line` to the next line that is exactly `^`: **183/183 bodies found** (avg 9 lines, max 85); 177/183 `FOR <known table>`; **183/183 mention `NEW.<col>` or `OLD.<col>`**; 4 also name ANOTHER table after FROM/JOIN/INTO/UPDATE | CONFIRMED |
| P20 | proc bodies are scannable the same way | **only 1 of 168** terminates with a bare `^` line within 400 lines -- MS1 (89) and MS5 (77) use a different terminator layout (`SET TERM` 4x each) | WRONG as written -- needs a `SET TERM`-aware scanner; budget it, and if it does not converge, procs render as name-only rows `[body not scanned]` |
| P21 | SERVER `sql_reads` / `sql_writes` facts are the table-level truth | facts: 19 reads / 148 writes / 442 touches over 8,923 rows; 157 symbols with either; 130 distinct table tokens, **129 match a `$SQL` table** (the 1 miss is `FIB` -- `FIB$FIELDS_INFO` truncated at `$`); **129 of the 135 distinct tables have >=1 SERVER method with a fact** | CONFIRMED for WRITES |
| P22 | ... and for READS | **WRONG in degree.** `sql_reads` names **14** distinct tables; uppercase SQL literals name **133** after `FROM`/`JOIN`. `TDataService_CAUSFAIL_SERVER.PrepareLoadQuery` builds `SQL.Add('SELECT ...'); SQL.Add('FROM CAUSFAIL')` (`uCAUSFAIL_SERVER.PAS:108-111`) and has **no fact at all**; the 19 read facts are all in `uPipeSessionBuilder` / `uOPTRLIST_SERVER` / `uGenericTableRoute` / `uOptrlistRoleSync`. So a reads chart built on the fact alone shows 14 tables where 133 are read | WRONG -- reads come from LITERALS `[inferred]`; the fact is a `[certain]` subset. **File this to the engine** (an INBOX note, not written by this session -- section 10) |
| P23 | a literal that names a table IS a SQL use | 782 uppercase-verb literals on SERVER; `Cannot Load from CAUSFAIL` and `TLogContext.ForDB('CAUSFAIL', ...)` also contain the name. 9 uppercase-verb literals name no table (`SELECT DISTINCT P FROM (`, `IS NOT DISTINCT FROM ta.OPERID`). Non-table tokens after FROM: `RDB$DATABASE`, `RDB$RELATION_FIELDS`, `RDB$USER_PRIVILEGES`, `FIB$RESYNC_GENERATORS`, `OR`, `SERIAL`, `TRUE`, `USER` | OVERSTATED -- require an UPPERCASE verb immediately before the name (`FROM T`, `JOIN T`, `INTO T`, `UPDATE T`, `DELETE FROM T`, `EXECUTE PROCEDURE P`), word-bounded, and the name in the collapsed table set |
| P24 | column-level consumers resolve from the same literals | `CAUSFAIL.REASON` -> 2 routines (PrepareLoadQuery, PrepareSaveQuery); `FOLDERS.PARTNMBR` -> 2; `DRA1.FLDRID` -> 3 (+`HandleCopyOperation`). Column coverage inside literals of fact-bearing routines: CAUSFAIL 4/4, FOLDERS 79 of 126 index columns (126 includes a historical duplicate; live has 79), DRA1 13/22 | CONFIRMED, PARTIAL -- `Fields[1].AsString` positional reads are invisible; say so |
| P25 | CLIENT has SQL facts / SQL text | 0 `sql_reads`, 0 `sql_writes`, 38 `touches`; **0 DFM SQL properties** (no `SQL.Strings`, no `TFDQuery`); 239 pas literals equal a table name over 56 distinct tables (23 of them `const`, e.g. `CAUSFAIL_TABLE = 'CAUSFAIL'` at `uCausFail.ViewModel.pas:37`) | CONFIRMED -- CLIENT consumers are `[inferred]` from table-name literals + DFM bindings only |
| P26 | shown-where's index-wide "459 columns" | `COUNT(DISTINCT text)` is case-sensitive; UPPER-folded it is **424** | OVERSTATED (cosmetic, another chart's number; noted, not in scope) |

### 1c. feeds-from (`$CLI`)

| # | premise | evidence | verdict |
|---|---|---|---|
| P27 | controls bind to a datasource in the DFM | 209 rows: `DataBinding.DataSource` 121, `DataController.DataSource` 59, `DataSource` 29 (+ `ListSource` 5, `Properties.ListSource` 4 -- lookup lists, a DIFFERENT binding) | CONFIRMED |
| P28 | the datasource name resolves to a `TDataSource` component | 144 rows are same-form (38 distinct names). **65 rows carry a data-module prefix that exists NOWHERE**: `dmlSystem2.dsrFolder` 29, `Blueprint4_Model.*` 27, `ControlPlan_Model.*` 9 -- no DFM root, no `var`, no symbol anywhere under `C:\Projects\DB\ORM3`. A name-only lookup "resolves" 196/209 because `dsrFtrs` exists in THREE other forms -- that is a COLLISION, not a resolution | OVERSTATED -- resolve SAME FILE only (144); the 65 are DANGLING designer references; 21 of the 65 are re-pointed in code (`X.DataBinding.DataSource :=`, 76 member-access rows over 22 receivers) |
| P29 | `receiver_text` names the control on those re-pointing rows | `Blueprint4.pas:1015` has `edtF1.DataBinding`; `:1019-1045` have **`.DataBinding`** with the control lost -- multi-line / `with`-style statements | OVERSTATED -- an index quirk to disclose, not to paper over |
| P30 | the datasource gets its dataset in the DFM | **5 of 54** via a DFM `DataSet` prop (`tblCompTree`, `tblLookups`, `TBL` x2, `dmlSystemLookup.tblParList`); **51 of 54 in CODE** (`.DataSet` member-access: 246 rows, `X.DataSet := RHS` assignments over 35 distinct RHS) | CONFIRMED, INVERTED from the catalogue's assumption |
| P31 | the RHS is a memtable with a known type | RHS tails: `FMemTable` (field, TFDMemTable) 28, `MemTable` (property) 25, `AMT` (param) 16, `AMemTable` 7, `FMTFtrs` 5, ... -- all `TFDMemTable` | CONFIRMED |
| P32 | the memtable's TABLE is derivable | chain per datasource (up to 8 code sites scanned each): 54 -> 51 with a code site -> 49 with an assignment -> 48 RHS root has a declared type in the index -> **22 resolve to exactly ONE table-name literal in the view-model unit** (`dsrCausFail -> TCausFailViewModel -> CAUSFAIL`), **17 to MANY** (multi-table VMs: `TAssignGroupsViewModel` 7 candidates, `TMachineListViewModel` 4), **9 to NONE** (6 through an INTERFACE-typed VM whose unit has no literal; `TDataChannelsViewModel`, `TLookupListViewModel`) | CONFIRMED at 41% exact -- the rest need P33 or stay `[unresolved]` |
| P33 | bound column names disambiguate a multi-table VM | test "candidate table contains EVERY column bound through this datasource": `dsrGroups -> TOOLGR12`, `dsrAssigned -> TOOLASSG`, `dsrMachPos -> MACHPOS`, `dsrToolGr12 -> TOOLGR12`, `dsrMachines -> MACHINES` (**5 resolve to exactly one**), `dsrPList` **stays 3-way** (SERID/SERREAD/SERPART all hold the 2 bound columns), `dsrStations`/`dsrPlant`/`dsrDepartment`/`dsrOperat`/`dsrMachTyp`/`dsrOPeration` have **ZERO bound columns** (lookup `ListSource` users, grids with no `FieldName`) | CONFIRMED as a tie-break, `[inferred]` |
| P34 | column name alone finds the table | 424 distinct bound names vs `$SQL` columns collapsed by TABLE NAME: **210 exactly one table / 171 MANY / 43 none**; by row 393 / 435 / 75. `ID` is in 77 tables, `FLDRID` 33, `OPERID` 30. (This plan's first pass said 35 / 346 / 43 and `ID` in 149 -- it counted duplicate script declarations as separate tables, the P15 trap) | WRONG on its own for 171 names / 435 rows -- the table must come from the datasource chain, the column only checks membership |

### 1d. lands-where (`$CLI` + `$SRV` + `$SQL`)

| # | premise | evidence | verdict |
|---|---|---|---|
| P35 | the ORM object property IS the column, by name | `Tmc*` properties: **2,063**; 1,997 sit on a class named after a table (`TmcCAUSFAIL`); **1,991 of those are a column of that table (99.7%)**; 6 are not (`DistHist`, `DistHistLim`, `f_tb`, `GRIDS`, `MENUS`, `TABLE`). Reverse: CAUSFAIL 4/4 columns have a property, FOLDERS 79/79 | CONFIRMED -- the strongest fact in this whole plan, and it is a NAMING CONVENTION, so it renders `[inferred]` with the count that backs it |
| P36 | one server DataService per table | 134 `Imc*` interfaces, 129 named after a table (misses: `ImcFIB_DATASETS_INFO`, `ImcFIB_ENUMVALUES`, `ImcFIB_ERROR_MESSAGES`, `ImcFIB_FIELDS_INFO` -- `$` became `_` -- and `ImcMEMCONTROLPLANNINGPRESETS`); **133 `TDataService_<T>_SERVER` classes** | CONFIRMED |
| P37 | the server ties property -> param -> column | `ParamByName('X')` literals: 390; 189 inside a `TDataService_<T>_SERVER` routine; **182 of those are a column of T**; 7 are not (the `FIB$` naming again, `FOLDERCOUNT.TABLE`). `Obj.<PROP>` member-accesses inside `Save`/`Load`: **5,013 rows / 1,320 members / 133 classes** | CONFIRMED -- anchors exist for the write side |
| P38 | a DFM `FieldName` is also a "field" the reader will select | 903 binding rows; 34 persistent `TField` components (TIntegerField 15, TStringField 10, TLargeintField 6, TBooleanField 2, TFloatField 1) | CONFIRMED -- a second selection kind, resolved through the feeds-from chain (P32/P33), so it inherits that chain's 41% + tie-break coverage |
| P39 | triggers touching the column are findable | P19: 183/183 bodies mention `NEW.`/`OLD.` columns; `CAUSFAIL`: `CAUSFAIL_BIU5` (MS5.SQL:15) touches REASON, SEVERITY, SYSTID; `CAUSFAIL_BIU0` (MS6.SQL:34) ID; `CAUSFAIL_BUD0` (MS6.SQL:44) SYSTID | CONFIRMED |

### Measured table sizes on the re-cloned clones

| | CLIENT | SERVER | DL | SQL |
|---|---|---|---|---|
| symbols | 57,119 | 37,919 | 23,361 | 4,631 |
| files (pas) | 625 (563) | 471 (460) | 130 (129) | 12 (firebird-sql) |
| refs | 266,417 | 237,173 | 186,522 | 209 |
| string_literals dfm-prop | 39,277 | 2,284 | 0 | 0 |
| symbol_facts rows / sql_reads / sql_writes / touches | 11,007 / 0 / 0 / 38 | 8,923 / 19 / 148 / 442 | 2,953 / 92 / 27 / 332 | 0 |
| orm_links, fb_datasets, fb_columns, fb_relations | 0 | 0 | 0 | 0 |

---

## 2. RED TEAM -- attacking the premises above

**R1. "read = raise" is a property of THIS corpus's style, not of the grammar.**
`if E is EFoo` emits a `type_use`; `EFoo.ClassName`, `EFoo(E).Code`, `Exit(EFoo)`
would all emit `read` and are NOT raises. On CLIENT every exception-class read
WAS a raise (168/168) because nobody writes those forms here; SERVER's 266
"member-of-type" reads (`EFDException(E).Kind`-style casts) prove the
counter-example exists next door. **So the kind is the PRE-FILTER, the source
token is the CLASSIFIER, and a read whose preceding token is not `raise` is
dropped, not drawn.** Never ship the kind alone.

**R2. The syntax-first scan must still be REF-ANCHORED.** P6 is the whole
lesson: 18 of the 19 "missing" raises were in comments or a never-defined
`$IFDEF`. A scanner that finds `raise` in source and then looks for a ref is
right when the ref exists and silently wrong when it does not -- and "no ref"
has THREE causes (comment, directive, parser gap) the scanner cannot tell
apart. Rule: iterate REFS, read source around each one. The only source-first
rows are bare `except` and `raise;` (P9), and those are drawn `[inferred]`
inside an indexed impl span with the sentence "directive state not evaluated".

**R3. `on E: Exception` catches everything, so "where is it handled" is mostly
"the first catch-all up the chain" -- and P13 says the chain is usually EMPTY.**
Four of five focus candidates have zero resolved callers (event handlers,
interface dispatch). The honest chart says "no resolved caller in this index"
with the count of callers it DID find, and never "unhandled". The riskiest
premise in this verb is not the classifier; it is that a reader takes "escapes
to depth 3" as "escapes to the user".

**R4. Ancestry outside the project is UNKNOWN, not "Exception".** `EConvertError`
under `on E: EDatabaseError`? We cannot tell without the library DB (STOP list,
and still being written). The typed-handler match is: exact name, or a walk of
`type_ancestors` that reaches the handler's type INSIDE the project, or the
handler is `Exception`. Anything else renders as `may catch -- ancestry not in
this index` on a dashed edge. Do not hard-code an RTL hierarchy: it will be
wrong for FireDAC/DevExpress and nobody will notice.

**R5. `ERollback` is a warning about every name heuristic in this plan.** 798
rows on SERVER from ONE variable name. The same failure exists in consumers
(`FIB` vs `FIB$FIELDS_INFO`, P21), in feeds-from (`dsrFtrs` in three forms,
P28) and in lands-where (`ImcFIB_FIELDS_INFO` vs `FIB$FIELDS_INFO`, P36). Each
verb has its own place where a name match is NOT identity, and each is called
out in its design below. When a match is by name, the row says `[by name]`.

**R6. The SQL index is HISTORY, not schema (P15/P16) -- and it bit THIS plan.**
117 of 135 tables are declared twice; `FOLDERS` carries 126 index columns
against 79 live; the first pass of P34 reported `ID` in 149 tables because it
counted rows. A column-level consumers chart that lists a column dropped in
2019 is confidently wrong. Collapse declarations on name; prefer the LAST
declaration in file order (`MS2_OLDER_BCK` is a backup, and the migration
scripts are numbered); and print the collapse count. The 5 live-only `PDF_*`
tables cannot appear at all -- disclose that the scripts are not the live
schema.

**R7. `sql_reads` is 14 tables wide and looks complete (P22).** A reads chart
on the fact alone is the "smaller confident answer" failure mode this project
exists to prevent. The fact is rendered `[certain]`, the literal scan
`[inferred]`, and BOTH counts are printed on the focus box so the gap is
visible. This is also an engine finding -- section 10.

**R8. feeds-from's DFM says one thing and the code says another (P28-P30).**
`Blueprint4.dfm` binds `edtF1` to `Blueprint4_Model.dsrFolder`, which does not
exist; `Blueprint4.pas:1015` re-points `edtF1.DataBinding.DataSource` at
runtime. A chart that follows the DFM draws a dead module; one that follows
the code loses the control name on 11 of 12 rows (`.DataBinding`). Draw BOTH:
the DFM row marked `[dangling]` when the module is not in the index, and the
code row marked `[re-pointed at]` with the routine, anchored to the line even
when `receiver_text` is empty (the line is still the fact).

**R9. The 41% exact resolution in P32 is per DATASOURCE, not per control.**
The 22 one-table datasources serve the simple list forms (one VM = one table);
the 17 many-table ones serve the busy forms (Blueprint4, AssignGroups,
MachineList) that a reader is MORE likely to ask about. Coverage measured by
"controls whose feed resolves" will be lower than 41%. Measure it at build
time and print it on the chart; do not quote 41%.

**R10. lands-where's 99.7% is a convention (P35), and the 6 exceptions are the
interesting rows.** `TmcFOLDERS.TABLE`, `.GRIDS`, `.MENUS` are NOT columns and a
chart that "lands" them in `FOLDERS.TABLE` is wrong. The column must EXIST in
the collapsed `$SQL` column set; otherwise the row says "not a column of
FOLDERS -- computed or UI-only" and stays un-anchored on the DB side.

**R11. Source freshness is a per-file check, not a per-clone assumption (P11).**
On the pre-1.18 DL clone 18 of 128 files differed; on the re-clone 1 of 130
does, and CLIENT still has 1. Any classifier that reads `file:line:col` MUST
check `files.sha256` first. This belongs in `Emit-Common` (Task 0), because
the next person will forget it.

**R12. Multi-line `raise` / `on` clauses.** Measured 0 multi-line raises on
CLIENT (every `raise X.Create` has `raise` on the same line; the classifier's
"previous line" fallback never fired). It stays in the classifier because
Delphi permits it, but it is not a measured risk here.

**R13. Inline directives inside a qualified type name.** `EExtraExceptionInfo.pas`
writes `E is {$IFDEF USE_NAMESPACES}System.SysUtils{$ELSE}SysUtils{$ENDIF}.EInOutError`
-- the ref is a `member-access` and the token before the name is `}.`. Those
3 rows are `is`-tests and are dropped either way, but `Get-SourceContext`
must strip `{$...}` directives INSIDE a line before looking at the preceding
token, or a future `raise {$IFDEF X}A{$ELSE}B{$ENDIF}.EFoo.Create` is missed.

---

## 3. Task 0 -- shared additions (do first)

* **`Test-SourceFresh $Path`** in `Emit-Common.ps1`: sha256 of the file on disk
  vs `files.sha256`; returns `$true`/`$false`. Every source-reading emitter
  calls it per file and renders `[stale source]` rows for a mismatch instead of
  classifying. (R11)
* **`Get-SourceContext $Path $Line $Col $Len`**: returns the comment-stripped
  text BEFORE and AFTER a ref on its line, plus the previous non-blank line,
  with `'...'` strings blanked, `{...}` / `(*...*)` / `//` removed and `{$...}`
  directives blanked (R13). One place, because P6 shows the stripping is
  load-bearing. Strip with a LINE-PRESERVING regex over the whole file
  (replace comment bytes with spaces, keep the newlines) so line numbers stay
  aligned with the index -- a per-line state machine was tried in this session
  and was the slower, buggier route.
* **`Get-SqlTableSet`**: the collapsed `$SQL` table set (135 names -> id of the
  LAST declaration in file order) and per-table column sets, cached per run.
  Also `Get-SqlBodyText` for triggers (scan to `^`) with the `SET TERM`
  variant for procs (P20) -- budget the proc variant separately.
* **`Get-SqlVerbTables $Text`**: the P23 regex, one place -- `(FROM|JOIN|INTO|
  UPDATE|DELETE FROM|EXECUTE PROCEDURE)\s+([A-Z][A-Z0-9_$]*)`, case-SENSITIVE
  on the verb, membership-checked against the collapsed set.
* **`Get-DataSourceChain $Form $DsName`**: P27-P33 as one function returning
  `{ Control rows; DataSource (same-file only); Dangling; RePointedAt[]; DataSetSites[];
  RhsType; CandidateTables[]; BoundColumns[]; ResolvedTable | $null; Grade }`
  -- shared by feeds-from AND lands-where (the DFM-field selection), so the two
  cannot disagree on what a control feeds from.
* **Encoding after EVERY edit** -- strict 7-bit ASCII, CRLF, no BOM.

---

## 4. Task 1 -- `exception-paths` (M) -- GO

Selects a METHOD (qualified name; `Resolve-MemberSelection` with kinds
method/procedure/function/constructor/destructor, `-Hint 'exception-paths selects a routine'`).

**Inputs.** `$CLI`-style project clone. Two different populations, on purpose:

* **Per focus (the chart's rows): ALL refs of kind `read` and `type_use`
  enclosed by the routine, NO name filter.** The token before the ref decides
  (`raise` -> RAISE, `on <id>:` / `on ` -> HANDLE); everything else is
  dropped. A routine has at most a few thousand refs, and this is the only
  form that catches `raise EdxException.Create` (P9: 180 source raises vs 168
  under the name filter) and cannot be fooled by `ERollback` (P5) -- a local
  variable is never preceded by `raise` or `on x:`.
* **Index-wide (the pre-check and the counts on the focus box): the cheap
  name-filtered candidate set** -- `^E[A-Z]\w*$` or `^Exception$`, minus any
  name declared in this index as something other than a `class` (`EOPart`
  local_var, `EWclassconv` const, `ERollback` local). Printed as
  "approximately N raise sites / M handlers index-wide (name-filtered)".
  Scanning all 266k refs for the two tokens is the exact alternative and is
  allowed if it stays under a few seconds; measure once and pick.

**Algorithm.**

1. Index-wide pre-check (the touches-tables precedent): count candidate refs,
   count those whose file is `Test-SourceFresh`. Refuse only if the index has
   ZERO candidate refs; print both counts on the focus box.
2. Own body: refs enclosed by the focus (`enclosing_symbol_id`, P12). Classify
   each with `Get-SourceContext`:
   * `read` + preceding token `raise` -> **RAISE** row, anchored to the line,
     labelled with the type. `raise X.Create(...)`, `.CreateFmt`, `.CreateRes`
     all match (the token before the NAME is what counts, R1).
   * `type_use` + `on <id>:` or `on ` immediately before -> **HANDLE** row.
   * anything else (decl, `class(`, `is`, `as`, cast) -> dropped from the
     picture, counted in a disclosure line ("N other references to exception
     types in this body are declarations or tests").
   * a `read` with any other preceding token -> dropped and counted (R1).
3. Source-only rows, `[inferred]`, bounded to the focus impl span, comment-
   stripped: bare `except` blocks (no `on` on the same or next non-blank
   line), `raise;` (re-raise), `raise <ident>;` (raise of a variable). Each
   carries the note "source scan; compiler directives not evaluated".
4. Handled-where: walk CALLERS via `call_edges` -> `refs.enclosing_symbol_id`
   to depth `-Depth` (default 3, the who-calls precedent). For each caller,
   classify ITS handle rows (step 2) and ITS bare-except rows (step 3). A raise
   of type T is "caught at" the first caller (by depth) whose handler is:
   exact T, or `Exception`, or a bare `except`, or a project ancestor of T by
   `type_ancestors` walk -> **solid edge**; a typed handler whose relation to T
   cannot be established inside the index -> **dashed edge `may catch --
   ancestry not in this index`** (R4). If no caller at any depth qualifies:
   the row says "no handler found within N caller levels (M callers walked)";
   if the focus has ZERO resolved callers: "no resolved caller in this index"
   (R3). Never the word "unhandled".
5. `Get-EdgelessFiles` disclosure as in every caller-walking chart.

**Renders.** LEFT cluster RAISES (type, line, anchored), CENTRE the focus box
with counts, RIGHT cluster HANDLERS-IN-BODY, and BELOW a caller chain cluster
per depth with the catching handler anchored; `[inferred]` rows dashed.

**Disclosure rows on the focus box** (always): "N raise sites (M types) --
K handler clauses in body -- B bare except blocks `[inferred]` -- callers
walked: C over D levels" and "type_use refs read from source at file:line:col;
files checked fresh: F of G".

**VERIFY** (`$CLI`; section 9 has the codes):

* `Blueprint4.PDFImport.ViewModel.TBlueprintPDFImport_ViewModel.PersistScanToDB`
  (impl 1607-1715) -> 6 RAISE rows all `Exception` (lines 1624, 1653, 1667,
  1679, 1691, 1707), 0 handlers in body, callers d1 `AutoScanIfNeeded` (0
  handlers), d2 `ForceRescan` (0 handlers), d3 none -> "no handler found
  within 3 caller levels (2 callers walked)".
* `Gagefrm2.TfrmGageport2.Configure_ComPort` (1630-1736) -> 1 RAISE
  (`Exception`@1703), 3 HANDLE (`Exception`@1690, 1705, 1732), the `is`-test
  @1695 and the cast @1696 DROPPED and counted, 0 resolved callers.
* `uMain.Model.TMainModel.LoadInspectionNames` (60-87) -> 7 RAISE `EDataError`
  (65, 68, 71, 74, 78, 81, 85), 0 handlers, 0 resolved callers -> the
  "no resolved caller" sentence.
* `BASICSF.CopyRecords` (4957-5074) -> 1 HANDLE `Exception`@5037, plus
  `[inferred]`: `raise E`@5046 and `raise`@5064 (no ref rows exist for either).
* `uAutoTest.RunAutoTest` (678-2086) -> 41 HANDLE rows (all `Exception`),
  capped by `-Cap` with the standard `+N more` disclosure.

---

## 5. Task 2 -- `consumers` (M-L) -- GO with caveat

Selects a TABLE (`FOLDERS`) or a COLUMN (`FOLDERS.PARTNMBR`). Two indexes are
READ: the Delphi project clone given by `-DbPath` and `$SQL` given by
`-SqlDbPath` (both through `Get-CloneDb`).

**Inputs.** `$SQL` collapsed table/column sets (P15); SERVER `symbol_facts`
sql_reads/sql_writes (P21); SERVER SQL-verb literals (P22/P23); trigger bodies
(P19); proc bodies if P20's scanner converges; CLIENT DFM bindings (the
shown-where query, for the column form) and CLIENT table-name literals (P25).

**Algorithm.**

1. Resolve the selection against the collapsed `$SQL` set; refuse a name that
   is not a table (or `T.C` not a column of T) NAMING the nearest match. Print
   "declared N times in the scripts; showing the last" when N > 1 (R6).
2. Index-wide pre-check on the Delphi clone: `sql_reads`/`sql_writes` counts
   (touches-tables' query) AND the uppercase-verb literal count. Zero of both =
   "this index has no SQL at all -- ask the SERVER index". CLIENT lands at
   "no facts" but NOT at "no SQL text": it has 239 table-name literals, so the
   `[by name]` half still renders.
3. **Table form.** Rows:
   * `[certain]` SERVER routines whose fact names T (write side: 148 facts;
     read side: 19), anchored via touches-tables' literal-provenance rule.
   * `[inferred]` SERVER routines with an uppercase-verb literal naming T
     inside their impl span (`Get-SqlVerbTables`), grouped read/write by verb,
     MINUS the ones already certain. Both counts on the focus box (R7).
   * `[inferred]` CLIENT routines/units holding a literal equal to T (P25),
     labelled `[by name]` -- these are pipe commands, not SQL.
   * triggers `FOR T` (`$SQL` refs, 183 on declaration lines -- P17) anchored
     to the script line; procs naming T in their body if scanned, else
     name-only `[body not scanned]`.
   * `sql_index ON T` rows from the same 26 refs.
4. **Column form.** Rows: SERVER routines that name T in SQL context AND
   word-match C in a literal in the same span (P24); triggers FOR T whose body
   mentions `NEW.C`/`OLD.C` (P39); CLIENT DFM bindings with `FieldName = C`
   WHERE the control's `Get-DataSourceChain` resolves to T (P32/P33) -- a
   binding whose chain does NOT resolve is counted in a disclosure line, never
   drawn as a consumer of T (P34: `ID` is in 77 tables).
5. Disclosure: "script-derived schema: 135 tables; 5 live tables are not in
   the scripts (2026-09-23)"; "positional `Fields[i]` reads are not visible".

**Renders.** Focus = the table/column box; LEFT = readers, RIGHT = writers,
BOTTOM = DB-side (triggers/procs/indexes) in the touches-tables DB hue;
`[inferred]` clusters dashed.

**VERIFY** (`$SQL` numbers final; `$SRV`/`$CLI` as re-cloned):

* `-Table CAUSFAIL` -> certain writers 1 (`PrepareSaveQuery`), inferred
  readers >= 1 (`PrepareLoadQuery`), triggers 3 (`CAUSFAIL_BIU5` MS5.SQL:15,
  `CAUSFAIL_BIU0` MS6.SQL:34, `CAUSFAIL_BUD0` MS6.SQL:44), CLIENT `[by name]`
  units 1 (`uCausFail.ViewModel`: const at :37 plus literals at :258-259).
* `-Column CAUSFAIL.REASON` -> SERVER 2 routines, trigger 1 (`CAUSFAIL_BIU5`),
  CLIENT bindings: 7 rows carry `REASON` index-wide, of which ONLY those whose
  chain resolves to CAUSFAIL are drawn (expected 1: `uCausFailForm.dfm:60`,
  `colREASON`).
* `-Column DRA1.FLDRID` -> SERVER 3 routines incl. `TPipeSessionBuilder.HandleCopyOperation`.
* `-Table FOLDERS` -> "declared 2 times; showing the last"; column set 79.

---

## 6. Task 3 -- `feeds-from` (M) -- GO with caveat

Selects a CONTROL (the DFM component qualified name, e.g. `frmCausFail.colREASON`).

**Inputs.** DFM bindings (`FieldName`/`DataField` + the three DataSource
props), `TDataSource` components, DFM `DataSet` props, code `.DataSet`
assignments, code `.DataBinding.DataSource` re-pointing, view-model type ->
unit -> table-name literals, `$SQL` column sets. All through
`Get-DataSourceChain` (Task 0).

**Algorithm.** The chain is drawn as ONE row per hop, each hop graded:

| hop | source | grade |
|---|---|---|
| control -> datasource name | DFM prop | certain, anchored to the .dfm line |
| datasource name -> `TDataSource` | same-file component | certain; a prefixed name with no such module -> **`[dangling]`** (65 rows, P28) |
| control re-pointed in code | `DataBinding.DataSource` member-access in the form's unit | `[re-pointed at routine:line]` -- anchored even when `receiver_text` is `.DataBinding` (P29) |
| datasource -> dataset | DFM `DataSet` (5) or code `X.DataSet := RHS` (scan EVERY site, not the first -- `dsrFolder`'s first site is a `CodeSite.Send` format string) | certain, anchored to the assignment line |
| RHS -> type | `symbols.signature` of the RHS root | certain |
| type -> table | table-name literals in the type's unit; if MANY, the P33 column-set tie-break; if the type is an interface, `[unresolved -- interface-typed view-model]` | **`[inferred]`** with the candidate list printed when not unique |
| table.column | column exists in the collapsed `$SQL` column set | certain/absent |

**Renders.** A vertical chain, top = control, bottom = `TABLE.COLUMN`; every
`[inferred]` hop dashed; a broken chain ends in a grey "chain stops here:
<reason>" row -- never a guessed table.

**Disclosure rows.** "datasources in this index: 54 (5 wired in DFM, 51 in
code); resolved to one table: 22, ambiguous: 17, unresolved: 9 -- measured
per datasource" and, on a dangling row, "the DFM names `dmlSystem2`, which is
not in this project".

**VERIFY** (`$CLI`):

* `frmCausFail.colREASON` -> chain: DFM `DataController.DataSource`
  `dsrCausFail` (same file, `uCausFailForm.dfm:88` declares it) ->
  `dsrCausFail.DataSet := FViewModel.MemTable` (`uCausFailForm.pas:125`,
  `FormActivate`) -> `TCausFailViewModel` -> `CAUSFAIL` (one literal,
  `uCausFail.ViewModel.pas:37`) -> `CAUSFAIL.REASON` exists. Grade of the
  table hop: `[inferred]`.
* `frmMachineList.<a column on dsrMachines>` -> candidates 4 (MACHINES,
  STATIONS, PLANT, DEPARTTBL), tie-break on 6 bound columns -> `MACHINES`.
* `frmDefineSerialNumbers.<a column on dsrPList>` -> candidates 3, tie-break
  leaves 3 -> "ambiguous: SERID, SERREAD, SERPART share every bound column";
  exits 0.
* `frmBlueprint4.edtF1` -> DFM `Blueprint4_Model.dsrFolder` `[dangling]`,
  re-pointed at `Blueprint4.pas:1015` (`RepointJobHeaderToFolder`).
* `frmBlueprintCADImport.<a control on dsrBals>` -> chain stops at
  `IBlueprintCADImport_ViewModel` (interface-typed), exits 0.

---

## 7. Task 4 -- `lands-where` (M) -- GO with caveat

Selects a FIELD in one of two kinds, dispatched on what resolves (the
protocol-trace precedent):

* an ORM property or field: `uCAUSFAIL.TmcCAUSFAIL.REASON` / `fREASON` /
  `iCAUSFAIL.ImcCAUSFAIL.REASON` (2,063 properties; P35);
* a DFM-bound field: a control's `FieldName` (903 rows; P38) -- resolved
  through `Get-DataSourceChain` and then continuing as the ORM case for the
  resolved `TABLE.COLUMN`.

**Algorithm (ORM kind).**

1. Class name `Tmc<T>` / `Imc<T>` -> T must be in the collapsed `$SQL` set
   (129 of 134 do; the `FIB$` four and `MEMCONTROLPLANNINGPRESETS` refuse
   with the name they tried). Grade `[inferred -- naming convention, 1,991 of
   1,997 properties on table-named classes are a column of that table]`.
2. Property name -> column of T in `$SQL`: exists -> certain row
   `TABLE.COLUMN` anchored to the script declaration; missing -> "not a column
   of T (computed / UI-only)" and the DB side of the chart is empty (R10).
3. Server write path, anchored: `TDataService_<T>_SERVER.PrepareSaveQuery`'s
   literal naming the column (`(ID, REASON, SEVERITY, SYSTID)` at
   `uCAUSFAIL_SERVER.PAS:124`); `ParamByName('<COL>')` literal in `Save`
   (182/189 tie, P37); `Obj.<PROP>` member-access in `Save`/`Load` (5,013
   rows). Server read path: `PrepareLoadQuery`'s `<COL> AS <COL>` literal
   (`:109`).
4. DB side: triggers `FOR T` whose body mentions `NEW.<COL>`/`OLD.<COL>`
   (P39), anchored to the script line; procs if P20's scanner converges.
5. Client side (reverse of feeds-from): DFM bindings with `FieldName = COL`
   whose chain resolves to T -- drawn; the rest counted.

**Renders.** Top = the selected property (anchored), then the server
DataService rows, then `TABLE.COLUMN`, then triggers/procs; the client
bindings as a side cluster. Convention hops dashed.

**Disclosure rows.** "table by naming convention (Tmc<T>): 1,991 of 2,063
properties in this index follow it"; "positional `Fields[i]` reads not shown";
"script-derived schema, 5 live tables absent".

**VERIFY**:

* `uCAUSFAIL.TmcCAUSFAIL.REASON` -> `CAUSFAIL.REASON` certain; server rows:
  `PrepareSaveQuery` (`uCAUSFAIL_SERVER.PAS:124`), `PrepareLoadQuery`
  (`:109`), `Save` ParamByName, `Load` `Obj.REASON` (`:159`); trigger
  `CAUSFAIL_BIU5` (MS5.SQL:15); client bindings resolving to CAUSFAIL: 1.
* `uFOLDERS.TmcFOLDERS.TABLE` -> "not a column of FOLDERS"; DB side empty;
  exits 0.
* `iCAUSFAIL.ImcCAUSFAIL.SYSTID` -> triggers 2 (`CAUSFAIL_BIU5`, `CAUSFAIL_BUD0`).
* `uFIB_FIELDS_INFO.TmcFIB_FIELDS_INFO.<any>` -> refuses: "no table named
  FIB_FIELDS_INFO in the SQL index (the scripts declare FIB$FIELDS_INFO)".

### Path B -- when `orm_links` arrives (short, by ruling)

`orm_links` (`delphi_symbol_id`, `sql_symbol_id`, `confidence`, `link_kind`,
`evidence`) is the engine's own version of hops 1-2 above; `fb_datasets` /
`fb_columns` / `fb_relations` replace the script-derived schema with the live
one (and would bring the 5 `PDF_*` tables).

* **Detection** (one query, in `Emit-Common`): `SELECT COUNT(*) FROM orm_links`
  plus `MAX(computed_at)`. The gate asserts the count it EXPECTS -- today 0 --
  so a snapshot landing in a clone is a FAILING assertion, not a silent
  upgrade: `A-OL-ROWS` = 0 on `$CLI` and `$SRV`.
* **Switch**: `Get-DataSourceChain` and the lands-where step 1 take their
  table from `orm_links` when a row exists for the symbol (grade `[certain]`
  when `confidence = 'certain'`), and fall back to the derived path
  otherwise. The chart prints which route each row took. Nothing else changes.
* **Do not design further** until the owner rules on the snapshot.

---

## 8. Negative tests -- each MUST fail as stated, leaving no `.svg`

| # | command | expected |
|---|---|---|
| N20 | `Emit-ExceptionPaths -Qname <a field>` | refuses naming the kind, hint "exception-paths selects a routine" |
| N21 | `Emit-ExceptionPaths -Qname <a routine in uMain.ViewModel.pas>` (the one CLIENT file whose sha256 differs on disk, P11) | ALWAYS manufacture the mismatch, never write to ANY database: give `Test-SourceFresh` / `Get-SourceContext` a `-SourceOverride @{ <indexed path> = <scratch path> }` hook, copy that source file to a scratch path with one line changed, pass the map, then assert EVERY row of that file reads `[stale source]` and none is classified. Do not depend on the disk happening to differ |
| N22 | `Emit-ExceptionPaths -Qname BASICSF.CopyRecords` | the two `raise` rows are `[inferred]` and dashed; assert the dot has exactly 1 solid HANDLE row and 2 dashed rows |
| N23 | `Emit-ExceptionPaths -Qname Gagefrm2.TfrmGageport2.Configure_ComPort` | the `is`-test at :1695 and the cast at :1696 are NOT raise or handle rows (assert `line=1695` and `line=1696` are absent from the dot) |
| N24 | `Emit-Consumers -Table OPERATION -SqlDbPath $SQL` | renders (it IS in the scripts), focus box carries "declared 1 time" and the script-derived sentence. Its absence from the LIVE schema is a HUMAN validation step, not a gate: the emitter cannot know |
| N25 | `Emit-Consumers -Table PDF_SCAN` | refuses: "no table PDF_SCAN in the SQL index (script-derived; the scripts may lag the live schema)" |
| N26 | `Emit-Consumers -Column FOLDERS.NOPE` | refuses naming FOLDERS' column count (79) |
| N27 | `Emit-Consumers -Table CAUSFAIL -DbPath $CLI` | renders: fact half says "this index has no SQL facts"; literal half shows the `[by name]` unit; exits 0 |
| N28 | `Emit-FeedsFrom -Control <a TDataSource>` | refuses: "feeds-from selects a data-aware CONTROL, not a datasource -- ask consumers/shown-where" |
| N29 | `Emit-FeedsFrom -Control frmBlueprint4.edtF1` | the DFM row reads `[dangling]` and a `[re-pointed at]` row exists; assert both phrases in the dot |
| N30 | `Emit-FeedsFrom -Control <a column on dsrPList>` | "ambiguous: SERID, SERREAD, SERPART" and NO `TABLE.COLUMN` row; exits 0 |
| N31 | `Emit-LandsWhere -Field uFOLDERS.TmcFOLDERS.TABLE` | "not a column of FOLDERS"; no trigger rows; exits 0 |
| N32 | `Emit-LandsWhere -Field <a field on a non-Tmc class>` | refuses: "not an ORM object property (class is not Tmc<T>) and not a DFM-bound field" |
| N33 | any of the four pointed at a LIVE DB | refuses via `Get-CloneDb` (existing N19 extended to the new emitters and to `-SqlDbPath`) |
| N34 | `Emit-Consumers` with `-SqlDbPath` pointing at a Delphi clone | refuses: "not a SQL index (0 sql_table symbols)" |
| N35 | any of the four pointed at a `*.sqlite.pre-1.18` file | `Get-CloneDb` accepts it (it is under the clone root) -- so the EMITTER must refuse on `schema_meta` / file count: assert CLIENT `files = 625`; a 562-file clone is the pre-1.18 copy |

## 9. Gate assertions -- POSITIVE, with expected numbers

**These clones ARE the post-1.18 baseline (re-cloned 10:11; measured 10:28-10:45).
No re-measure flag applies. If the engine re-parses again, re-clone FIRST,
re-run, and re-baseline in ONE commit whose message lists what moved.**
`$SQL` rows will never move.

| code | assertion | expected |
|---|---|---|
| A-EP0-CANDS | index-wide raise / handle rows on `$CLI` (after the P5 exclusion) | 168 / 185 |
| A-EP0-ROUTINES | routines with >=1 raise / >=1 handler | 120 / 106 |
| A-EP0-DROPPED | non-raise/handle candidate refs counted index-wide (decl 30 + class 17 + is 8 + as 2 + cast 8 + member-access 7) | 72 |
| A-EP0-SOURCE | comment-stripped source rows inside indexed spans: bare except / on-except / `raise;` / `raise <var>` / routines with a bare except | 86 / 180 / 12 / 2 / 56 |
| A-EP1-RAISES | `PersistScanToDB` raise rows | 6 |
| A-EP1-TYPES | distinct raise types | 1 (`Exception`) |
| A-EP1-CALLERS | callers walked at depth 3 | 2 |
| A-EP1-CAUGHT | catching handlers found | 0 |
| A-EP2-HANDLES | `Configure_ComPort` handle rows | 3 |
| A-EP2-DROPPED | non-raise/handle refs counted (is + cast) | 2 |
| A-EP3-RAISES | `LoadInspectionNames` raise rows (`EDataError`) | 7 |
| A-EP3-CALLERS | resolved callers | 0 |
| A-EP4-INFERRED | `CopyRecords` inferred rows (raise E + raise;) | 2 |
| A-EP5-HANDLES | `RunAutoTest` handle rows | 41 |
| A-EP-FRESH | files with a sha256 mismatch among those the focus touches | 0 for every focus above (none is in `uMain.ViewModel.pas`) |
| A-CO0-TABLES | collapsed `$SQL` tables / declarations | 135 / 252 |
| A-CO0-TRIGGERS | trigger bodies scanned | 183 / 183 |
| A-CO0-FORTABLE | triggers FOR a known table | 177 |
| A-CO1-CERT-W | `CAUSFAIL` certain writers | 1 |
| A-CO1-INF-R | `CAUSFAIL` inferred readers | EXACT count, measured at build time and pinned (includes `PrepareLoadQuery`); `>=` is not a gate |
| A-CO1-TRIG | `CAUSFAIL` triggers | 3 |
| A-CO1-CLIENT | `CAUSFAIL` client `[by name]` units | 1 |
| A-CO2-SRV | `CAUSFAIL.REASON` server routines | 2 |
| A-CO2-TRIG | `CAUSFAIL.REASON` triggers | 1 |
| A-CO2-BIND | `REASON` bindings index-wide / drawn (chain -> CAUSFAIL) | 7 / 1 |
| A-CO3-SRV | `DRA1.FLDRID` server routines | 3 |
| A-CO4-DECL | `FOLDERS` declarations collapsed | 2 |
| A-CO-IDX | `$SRV` index-wide facts read / write / symbols-with-either | 19 / 148 / 157 |
| A-CO-LITS | `$SRV` uppercase-verb literals / tables named after FROM-JOIN / by fact | 782 / 133 / 14 |
| A-FF0-DS | datasources / DFM-wired / code-wired | 54 / 5 / 51 |
| A-FF0-RESOLVE | one-table / many / none (per datasource) | 22 / 17 / 9 |
| A-FF0-DANGLING | DFM datasource rows with a missing module / re-pointed in code | 65 / 21 |
| A-FF1-TABLE | `frmCausFail.colREASON` -> table | `CAUSFAIL` |
| A-FF1-HOPS | chain rows | 5 (control, ds, assignment, type, table.column) |
| A-FF2-CANDS | `dsrMachines` candidates / after tie-break | 4 / 1 (`MACHINES`) |
| A-FF3-AMBIG | `dsrPList` after tie-break | 3 |
| A-LW0-CONV | Tmc properties / on table-named classes / column-matching | 2,063 / 1,997 / 1,991 |
| A-LW0-DS | `TDataService_<T>_SERVER` classes | 133 |
| A-LW1-COL | `TmcCAUSFAIL.REASON` -> column | `CAUSFAIL.REASON` |
| A-LW1-SRV | server rows (PrepareSave, PrepareLoad, Save param, Load Obj.) | 4 |
| A-LW1-TRIG | triggers touching REASON | 1 |
| A-LW2-TRIG | `SYSTID` triggers | 2 |
| A-LW-PARAM | `ParamByName` literals in DataService routines / column-matching | 189 / 182 |
| A-OL-ROWS | `orm_links` rows on `$CLI` and `$SRV` (path-B detector) | 0 / 0 -- a non-zero here is the SIGNAL, not a failure to fix |
| A-AR1-* | the architecture assertions | GREEN since d009f409 (563 / 2859 / 293 / 30716) -- do not touch |

Plus the byte checks (ASCII/CRLF/no BOM) on every new `.ps1`, and the
`ClickTargets >= Expected` anchor check every emitter already returns.

## 10. What CANNOT be made correct, and why -- said plainly

* **exception-paths cannot say "unhandled".** With 169 of 185 handlers being
  `on E: Exception` and 4 of 5 focus candidates having zero resolved callers,
  the chart can only say where a handler WAS found within N levels, and that
  the walk ended. Interface dispatch and event wiring are not in
  `call_edges`, and that is the engine's boundary, not a chart defect.
* **exception-paths cannot resolve external ancestry.** Whether
  `on E: EDatabaseError` catches `EFDDBEngineException` needs the library
  index, which is on the STOP list and still being written. Those edges are
  dashed with the reason.
* **consumers cannot see positional reads** (`Fields[1].AsString`) and cannot
  know the live schema (5 `PDF_*` tables, 1 dropped `OPERATION`). It is a chart
  of the SCRIPTS plus the Delphi literals, and says so.
* **consumers' read side is `[inferred]` by construction** until the engine's
  `sql_reads` fact covers multi-line `SQL.Add` (P22) -- 14 vs 133 tables. That
  is an engine finding: **file `INBOX-sql-reads-misses-multiline-sql-add.md`**
  with `uCAUSFAIL_SERVER.PAS:100-114` as the reproducer (this planning session
  was not permitted to write outside this file, so the implementer files it,
  and appends a `wrong` row to `stats\draglint-gaps.log`).
* **feeds-from resolves 22 of 54 datasources exactly, 5 more by tie-break.**
  The interface-typed view-models (6) and the multi-table ones with zero bound
  columns (6) stop the chain. `orm_links` would close this; nothing derivable
  does.
* **lands-where is a naming convention** at 99.7%. It is drawn as one, with the
  count. The 6 non-column properties are the proof it is not a fact.
* **procedure bodies** (P20) are NOT scannable with the trigger scanner. If the
  `SET TERM` variant does not converge in its budget, procs are name-only rows
  in both consumers and lands-where, labelled `[body not scanned]`.

## 11. Build order

0. DONE (d009f409): battery green on the 1.18 clones.
1. Task 0 (`Test-SourceFresh`, `Get-SourceContext`, `Get-SqlTableSet`,
   `Get-SqlVerbTables`, `Get-DataSourceChain`; unit-check each against the
   numbers in section 1 BEFORE any emitter).
2. `exception-paths` -- single-index, the cleanest premises, and it exercises
   `Test-SourceFresh` first.
3. `consumers` -- table form, then column form; the proc-body scanner LAST and
   time-boxed.
4. `feeds-from` -- on `Get-DataSourceChain`.
5. `lands-where` -- reuses 3 and 4; smallest new code.
6. Gate: register N20-N35 and section 9; run the FULL battery.
7. Gallery (`New-ExampleGallery.ps1`) rows for the four; `STATUS-questions.md`
   moves them from BLOCKED to SHIPPED with the caveat sentence each; `hot.md`
   overwritten (it is a cache).

## STOP -- do not

* Run `drag-lint index` / `fb-snapshot` / `autodoc` on ANY database.
* Open the live project DBs, `C:\Projects\.drag-lint\library-*.sqlite`
  (still being written), or `C:\Projects\DB\SQL\drag-lint-sql.sqlite` --
  clones only, and never the `*.pre-1.18` copies.
* Use a name regex as the exception FILTER (P5); use the kind as the
  CLASSIFIER (R1); scan source for raises without a ref (R2).
* Resolve a DFM datasource by bare name across files (P28).
* Count SQL tables or columns by ROW (P15 / P34): collapse on name first.
* Quote the 41% (R9) or the 99.7% (R10) as a fact about the chart's coverage;
  measure the per-control / per-property number at build time and print THAT.
* Hard-code an RTL exception hierarchy (R4).
* Read a source line by column without `Test-SourceFresh` (R11).
* Touch anything outside `charts\`; `git push`; `git add -A`; bare `git stash`.
