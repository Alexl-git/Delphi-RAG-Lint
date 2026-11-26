# Fields that need data of other tables (cross-table fields) -- design 2026-11-26

Status: DESIGN APPROVED 2026-11-26 (owner: XQ1-XQ14 all A, section 12; FireDAC copy sources added to X3, section 3.1).
Lane `lane/v155-xtable`; slice X1 BUILT there 2026-11-26 (tests `tests\fieldrepo\CrossTableTests.dpr`, runner
`tests\autotest\run_v155_XTABLE.ps1`; as-built notes at the end of 2.3).

Inputs:
* Goals draft `2026-11-25-cross-table-fields-goals-DRAFT.md` (G1-G8, N1-N7, owner answers P1-P4 in its sections 9-10).
* Survey `C:\TEMP\claude\lanes\v154\MEMSURVEY\REPORT.md` (M2022, steps 1-6).
* 1.54.1 ORIGIN: `2026-11-26-join-field-origin-design.md` (read-dfm: the table of every field of a join).
* Rulings `2026-11-23-field-repository-v3-rulings.md` (R1, R3), model `2026-11-22-field-repository-v2-design.md` (4.3, 4.4, 5).
* Owner answers 2026-11-26, `C:\TEMP\claude\lanes\v153\OWNERPAGE\OWNER-LIVE-RESULTS-153.md` Q4-Q7, summarised:
  * Q4: IPCHART -> 2-3 tables -> MSCLIST for the name and DECIMALS. Store the origin of every input a calc field needs;
    selecting IPCHART.FTRNAME prompts to join what it needs; rows already loaded in this thread / form are not re-read
    from Firebird, but DL proves the loaded chunk is the right one.
  * Q5: a field belongs to its dataset: `T1.A := T2.B + T3.C` is stored with T1; DL finds T2, T3 and generates a
    Firebird or FireDAC Local SQL statement that brings B and C.
  * Q6: store CODE (table aliases + field names), not a plain macro; one universal resolution: including T1.A makes
    DL join T2, T3 to T1 (if not yet joined) and add B, C to the field list.
  * Q7: M2022 is not fixed; kbmMemTable AttachedTo tells the original table of a calc field; a lost-link warning
    perhaps in January.

## 1. Goals (from the draft, with the owner's answers folded in)

| # | Goal | Done when |
|---|---|---|
| G1 | A stored consumer (calc, OnGetText, ...) works on any dataset whose home table reaches its inputs | Same value as the M2022 form for the same rows |
| G2 | DL finds what is missing (columns, joins), shows it, adds it after a yes | One dialog; every addition can be unticked |
| G3 | One formula per field, stored once with its home table (P3 A, Q5) | One fix reaches every form |
| G4 | Rows the form already holds are not read again, if they are the right rows | No query when the keys are present; only missing keys are fetched |
| G5 | Works without SQL to extend (CLIENT memory tables) | Same consumer on a TFDMemTable |
| G6 | Never a wrong value silently | Unknown input or row = empty and reported |
| G7 | FireDAC Local SQL over the form's tables is a delivery | Same consumer through TFDLocalSQL |
| G8 | Freshness is the SERVER change signal, not a DL policy (P2) | DL adds no refresh logic of its own |

Out of every slice here: going DOWN (one to many: sums, counts, the latest sample -- 3 fields in the survey); SQL
built at run time (24 M2022 joins); bodies that read another dataset's CURRENT row (stateful, 47 in the survey).

## 2. The model: code with aliases (Q5, Q6, P3)

### 2.1 What is stored

The formula stays where it is: Pascal statements in `DL_FIELDS_INFO.CALC_BODY` (and the event columns of R2) on the
row of the HOME table (T1). Own fields keep the R3 macro `{{FIELD}}`. A field of another table is written
`{{ALIAS.FIELD}}`, where ALIAS is an INPUT ALIAS declared for that field (2.2). That is the owner's "code with table
aliases and field names": the body is code, the alias says which table row it means, and the alias's PATH says how
that row is reached from a T1 row. There is no second macro language and no per-form copy of the code.

```
DL_FIELDS_INFO  IPCHART | FTRNAME   (kind calc)
CALC_BODY       {{FTRNAME}}.AsString := FtrNameString({{MSC.NOTATION}}.AsInteger, {{MSC.DECIMALS}}.AsInteger, ...);
DL_FIELD_INPUTS IPCHART | FTRNAME | '' | MSC -> path IPCHART_INSPRSLT > INSPRSLT_MSCLIST   (ends at MSCLIST)
```

R3 is amended: `{{X.F}}` is legal exactly when X is a declared alias of the field; any other `{{X.F}}` stays an error.

### 2.2 New repository tables (schema 4)

`DL_RELATIONS` -- one N:1 step, child row to ONE parent row (N2, N3). PK RELATION_NAME.

| # | Column | Type | Null | Note |
|---|---|---|---|---|
| 0 | RELATION_NAME | VARCHAR(63) | N, pk | role name; default = FK constraint name, else `<CHILD>_<PARENT>[_n]` |
| 1 | CHILD_TABLE | VARCHAR(68) | N | |
| 2 | PARENT_TABLE | VARCHAR(68) | N | |
| 3 | SOURCE | VARCHAR(10) | N | `FK` (from DL_CONSTRAINTS), `FORM` (found in a form's join, confirmed), `HAND` |
| 4 | CONSTRAINT_NAME | VARCHAR(68) | Y | the FK for SOURCE = FK; columns then come from DL_CONSTRAINT_COLUMNS |
| 5 | PARENT_KEY | VARCHAR(63) | N | the PK / UNIQUE constraint the parent columns match (proof of "one row") |
| 6 | IS_DEFAULT | BOOLEAN | N | default false; true = the stored answer of P1 B for (CHILD_TABLE, PARENT_TABLE) |

`DL_RELATION_COLUMNS` -- PK (RELATION_NAME, POSITION): CHILD_COLUMN, PARENT_COLUMN. Written for FORM / HAND relations;
for FK relations a copy of the constraint columns (so a relation survives a schema refresh that renames nothing).

`DL_FIELD_INPUTS` -- PK (TABLE_NAME, FIELD_NAME, BINDING, ALIAS).

| # | Column | Type | Null | Note |
|---|---|---|---|---|
| 0 | TABLE_NAME | VARCHAR(68) | N, pk1 | home table of the consumer (T1) |
| 1 | FIELD_NAME | VARCHAR(68) | N, pk2 | consumer field |
| 2 | BINDING | VARCHAR(160) | N, pk3 | `''` = the field's default binding; `<FORM>.<DATASET>` = an override for one dataset (P3 A: IPTrack's sample limits) |
| 3 | ALIAS | VARCHAR(63) | N, pk4 | the name used in `{{ALIAS.F}}` |
| 4 | PATH | VARCHAR(1000) | N | relation names in order, `>`-separated; `''` = the home table itself (an alias of T1 is allowed, not needed) |
| 5 | TARGET_TABLE | VARCHAR(68) | N | end table of PATH (redundant; `repo check` verifies it) |

Only the PATH differs between bindings; the body never does (P3 A: CLIENT never chooses between formulas).

### 2.3 Migration, backup, check

* `REPO_SCHEMA_VERSION = 4`; `repo migrate [--apply]` 3 -> 4 (and 1/2 -> 4 through the existing chain): adds the three
  tables, empty; nothing else changes, so the dry run lists three CREATEs only. Text backup `#DLREPO 4`; `#DLREPO 3`
  restores into 4 unchanged; read-dfm and gen-handlers refuse schema 3 ("run repo migrate"), as R-open-detail 8 did for 2.
* Relations of SOURCE = FK are NOT created by migrate or refresh-schema; they are created when a binding first uses
  the step (2.4 keeps the graph derived from DL_CONSTRAINTS). A dropped FK leaves its relation; `repo check` warns.
* `repo check` adds: every `{{X.F}}` has an alias X for every binding of the field; every PATH step exists and chains
  (parent of step n = child of step n+1, first child = TABLE_NAME); TARGET_TABLE has column F (schema facts, or a
  DL_FIELDS_INFO row of that table); PARENT_KEY is a PK / UNIQUE of the parent on exactly the parent columns;
  at most one IS_DEFAULT per (child, parent); an override binding has the same alias set as the default.

### 2.4 Dependencies and the closure (N7)

`CalcDependencies` returns own fields AND `(alias, field)` pairs. `ExpandSelection` S1 extends over aliases: selecting
IPCHART.FTRNAME selects its own inputs, and for every `(MSC, DECIMALS)` the requirement "MSCLIST.DECIMALS reached by
PATH". When an input is itself a calc field of the parent table (MSCLIST.X), its own inputs are taken with the paths
CONCATENATED (IPCHART path + MSCLIST's path); a concatenated path may be longer than the search depth (3.2), because
it is composed from stored bindings, not searched. Cycle guard as today, over (table, field).

As built (X1, 2026-11-26):
* `ParseMacros` (used by the generators) still refuses `{{A.F}}`: nothing can deliver a foreign input before X4 / 1.56.
  `ParseMacrosWithAliases` / `CalcInputs` accept a declared alias; on schema 3 and older `repo check` keeps the 1.53 error.
* read-dfm and gen-handlers still accept schema 3: they write nothing into the new tables yet. X3, which does, raises their
  minimum to 4.
* `repo check` codes: input-alias-undeclared, input-unknown-field, input-no-field-row, input-path-broken,
  input-target-mismatch, binding-no-default, binding-alias-set, relation-source-invalid, relation-no-columns,
  relation-two-defaults, relation-key-not-unique, relation-fk-missing, relation-fk-mismatch; WARN relation-key-unknown and
  relation-fk-gone (the schema facts lack the constraint). A cycle through aliases: `calc dependency cycle across tables`.
* Restore: an older backup is migrated row-wise up to the TARGET file's schema (`MigrateRepoRows(pFrom, pTo)`), also into a
  non-current file; no row is dropped (TextBackupTests 21b, 25d, 25i).

## 3. Where origins come from

### 3.1 The home table of a consumer

| Source | What it gives | State |
|---|---|---|
| ORIGIN (1.54.1): select list, Origin (three forms), star | table + column of every data field of a join | built |
| ORIGIN 2.3: calc of a join reading ONE table | home = that table | built |
| NEW: calc of a join reading SEVERAL tables (60 in M2022) | home = the CHILD END (below), inputs = aliases | 1.55 |
| NEW: kbmMemTable `AttachedTo = X` in the DFM, `AttachTable(X)` in code (Q7) | the memtable has X's fields, so X's origins, transitively | 1.55 (DFM + direct call) |
| NEW (owner 2026-11-26): TFDDataSet literal calls `T.CloneCursor(S, ...)`, `T.CopyDataSet(S, ...)`, `T.CopyData(S)`, `T.AppendData(S)`, and the assignment `T.Data := S.Data` | the same role as AttachedTo: link T -> S, follow transitively; a field of T named like a field of S gets S's origin | 1.55 (X3) |
| Survey steps 2a-4 (bulk copy, created in code, AssignRecord, field copies) | per-field origins of memtables | later slices (9) |

CHILD END rule for a calc over several tables: the home is the ONE table among the inputs' tables from which every
other input table is reached going UP along relations (3.2). IPCHART + MSCLIST -> IPCHART (MSCLIST never reaches
IPCHART). No such table, or two (a 1:1 pair), -> unresolved `no table of A B reaches all the others` and offered to
the owner in the dialog (OWNER Q3).

AttachedTo: the DFM property and a literal `X.AttachTable(Y...)` call in the form's unit give the link; links through
arrays (INSPFLDR.pas:10168), variables or other forms are not followed. In M2022's tip only one link exists
(INSPFLDR.pas:2373), so the measured gain there is small: the survey's +64 calc of step 6 came from the hg rev 25 DFMs
and is NOT claimed (Q7: M2022 is not fixed). The lost-link warning is a later slice (January, Q7).

FireDAC copy sources (owner 2026-11-26). Read from the index: the call sites of CloneCursor / CopyDataSet / CopyData /
AppendData (`find-callers`, bare name) and the writes of `Data` (`usages`); a site counts only when the receiver and
argument 0 are literal dataset names (`X`, `Self.X`, `dm.X`, a field of the form or a data module the unit uses), with
comments removed from the argument (M2022 has `tblIPChartB.CopyDataSet({ dmlGlbReadings.tblIPChart }qryLoadIPSamples)`).
The link target -> source is followed transitively with a cycle guard; two different sources for one target = report
(survey rule "never pick"); a copy into a dataset that ALSO gets field writes keeps the copy as origin only for the
fields not written afterwards (survey events overlap; per field, as the ORIGIN unit is the field). Locals, arrays,
parameters and FindComponent are not followed.

Measured 2026-11-26, read-only (M2022: the survey's index copy `MEMSURVEY\m.sqlite`; Micronite2027: a copy of
`C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`, 663 files, 2 changed since built; script output
`C:\TEMP\claude\lanes\v155\XTABLE\scratch\fd-copy-calls.csv`):

| | CloneCursor | CopyDataSet | CopyData | AppendData | `Data :=` of a dataset |
|---|---|---|---|---|---|
| M2022 call sites (literal) | 6 (6) | 131 (130) | 0 | 0 | 0 (188 writes of `Data`, none a dataset) |
| Micronite2027 call sites (literal) | 1 (1) | 0 | 0 | 0 | 0 |

M2022: 91 of the 245 no-SQL datasets are the target of a literal site; 75 of them get a source that has a table
(73 directly, 2 through another target), carrying 67 calc and 39 lookup fields. 1.54.1 resolves none of the 245, so that
is the X3 gain from these sources (INFERRED: datasets matched by unit + name, the source by name only; X3 measures it
with the engine). Of the survey's 111 unresolved datasets only 4 are linked (the survey already followed these copies
as step 2a). Micronite2027: one site (`FIgnoreTbl.CloneCursor(FRegionsTbl, ...)`, Blueprint4.PDFImport.ViewModel.pas:1565,
two fields of a view model, no DFM dataset): the CLIENT fills its memory tables through the pipe (cmdDelta), so these
sources resolve about nothing there; its origins need the delta / view-model path (not designed).

### 3.2 The relation graph and the path (N2, N3, P1 B)

Nodes: tables. Edge child -> parent when the child columns equal a parent key (PK or UNIQUE constraint) column for
column: (a) every FK of DL_CONSTRAINTS whose REF_CONSTRAINT is a PK / UNIQUE (FbDdl already checks this); (b) DL_RELATIONS
of SOURCE FORM / HAND. A relation whose parent side has no PK / UNIQUE is never an edge (rows would multiply). Unique
INDEXES (not constraints) are not in the schema facts today (refresh-schema reads RDB$RELATION_CONSTRAINTS only; the DDL
parser ignores CREATE INDEX): OWNER Q7.

Search: all simple paths from home to target, at most 3 steps (OWNER Q5). Choice, first that applies:
1. the binding already stored for this field (and dataset);
2. the path the form's own SQL uses: its join conditions (ON, and WHERE equalities between two FROM tables) matched to
   relations, step by step (P1 "take the one of the form being read");
3. the IS_DEFAULT relation per step (P1 B);
4. exactly one path -> taken and stored;
5. several -> asked ONCE in the dialog, the answer stored as IS_DEFAULT of each step (P1 B). Never by data: two paths
   that agree on today's rows (IPCHART -> MSCLIST, 2,232,615 rows) are still two paths.

Join conditions of a form that match no FK but end on a parent key (M2022: 16 to TOOLGR12, 1 to MACHPOS) are offered
as FORM relations, confirmed once (OWNER Q6). The other 17 (TOOLASSG with TOOLFLDR, four columns) are offered only if
the four columns are a parent key; else reported. Parsing join conditions is new work: `DfmReadSql` splits the FROM
today but does not read ON / WHERE.

Measured check (1.55 test): `repo paths` over the MICRONITEV6A schema facts must reproduce the draft's table
(274 / 1,089 / 1,653 pairs; 11 / 334 / 1,168 with more than one path at 1 / 2 / 3 steps, the two-column key counted once).

## 4. Delivery 1: JOIN (Firebird SQL)

Input: the dataset's DFM SQL (parsed by DfmReadSql), the selected fields, their bindings. Steps:
1. For each needed (path, column): walk the path from the home alias of the FROM; a step already present in the FROM
   (same parent table joined on the same columns to the same child alias) is REUSED with its alias; otherwise add
   `LEFT JOIN <PARENT> <alias> ON <child>.<c1> = <alias>.<p1> [AND ...]`. Alias = the input alias, suffixed `_n` on a
   clash with a FROM name. LEFT keeps every home row when a key is NULL; a parent key keeps the row count.
2. Add `<alias>.<COL> AS <ALIAS>_<COL>` to the select list unless a select item already gives that column through
   that path. The persistent field gets that name, kind data, read-only, ProviderFlags `[]` (never written back;
   OWNER Q10); the body's `{{MSC.DECIMALS}}` resolves to that field component.
3. Keep the form's WHERE, ORDER BY, parameters and comments outside the edited ranges.
4. Refuse (reported, nothing written): UNION, GROUP BY, DISTINCT, a derived table or CTE in the FROM, a home table that
   appears twice in the FROM with no way to tell which, SQL set at run time, a TTable / TFDTable home (no SQL to
   extend: KEYED or Local SQL instead, later slices).

### 4.1 Proof (before anything is written)

| # | Check | Needs | Fails when |
|---|---|---|---|
| P1 | round trip: the new SQL parsed by the ORIGIN rules gives every added field exactly the intended table + column, and every old field its old origin | nothing | any field changes or is unresolved |
| P2 | schema: every column exists, each join is child columns = parent key columns, types of each column pair compatible | schema facts | a missing column, a non-key join, a type mismatch |
| P3 | prepare against the database (syntax, names, types) | `--connection` | Firebird refuses |
| P4 | data: `COUNT(*)` of old and new equal; first N rows (default 500) ordered by the home PK: every column both return is equal | `--connection`, read-only transaction | any difference |

P1 + P2 = "proved statically"; P3 + P4 = "proved by data". Without a connection the report says which level was
reached; the apply (later slice) requires P1-P2 and, when a connection is configured, P3-P4. Parameterised SQL: OWNER Q8.
A mismatch refuses the change (draft section 10).

## 5. Delivery 2: KEYED, and "already loaded" (G4, Q4)

DL is a design-time tool: it cannot see the rows a running form holds. It decides STATICALLY whether a loaded dataset
may serve an input, and GENERATES the run-time proof.

Static candidate: a dataset of the same form (or a data module the unit uses) whose rows are the TARGET table (N1:
dataset table, ORIGIN or AttachedTo) and which has every needed column as a data field whose origin is that column
(an unchanged copy, not computed or snapshot). Refused as a candidate: a dataset member of a thread object or another
form (thread ownership cannot be shown: TFDMemTable is not thread-safe), a dataset used as a master-detail DETAIL
(its rows follow the master cursor), a dataset whose rows are computed / user entered (survey fill class 5).

Run-time proof, generated into the handler (goals section 5): for each step, look the KEY up in the loaded parent
without moving its cursor (a `Lookup`-style no-move call; never `Locate` / `FindKey` on a dataset a grid shows).
The key is unique, so a hit is THE row, whatever else the dataset holds (rows of other characteristics do no harm, they
do not match). A miss: fetch exactly that key with a generated parameterised SELECT when the form has a connection,
else the input is empty and reported once (OWNER Q12). A filtered dataset (Filtered, ranges) only causes misses, never a
wrong row. Over several steps the proof repeats per step.

Limits, stated in the dialog: freshness is the SERVER change signal (G8, P2) -- DL adds none; a cached position of the
old code (`if X.ID <> key then X.FindKey`) is replaced, not kept; going DOWN is not keyed.

## 6. Delivery 3: FireDAC Local SQL (G7)

The same composer (4) with a second dialect: tables are the form's datasets (TFDLocalSQL names), SQL is the SQLite
dialect, the home dataset is replaced by a TFDQuery on the Local SQL connection. Proof: P1 + P2 against the datasets'
persistent fields (no Firebird). The run-time key lookup of 5 is not needed (the join matches the keys), but
"right chunk" still is: a parent key absent from the loaded parent gives NULL inputs, so the generated code reports
rows whose join found no parent (G6). Whether a Local SQL result stays updatable for the home table is NOT established
(INFERRED from FireDAC docs; checked before the slice that builds it).

## 7. SNAPSHOT

A source calc copied into a memtable while loading (survey step 2a) is a snapshot of that calc: the memtable field is
data with origin "snapshot of T.F". No composer work; recorded only (later slice with the memtable steps).

## 8. CLI and UI surface (names provisional)

* `repo paths --repo <r> --from <T> --to <P> [--depth 3] [--json]` -- read-only, lists paths with roles and defaults.
* `repo read-dfm` -- writes DL_FIELD_INPUTS / DL_RELATIONS rows as change-set inserts (checked), like every other row.
* `repo compose-sql --repo <r> --dfm <f> --dataset <d> --field <T.F>[,...] [--connection <c>] [--json]` -- prints the
  new SQL, the added fields and the proof table; changes nothing (1.55).
* Later: the IDE dialog "<field> also needs ..." (G2) and the apply through the repo -> DFM engine.

Docs-sync: each verb lands with `--help`, README, AI-USAGE and a featuregen entry in the same change.
DRAGLINT_EXTRACTOR_VERSION: unchanged by every slice here (read-dfm reads DFM / unit text at read time; no index change).

## 9. Slices (each release ships one)

| Release | Slice | Done when |
|---|---|---|
| **1.55** | X1 schema 4: three tables, migrate 3 -> 4, `#DLREPO 4`, `repo check` rules (2.3), `{{ALIAS.F}}` legal when declared, CalcDependencies + ExpandSelection over aliases (2.4) | fixtures green; migrate of a 1.54 repository copy byte-checked |
| **1.55** | X2 relation graph + path finder (pure unit) and `repo paths` | reproduces the draft's 274/1,089/1,653 and 11/334/1,168 on MICRONITEV6A facts |
| **1.55** | X3 read-dfm: join conditions parsed; calc of a join over SEVERAL tables -> child-end home + aliases + bindings from the form's joins; AttachedTo (DFM) + literal AttachTable; literal CloneCursor / CopyDataSet / CopyData / AppendData / `Data :=` links (3.1) | of M2022's 60 SEVERAL calc fields, the count that gets a home and a full binding is MEASURED and reported (no target promised); 0 wrong home in a 20-field sample read by hand |
| **1.55** | X4 `repo compose-sql`, Firebird dialect, dry run, proof P1-P2 (P3-P4 when `--connection` is given) | fixture forms: added joins reused / added, refusals of section 4 step 4; IPCHART -> MSCLIST on a copy of MICRONITEV6A proved P1-P4 |
| 1.56 | apply into the DFM (repo -> DFM engine, the dataset's SQL and new persistent fields); IDE dialog "also needs ..."; unique indexes into the schema facts (OWNER Q7) | round trip on the all-kinds fixture; IDE test |
| 1.57 | KEYED delivery with the generated key proof; Local SQL dialect | CLIENT memtable fixture: same value as the join delivery |
| later | survey steps 2a-4 for memtable origins; read-dfm turns keyed Locate / FindKey bodies (57 + 3 in M2022) into aliases; SNAPSHOT origins | measured against the survey CSVs |
| January | lost-AttachedTo warning (Q7) | owner go |

## 10. Test plan

New battery script `tests\autotest\run_v155_XTABLE.ps1`, fixtures `tests\fixtures\fieldrepo\xtable\` (a small
FK schema as DDL: IPCHART -> INSPRSLT -> MSCLIST and IPCHART -> IINSP -> MSCLIST (two paths), a parent with no key,
a 1:1 pair; forms uXJoin.dfm / .pas, uXMem.dfm / .pas with AttachedTo).

* X1: migrate 3 -> 4 dry run = three CREATEs, apply then a second migrate = `already at schema 4`; backup 4 round trip;
  `#DLREPO 3` into 4; schema 3 refused by read-dfm. `repo check`: undeclared alias, broken chain, wrong TARGET_TABLE,
  non-key PARENT_KEY, two defaults, override with a different alias set -- each named (positive control: the clean
  fixture exits 0, each broken copy exits 1).
* X1: CalcDependencies returns `(MSC, DECIMALS)`; ExpandSelection closure over a parent calc with concatenated path;
  cycle across two tables named.
* X2: one path taken; two paths -> ambiguous (no pick); stored default wins; a keyless parent is no edge; depth limit;
  the MICRONITEV6A counts (on a repository COPY, size + mtime of the original checked unchanged).
* X3: the form's ON / WHERE conditions select the path; child-end home; no child end -> unresolved with the reason;
  AttachedTo chain of two memtables, cycle guarded; AttachTable literal followed, array form not.
* X4: added LEFT JOIN, reused join, alias clash, select item already present, every refusal of section 4 step 4 with its reason;
  P1 detects a deliberately wrong generated column (positive control); P2 detects a non-key join; P3 / P4 run only with
  a connection (skipped and SAID so otherwise).
* Doc-comment and test agree (CDD + TDD): each new public routine's `<summary>` names the rule number it implements here.

## 11. Not known

* How many CLIENT (ORM3) forms hold a child and its parent at once (draft 8): needed before 1.57.
* Whether Local SQL results stay updatable for the home table (6).
* Unique indexes behind the 34 M2022 conditions with no FK (3.2).
* How many of the 60 SEVERAL calc fields have a child end: not counted (X3 measures it).

## 12. OWNER QUESTIONS (A = recommended) -- ANSWERED 2026-11-26: all A

Rulings (owner, 2026-11-26, via the coordinator): XQ1-XQ14 = A, as written below. So: `{{ALIAS.FIELD}}` with declared
aliases; alias = target table name (`_2` for a second path); home = child end, else ask; default binding + per-dataset
override; depth 3; form relations offered once; unique indexes in 1.56; parameterised SQL proved statically only;
COUNT + 500 rows; added join columns read-only with ProviderFlags []; AttachedTo from current sources only; KEYED
fetches a missing key when the form has a connection; 1.55 composes as a dry run; KEYED + Local SQL in 1.57.
Addition: FireDAC CloneCursor / CopyDataSet / CopyData / AppendData / `Data :=` as origin sources in X3 (3.1).

1. Foreign input syntax in stored code: A `{{ALIAS.FIELD}}` with aliases declared per field (2.1); B `{{TABLE.FIELD}}` with table names only. -- B cannot hold two paths to one table.
2. Default alias name: A the target table name when the field reaches it by one path, `<TABLE>_2` for a second; B always the role name. -- A reads like the owner's `T2.B`.
3. Home of a join calc over several tables: A the child end (the table that reaches all others going up), else ask; B the dataset's UpdateTableName; C always ask. -- Q5 says the field belongs to T1.
4. Bindings: A one default binding per field plus an override per `<FORM>.<DATASET>` (IPTrack's sample limits); B one binding per home table only. -- P3 A, one formula.
5. Path search depth: A 3 steps; B 4. -- 71% of pairs are already ambiguous at 3.
6. Relations found only in forms' joins (16 TOOLGR12, 1 MACHPOS): A offer once, store as confirmed FORM relation; B use declared FKs only. -- the draft already says "offered, not assumed".
7. Unique INDEXES as parent keys: A read them into the schema facts in 1.56; B constraints only. -- refresh-schema reads constraints only today.
8. Proof of SQL with parameters: A prepare + static checks only, reported "not proved by data"; B ask for parameter values in the dialog. -- P4 cannot run without values.
9. Data proof size: A COUNT(*) of old and new plus the first 500 rows by home PK; B the first N rows only. -- COUNT over 2.2M IPCHART rows takes seconds, not minutes (INFERRED).
10. Added join columns: A read-only persistent fields, ProviderFlags [] (never written back); B ordinary fields. -- an updatable join must not post parent columns.
11. AttachedTo: A read the current DFM property + literal AttachTable calls; the links lost in M2022 stay unresolved; B also accept a hint file of old links (hg rev 25). -- Q7: M2022 is not fixed.
12. KEYED key missing from the loaded parent: A fetch exactly that key when the form has a connection, else empty + reported; B always empty + reported. -- CLIENT memtables have no connection.
13. 1.55 scope: A compose-sql is a dry run with proof, nothing written into DFMs (apply in 1.56); B apply in 1.55 too. -- the repo -> DFM SQL edit has no fixture yet.
14. Order after 1.56: A KEYED and Local SQL together in 1.57; B Local SQL first. -- both share the composer and the key proof.
