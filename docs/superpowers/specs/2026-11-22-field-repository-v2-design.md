# Field Repository v2 -- field kinds, dataset field use, schema cache, generators, DFM round trip (design)

Date: 2026-11-22. Lane TT-SPEC of the v153 run. Status: DESIGN (controller reviews; owner answers section 12).
Supersedes: `docs\superpowers\specs\2026-11-20-tabletools-publish-triage-design.md` (publish-fb DROPPED, column
triage reduced to a no-op, FIB$ reader inventory deferred -- section 11) and its four plans `2026-11-20-tt-*.md`.
Parent design (still valid for the table map, file format, verbs, editor): `docs\superpowers\specs\2026-11-16-tabletools-into-dl-design.md`.
Owner inputs: `C:\TEMP\claude\lanes\v1523\SPEC-TT\OWNER-ANSWERS-TABLETOOLS.md` (TT-Q01..Q25) and
`C:\TEMP\claude\lanes\v1523\SPEC-TT\ANSWERS-REVIEW.md` section 4 (FU-1..FU-14, 2026-11-22; these WIN over the Q answers).
Older requirement notes R1-R5: `docs\INBOX-tabletools-dfm-fields-grids-calc-lookup.md`.

1.53 plans (one per lane, each executable alone):

| Lane | Plan | Model |
|---|---|---|
| FR-SURVEY | `docs\superpowers\plans\2026-11-22-fr-survey.md` | sonnet |
| FR-SCHEMA | `docs\superpowers\plans\2026-11-22-fr-schema.md` | sonnet |
| FR-LINT | `docs\superpowers\plans\2026-11-22-fr-lint.md` | session model (target resolution is judgment) |
| FR-MODEL | `docs\superpowers\plans\2026-11-22-fr-model.md` | sonnet |
| FR-CONSTGEN | `docs\superpowers\plans\2026-11-22-fr-constgen.md` | sonnet |

## 1. What the feature is for (the answer to FU-1's "what is the final goal?")

DL becomes a TWO-WAY field repository (TT-Q07, FU-2):

```
   live database (Firebird today; others via FireDAC later)
        |  ^
 read   |  |  per-table ALTER (1.54), full regeneration (later, separate task)
        v  |
   +---------------------+        generate         +-----------------------------------+
   | repository .dlrepo  | ----------------------> | code: iTABLE units (DLFR regions), |
   | (hand-kept master)  |                         | constant arrays / TFDMemTable fill |
   +---------------------+ <---------------------- +-----------------------------------+
        ^  |              DFM read (1.54)           | DFMs: persistent fields, grid     |
        |  | apply to open form via OTA (1.54)      | columns, events                   |
        |  v                                        +-----------------------------------+
   schema cache in the index DB (disposable, rebuilt by `fb-snapshot`) --> schema-aware lint
```

Three stores, three roles -- this is the design's spine:

| Store | Holds | Authority | Lifetime |
|---|---|---|---|
| repository `.dlrepo` | hand-kept field facts: captions, widths, formats, kinds, calc bodies, lookup wiring, per-dataset field use, exceptions | MASTER for everything a person edits | committed as its text backup |
| schema cache (index DB `fb_*` tables) | facts the database owns: domains, lengths, PK / unique / FK, generators | read-only mirror; refreshed only by command (TT-Q03) | disposable; `index --rebuild` loses it (Q12-3) |
| DFM / code | what a form actually uses | the CONSUMER; edited only through a confirmed change set | source control |

Every transfer between two stores goes through ONE change-set model (section 3) with an explicit direction.
Nothing ever syncs silently; "for now DL is not looking for differences, just if it stumbles upon one" (TT-Q03).

## 2. Final rulings (Q answers as refined by FU answers)

| Topic | Ruling | Source |
|---|---|---|
| publish-fb | DROPPED. The repository holds everything and can regenerate the SQL that recreates FIB$ data; the read-only server-side replacement for FIB$ is GENERATED CODE (section 7), early | FU-4 |
| Schema cache home | index DB, extended `fb-snapshot` tables, rebuilt by command; nothing enters `.dlrepo` | FU-1 A, Q02 |
| Schema sources | live Firebird AND DDL scripts, all constraint kinds | Q01 A |
| Staleness | manual refresh only; schema lint prints the snapshot date once per run | Q03 A |
| Sync model | shared change-set model; CLI prints the diff and writes only with `--apply` (all, or `--select <file>`); IDE shows a checkbox form; direction explicit on every call, NO default | FU-3 A |
| Confirm defaults | DFM -> repository: DFM wins; repository -> DFM: repository wins; lint: reports only. Dialog lists every change `old -> new`, ALL checked; check all / uncheck all / OK / Cancel / per item; itemised log `replacing X with Y` | FU-9, Q16 |
| Silencing | `DL_EXCEPTIONS` table in the repository (dataset/field, property, rule, reason); the linter reads it | FU-10 A |
| Columns | keep all six low-use columns; no drop migration; ISCALCULATED folds into FIELD_KIND | FU-5 A, Q09 A |
| Field kinds | data / calc / lookup / aggregate / graphical rows in DL_FIELDS_INFO (the table they belong to) | Q10 B, FU-6 |
| Dataset field use | a per-dataset field-selection DIALOG, persisted; calc auto-selects its data fields, never auto-unselects | FU-6 |
| Lookup wiring | by repository table + field names; default PK preferred; lint for incomplete wiring / non-PK key | Q11 A |
| Calc bodies | Pascal text plus `{{FIELD}}` macros; macro -> persistent field with typed accessor; refuse on a cycle, warn at save | Q12 A, Q13 A |
| Volatile regions | marker `DLFR` (replaces `DB-RAD` / ORMxx); migrate a unit whole on regeneration; hg is the backup, no `.dlbak`; warn when a region was hand-edited | FU-7 A, Q14 |
| DFM read | menu `Field Repository` with several items; reads ONLY the selected dataset (+ a batch for all datasets of a form) | Q15 |
| DFM write | OTA apply to the open form; the change set is computed by a lane-testable engine, OTA only applies it; fixture dataset with ALL kinds + click-level owner steps | FU-11, Q17 B |
| Grids | cxGrid table view first; store OnGetText + OnCustomDrawCell for view and columns; full event catalog from the survey | Q18 A, Q20 |
| MAXLEN constants | per iTABLE unit, new region `DLFR 2a` after section 2, regenerated with the fields; drift = repository vs schema cache | FU-12 A |
| Golden test | lane auto-classifies the 290 units (zero diff outside regions = unmodified), picks 4-6 by PK shape for owner review; pins the volatile-code version; exception file for ORM-team changes | FU-13 C |
| DB change | first slice = on-demand PER-TABLE change (one or several fields); detect what Firebird refuses; replaceable hook for FB / Micronite specifics; full DB regeneration = separate later task | FU-2 |
| Schema lint | all five rules eventually, ON by default; 1.53 ships rules 1+2 (silent without a schema snapshot) | Q23 D, FU-14 |
| Survey source | M2022 (`C:\Projects\M2022`, index `C:\Projects\M2022\_D-RAG\Micronite.sqlite`, being built 2026-11-22); Micronite2027 secondary | FU-8 |
| Slicing | 1.53: survey, schema cache + rules 1+2, repository model, generator. 1.54: DFM read/write + confirm dialog + OTA, per-table ALTER + hooks, golden port. Overflow -> 1.55; long work slices, never holds a release | FU-14 A, Q25 |
| Retirement | TableTools retires after every real entry is covered plus one week of parallel use | Q24 A |

## 3. The change-set model (shared by every sync; engine 1.53 in FR-MODEL, UIs 1.54)

Unit `DRagLint.FieldRepo.ChangeSet` (FR-MODEL builds the type and the CLI rendering; 1.54 adds producers/appliers):

```pascal
TFrChangeOp = (fcoInsert, fcoUpdate, fcoDelete);
TFrDirection = (fdDbToRepo, fdRepoToDb, fdDfmToRepo, fdRepoToDfm);
TFrChange = record
  Id: Integer;            // 1-based, stable within one change set; what --select names
  Op: TFrChangeOp;
  Target: string;         // 'DL_FIELDS_INFO MSCLIST|DIMNAME', 'uOrders.dfm qryOrdersQTY', 'MSCLIST.DIMABBR'
  Prop: string;           // column / DFM property; '' for a whole-row insert/delete
  OldValue, NewValue: string;
  Checked: Boolean;       // default per section 2 "Confirm defaults" (all True today)
  Blocked: string;        // non-empty = cannot be applied (e.g. Firebird refuses); never checked
end;
```

* Text rendering (one line per change, ASCII): `[<id>] <op> <target> <prop>: <old> -> <new>` plus
  `  BLOCKED: <reason>`; header `direction <dir>, <n> changes, <b> blocked`. `--json` mirrors the record.
* `--select <file>`: one id per line (or `all`); lines starting `#` ignored; an unknown id is an error (exit 2,
  nothing applied). Without `--apply` nothing is written anywhere.
* Every apply logs `replacing <old> with <new>` per applied change (FU-9 "itemised log").
* Direction is a REQUIRED argument of every producer; there is no default direction (FU-3).

## 4. Repository model v2 (1.53, lane FR-MODEL)

### 4.1 FIELD_KIND values (existing column DL_FIELDS_INFO.FIELD_KIND, SMALLINT)

Live data (MICRONITEV6A, 2026-11-22): FIELD_KIND 1 = 2046 rows, 2 = 3 rows (all ISCALCULATED), NULL = 68 rows.
TableTools writes 1 for a real column (SchemaSeed `FIELD_KIND_COLUMN = 1`), i.e. `Ord(TFieldKind) + 1`. v2 keeps
that encoding and adds one DL value:

| Code | Kind | Meaning | TField |
|---|---|---|---|
| NULL / 1 | data | real table column (NULL read as data) | fkData |
| 2 | calc | calculated, body in CALC_BODY | fkCalculated |
| 3 | lookup | lookup, wiring in DESTTABLE / SOURCEKEY / DESTKEY / DESTVALUE | fkLookup |
| 4 | internal-calc | fkInternalCalc (stored for completeness, generated like calc) | fkInternalCalc |
| 5 | aggregate | aggregate, expression in CALC_BODY | fkAggregate |
| 10 | graphical | no data field; a grid column drawn by events (Q01 notes) | none |

Consistency (checked by `repo check`, section 4.6): ISCALCULATED = (kind in 2, 4); ISLOOKUP = (kind = 3).
The migration sets FIELD_KIND = 2 where ISCALCULATED and FIELD_KIND is NULL or 1 (the TableTools orphan rows).

`refresh-schema` change (SchemaSeed): it already writes FIELD_KIND = 1 only for columns present in
`RDB$RELATION_FIELDS`. `CleanOrphanFields` must SKIP rows whose FIELD_KIND is not NULL/1 -- a calc / lookup /
aggregate / graphical row is not an orphan. A data row whose column vanished keeps today's behaviour
(ISCALCULATED = True, FIELD_KIND becomes 2) so old data stays visible.

### 4.2 Lookup wiring (reuses the four zero-row columns; no new column)

| Column | Meaning for kind 3 |
|---|---|
| SOURCEKEY | key field(s) in THIS table (`KeyFields`); `;`-separated for multi-field keys |
| DESTTABLE | lookup table name (repository table) |
| DESTKEY | key field(s) in the lookup table (`LookupKeyFields`); empty = the lookup table's PK |
| DESTVALUE | result field (`LookupResultField`) |

The dataset component that serves the lookup on a form is NOT stored (TT-Q11): it is resolved on apply (1.54).

### 4.3 New column DL_FIELDS_INFO.CALC_BODY (TEXT, nullable, appended LAST)

Pascal statement text for kinds 2 / 4, aggregate expression for kind 5, NULL otherwise. Macros `{{FIELD}}` name a
field of the SAME table (any kind); `{{TABLE.FIELD}}` is reserved (error in 1.53). Example:
`{{TOTAL}} := {{QTY}} * {{PRICE}};`. Macro grammar: `{{` identifier `}}`, identifier = `[A-Za-z_][A-Za-z0-9_$]*`;
`{{{{` is not an escape (no escapes in 1.53; a literal `{{` in a string is an error the user rewrites).

Dependencies of a calc field = every macro in its body except the assignment target (the macro immediately left
of the first `:=` on a statement). Pure function `CalcDependencies(pBody, pSelf): TArray<string>`.

### 4.4 New table DL_DATASET_FIELD_USE (per-dataset field selection, FU-6)

| # | Column | Type | Null | Note |
|---|---|---|---|---|
| 0 | DATASET_KEY | VARCHAR(255) | N, pk1 | `<unit file base>.<component>` e.g. `Blueprint4.Model.qryMscList`, case kept, compared case-insensitively |
| 1 | TABLE_NAME | VARCHAR(68) | N, pk2 | repository table the field belongs to |
| 2 | FIELD_NAME | VARCHAR(68) | N, pk3 | |
| 3 | SELECTED | BOOLEAN | N, default 1 | |
| 4 | SELECTED_BY | VARCHAR(10) | N, default 'user' | `user` or `auto` (auto = pulled in by a calc dependency) |

Rules (pure unit `DRagLint.FieldRepo.FieldUse`, used by the 1.54 dialog and by the 1.53 CLI):

* S1 Selecting a calc / internal-calc / aggregate field selects every dependency (transitively) that is not
  selected yet, with SELECTED_BY = 'auto'.
* S2 Unselecting ANY field never changes another row (no cascade; owner: "does NOT auto-unselect").
* S3 Selecting an already-selected field changes nothing (SELECTED_BY stays).
* S4 A dataset with NO rows means "no selection recorded" (generators then use all data fields), which differs
  from a dataset whose rows are all SELECTED = 0.
* S5 A FIELD_NAME that does not exist in DL_FIELDS_INFO for TABLE_NAME is rejected (exit 2).

### 4.5 New table DL_EXCEPTIONS (FU-10)

| # | Column | Type | Null | Note |
|---|---|---|---|---|
| 0 | RULE_ID | VARCHAR(63) | N, pk1 | lint rule id or `*` |
| 1 | DATASET_KEY | VARCHAR(255) | N, pk2, default '' | '' = any dataset |
| 2 | TABLE_NAME | VARCHAR(68) | N, pk3, default '' | |
| 3 | FIELD_NAME | VARCHAR(68) | N, pk4, default '' | '' = whole table |
| 4 | PROP | VARCHAR(63) | N, pk5, default '' | e.g. `DisplayWidth`; '' = any |
| 5 | REASON | VARCHAR(220) | N | required, like a `dl:ok` reason |

A finding is suppressed when every non-empty key column of some row matches it. Pure function
`IsExcepted(const pExceptions; const pFinding): Boolean` in `DRagLint.FieldRepo.Exceptions`. In 1.53 only the
schema rules of section 6 consult it (via the repository named by `fieldRepository`, when configured).

### 4.6 Schema version 2, migration, text backup

* `REPO_SCHEMA_VERSION = 2`; `OpenRepository` accepts 1 and 2 and validates the table set of the file's own
  version (v1 = today's five tables; v2 = + DL_DATASET_FIELD_USE, DL_EXCEPTIONS and DL_FIELDS_INFO.CALC_BODY).
  `repo init`, `import-fb` / `seed-fb` into a missing file create v2.
* `repo migrate (--repo|--project) [--apply]`: dry run prints `v1 -> v2: add DL_FIELDS_INFO.CALC_BODY, create
  DL_DATASET_FIELD_USE, create DL_EXCEPTIONS, FIELD_KIND 2 for <n> ISCALCULATED rows, user_version 2` and changes
  no byte; `--apply` writes `<repo>.before-migrate-<yyyymmdd-hhnnss>.txt` first, then one transaction. On v2:
  `already at schema 2`, exit 0. Nothing is dropped or renamed.
* Text backup: a v2 repository writes `#DLREPO 2` (tables in RepoTables order, the two new tables last); v1 writes
  `#DLREPO 1` byte-identical to today. Restore: `#DLREPO 1` into v2 is accepted (new tables empty, CALC_BODY
  NULL); `#DLREPO 2` into v1 is refused (exit 2, "migrate first"); restore into a MISSING file creates the
  file's version (keeps the existing `#DLREPO 1` goldens byte-stable).
* `repo check (--repo|--project) [--json]` (read-only): kind consistency (4.1), lookup wiring complete (4.2:
  DESTTABLE + DESTVALUE present, DESTTABLE and DESTVALUE exist in DL_FIELDS_INFO; WARN when DESTKEY is not the
  lookup table's PK), calc macro targets exist, calc dependency CYCLE (names the cycle `A -> B -> A`, Q13), field
  use rows valid (S5). Exit 0 clean, 1 findings. Q13's "warn early at save": the editor (1.54) calls the same check.
* `repo field-use (--repo|--project) --dataset <key> [--table <T>] [--select F1,F2] [--unselect F3] [--list] [--json]`
  -- the CLI face of section 4.4 (the dialog is 1.54).

## 5. Schema cache in the index DB (1.53, lane FR-SCHEMA)

New tables, created by `fb-snapshot` with `CREATE TABLE IF NOT EXISTS` inside `DRagLint.Sql.FbSnapshot` (no
change to the index store schema version, no extractor / resolver bump):

| Table | Columns |
|---|---|
| `fb_domains` | id, name, field_type, sub_type, field_length, char_length, scale, precision, nullable, default_value, check_source, charset, source ('live' or 'ddl'), snapshot_at |
| `fb_constraints` | id, relation_name, name, kind ('PK','UNIQUE','FK','CHECK','NOT NULL' excluded), index_name, ref_relation, ref_constraint, update_rule, delete_rule, source, snapshot_at |
| `fb_constraint_columns` | constraint_id, position, column_name |
| `fb_generators` | id, name, current_value (live only, NULL for ddl), source, snapshot_at |
| `fb_snapshot_meta` | key, value (`snapshot_at_utc`, `source`, `database` = Database value only, never a password) |

`fb_columns` gains `char_length` and `domain_is_system` (ALTER TABLE ADD COLUMN when missing; old snapshots read
NULL). Readers:

* Live: one read-only transaction over RDB$FIELDS, RDB$RELATION_CONSTRAINTS, RDB$INDEX_SEGMENTS,
  RDB$REF_CONSTRAINTS, RDB$GENERATORS (current value via `GEN_ID(g, 0)` is a read). Existing verb, new data.
* Offline: `fb-snapshot --ddl <file.sql>[;<file.sql>...] --db <db>`: a small statement splitter + parser for
  `CREATE DOMAIN`, `CREATE TABLE` (column defs, inline and table constraints), `ALTER TABLE ... ADD [CONSTRAINT]`,
  `CREATE [UNIQUE] INDEX` (ignored), `CREATE GENERATOR|SEQUENCE`, `SET TERM` blocks (skipped). Unknown statements are
  counted and listed, never fatal. Live and DDL never mix in one snapshot (the newer call replaces all fb_* rows).
* `schema-length` helper (pure, used by lint and generators): `ColumnCharLength(table, column)` -> char_length,
  falling back to the domain's char_length; returns -1 when unknown.

## 6. Schema-aware lint, rules 1 + 2 (1.53, lane FR-LINT)

Both rules are ON by default (Q23 D) and SILENT when the DB has no schema snapshot (`fb_snapshot_meta` empty or
`fb_columns` empty). When they run, lint prints once: `schema snapshot <utc> (<source>)` (Q03 A). Findings in
DL_EXCEPTIONS (4.5) are suppressed when the project config names a repository; otherwise only `dl:ok` applies.

| Id | Severity | Fires when |
|---|---|---|
| `schema-maxlen-drift` (rule 1) | warning | a constant named `<TABLE>_<FIELD>_MAXLEN` (case-insensitive; `$` in a table name written `_`) whose table/column is in the snapshot has a value different from the column's char length. Also: a string LITERAL longer than the column's char length assigned to a target resolved to that column (resolution, below) |
| `schema-length-bound` (rule 2) | warning | `Copy(x, i, N)` assigned to a resolved column target, `SetLength(s, N)` where `s` is then assigned to it, `.Size := N` / `MaxLength := N` on a resolved field / editor, or a DFM persistent `TStringField` / `TWideStringField` whose `Size` property differs, where N (literal or a constant the index resolves to an integer) > column char length (DFM: <>) |

Target resolution (conservative; unresolved = silent, never a guess):
1. ORM field variables and properties linked by `link-orm` (`T<X>` / `I<X>` / `F<Y>` naming) -> X.Y.
2. Persistent field components in a DFM: component name = dataset name + field name AND the dataset's SQL /
   `UpdateOptions.UpdateTableName` / ORM link names exactly one snapshot table.
3. `FieldByName('<Y>')` on a dataset resolved as in 2.
4. Local identifiers `t<FIELD>` / `fld<FIELD>` are NOT resolved in 1.53 (the Blueprint4 example uses them; a
   positive control uses the MAXLEN constant there instead). Recorded as a known gap, revisit after the survey.

Positive control in every test: the iMSCLIST pattern (`MSCLIST_DIMABBR_MAXLEN = 35` against a domain of 10 fires;
`= 10` is silent). Rules 3-5 (field not in schema; DFM display props vs repository; SQL unknown column) are 1.54+.
The default-on frame guard count (356 on 2026-11-22) rises by 2 in the same change.

## 7. Constant-array / TFDMemTable generator (1.53, lane FR-CONSTGEN)

Purpose (FU-4): the read-only server-side replacement for the FIB$ tables. The server reads registry rows from
generated code instead of Firebird.

`drag-lint repo gen-const (--repo|--project) --unit <UnitName> --output <file.pas> [--table DL_X,...]
[--memtable] [--dry-run]`

* Default tables: DL_FIELDS_INFO, DL_DATASETS_INFO, DL_ENUMVALUES, DL_ERROR_MESSAGES (never DL_META,
  DL_DATASET_FIELD_USE, DL_EXCEPTIONS). Generic over `RepoTables`, so v1 and v2 repositories both work
  (CALC_BODY is emitted when present).
* Per table: a record type `T<Table>Row` (field per column, Pascal types: string / Integer / SmallInt / Boolean /
  Byte; NULL-able columns get a companion `<Col>IsNull: Boolean` only when the table HAS a NULL in that column, so
  the shape is data-dependent -- the emitted header states the rule) and
  `const <TABLE>_ROWS: array[0..N-1] of T<Table>Row = (...)` in PK order.
* Strings: ASCII-escaped Pascal literals (`''`, `#13#10`, `#nnn` for <0x20 and >0x7E); split into `+`-joined pieces
  of at most 200 characters; no source line over 250 characters.
* `--memtable` adds `procedure Fill<Table>(pTable: TFDMemTable);` creating FieldDefs with the SAME names, types and
  sizes as the FIB$ table (RepoTables map, section 4 of the parent design) and appending every row, so code that
  read `TABLE=FIB$FIELDS_INFO` can be fed unchanged.
* Output 7-bit ASCII, CRLF, deterministic (same repository -> same bytes; no timestamp; the header names the
  source repository file base name and the row counts).
* Header + DocInsight comments on every public symbol of the generated unit (the generated unit must be lint-clean
  under `lint <file>`).

## 8. M2022 survey (1.53, lane FR-SURVEY)

`drag-lint dfm-survey --db <index DB> [--json] [--csv-dir <dir>] [--top N]` -- read-only over `dfm_objects` +
`dfm_properties` (+ `symbols` for handler bodies). Sections:

1. Datasets: count by class (TFDQuery, TFDMemTable, TFDTable, TClientDataSet, Paradox / BDE TTable / TQuery,
   others) and by form.
2. Persistent fields: count by field class and by `FieldKind` (data / calc / lookup / internal-calc / aggregate),
   lookup property completeness (`LookupDataSet`, `LookupKeyFields`, `LookupResultField`, `KeyFields`).
3. Events: every `On*` property on datasets, fields, grid views and grid columns: event name x owner class ->
   count, and distinct handler count (Q20 C: no threshold, the catalog IS the answer).
4. Grids: view classes (`TcxGridDBTableView`, banded, card, TDBGrid), column counts, columns WITHOUT a field binding
   that have a drawing / text event (= graphical candidates, Q01), view-level vs column-level event counts.
5. Calc handlers: per `OnCalcFields` handler, the fields it assigns (by text over the handler body) -> candidate
   calc bodies for a later import.
6. Strings-vs-Values (Q21 research): in grid event handlers, counts of `.Values[` vs `.Strings[` / `DisplayTexts[`
   accesses, with the first 20 sites, as input to a read-only analysis note.

CSV files (`--csv-dir`): one per section, header row, ASCII. The lane runs it on M2022 (primary) and
Micronite2027 (secondary) DB COPIES and writes the CSVs plus a one-page `SUMMARY.md` for the owner's triage to
`C:\Projects\M2022\_DL-SURVEY\2026-11\` -- OUTSIDE the DL repository, because the DL repository is public and the
survey names private Micronite code. Only the verb, its fixture and its tests are committed in DL. No temp repository is written in 1.53
(the DFM read that would fill one is 1.54).

## 9. 1.54 designs (outline -- planned after the 1.53 lanes land and the survey is read)

* DFM read (`Field Repository > Read Fields from Dataset...`, `... from All Datasets of Form...`, CLI
  `repo read-dfm --dfm <file> [--dataset <name>] --direction dfm-to-repo`): produces a change set (section 3);
  persistent fields with all kinds, lookup props, field events, calc handler text -> CALC_BODY with macros.
* Field-selection dialog per dataset: list all fields with kind, select all / unselect all, rules S1-S4, writes
  DL_DATASET_FIELD_USE; reusable any number of times.
* Repository -> DFM: engine computes the change set over DFM TEXT (lane-tested byte for byte, dry run);
  an OTA adapter applies the same set to the OPEN form. Fixture: a purpose-built form with one dataset holding
  every kind (data, calc, lookup, aggregate, graphical column) + a cxGrid table view; owner steps click-level
  (`owner-test-page` skill).
* Calc / grid handler generation: `DLFR` volatile regions inside OnCalcFields / grid events; first insert at the END
  of an existing handler; hand-edit detection by a hash in the region header.
* DLFR marker migration: `{$REGION 'DB-RAD n'}` -> `{$REGION 'DLFR n'}` for the whole unit at once during
  regeneration; region detection accepts both; `DLFR 2a` = the MAXLEN region (FU-12).
* Golden test port: FU-13 C (auto-classify 290 units, 4-6 picks, pinned volatile version, exception file; the
  existing `tests\fieldrepo\ormgen-golden-known-drift.txt` becomes that exception file).
* Per-table ALTER (`repo alter-table --table T --direction repo-to-db --connection ...`): change set per field;
  Firebird-refused changes detected BEFORE executing (VARCHAR shrink, string -> numeric, any type change on a
  column with dependencies from RDB$DEPENDENCIES / constraints / indices / computed-by) and marked BLOCKED with the
  reason, or -- when the user selects it -- the safe path: pre-scan `count(*) WHERE char_length(c) > n` / failed
  casts, `ADD c_NEW`, `UPDATE ... SET c_NEW = CAST(c ...)`, `DROP c`, `ALTER c_NEW TO c`, `ALTER c POSITION p`, one
  transaction, verify. Vendor specifics behind `IFrDbProvider` (FireDAC metadata where it suffices; Firebird +
  InterBase implementations testable); site specifics behind a replaceable `IFrSchemaHook` (BeforeTable /
  AfterTable / ExtraStatements) with the Micronite hook in its own unit.
* Full DB regeneration (DDL + initial data + legacy Paradox load + FKs last, Loader order): separate later task,
  Micronite-only at first, hooks as above.

## 10. 1.53 lanes, dependencies, shared files

| Lane | Needs before start | New units (own) | Shared files (hub commit, INT unions) |
|---|---|---|---|
| FR-SURVEY | M2022 index finished (`Micronite.sqlite.indexing.lock` gone) for the live run; code + fixture test can start at once | `src\sql\DRagLint.Sql.DfmSurvey.pas`, `src\cli\DRagLint.CLI.DfmSurvey.pas` | `src\cli\DRagLint.CLI.pas` (dispatch + flags), `drag-lint.dpr/.dproj` |
| FR-SCHEMA | none | `src\sql\DRagLint.Sql.FbDdl.pas`, `src\sql\DRagLint.Sql.SchemaFacts.pas` | `DRagLint.Sql.FbSnapshot.pas` (owned by this lane), `DRagLint.CLI.pas` (`--ddl` flag), dpr/dproj |
| FR-LINT | FR-SCHEMA merged (or its table DDL copied into the test fixture); starts after FR-SCHEMA task 2 | `src\lint\DRagLint.Lint.SchemaRules.pas`, `rules\schema-*.json` if the catalog needs them | `DRagLint.Lint.RuleCatalog.pas`, lint dispatch in `DRagLint.CLI.pas`, frame guard counts |
| FR-MODEL | none | `DRagLint.FieldRepo.ChangeSet.pas`, `.FieldUse.pas`, `.Exceptions.pas`, `.Check.pas`, `.Migrate.pas`, `src\cli\DRagLint.CLI.RepoModel.pas` | `DRagLint.FieldRepo.Schema.pas`, `.TextBackup.pas`, `.SchemaSeed.pas` (owned by this lane), `DRagLint.CLI.Repo.pas` hub, dpr/dproj |
| FR-CONSTGEN | none (generic over RepoTables; re-run its golden after FR-MODEL merges) | `DRagLint.FieldRepo.ConstGen.pas`, `src\cli\DRagLint.CLI.RepoConstGen.pas` | `DRagLint.CLI.Repo.pas` hub, dpr/dproj |

FR-MODEL and FR-CONSTGEN both add a `CLI.Repo` hub commit (`SUB_VERBS`, dispatch); FR-SURVEY and FR-SCHEMA both
touch `CLI.pas` ParseArgs. Each keeps its hub edit in ONE commit named `hub: <lane> dispatch`; INT unions them.
No lane bumps DRAGLINT_VERSION / extractor / resolver. Each lane owns its featuregen entry change
(`field-repository` for MODEL / CONSTGEN; new entries `dfm-survey`, `schema-lint` for SURVEY / LINT; the
existing `fb-snapshot` entry for SCHEMA) and runs `featuregen verify --id <id> --by ENGINE`.

## 11. What is superseded and why

| Item (2026-11-20 spec / plans) | Fate |
|---|---|
| `repo publish-fb`, plan `tt-publish-fb`, plan `tt-publish-ui` | DROPPED (FU-4): generated code replaces FIB$ at run time |
| Column triage, `DL_COLUMN_FATE`, plan `tt-column-triage` | DROPPED (FU-5 keep all); its v1/v2 compatibility rules are reused by section 4.6 |
| FIB$ reader inventory, plan `tt-fib-removal` | DEFERRED to 1.54: useful once generated constants exist (it lists which ORM3 readers switch to them) |
| Marker name DL / DLTT | replaced by DLFR (FU-7 final) |

## 12. Open questions for the owner

1. **Where does the server-side registry code live?** The generator (section 7) writes one Pascal unit with the
   registry rows as constants. Which folder and unit name do you want for Micronite (for example
   `ORM3\SERVER\uFieldRegistry.pas`), and should the CLIENT get the same unit? Until you say, the lane writes to a
   path you pass with `--output` and nothing in ORM3 is changed.
2. **What makes a dataset's identity in the field selection?** We key a dataset by `<unit>.<component>` (e.g.
   `Blueprint4.Model.qryMscList`). If you rename the component, the saved selection no longer matches. Is that
   acceptable for now (DL reports "selection for unknown dataset"), or do you want DL to follow renames?
3. **Schema snapshot after a full reindex.** The schema facts live in the index DB, and `index --rebuild`
   recreates that file, so the snapshot is lost until you run `fb-snapshot` again (schema lint is silent
   meanwhile and says so). Acceptable, or should `--rebuild` keep the `fb_*` tables?
4. **Graphical columns as rows.** A graphical column (no data field, drawn by an event) is stored as a row of its
   TABLE in DL_FIELDS_INFO with kind "graphical". If the same picture column appears on grids of different tables,
   it needs one row per table. Fine, or should graphical columns belong to a grid layout instead?
5. **Lookup with a key that is not the lookup table's PK.** `repo check` warns. Do you want it to be an error
   instead (generation refuses until fixed)?
6. **`t<FIELD>` / `fld<FIELD>` locals.** The Blueprint4 truncation example assigns through local variables named
   after the field. Rule 2 does not guess what such a local points to in 1.53. Do you want a naming-convention
   match (`tDIMABBR` -> column DIMABBR of the dataset in scope) later, accepting some false findings?
7. **Survey output.** The survey CSVs and summary go to `C:\Projects\M2022\_DL-SURVEY\2026-11\`, outside the
   public DL repository, because they name your private Micronite forms and fields. Is that folder right, and
   should it be committed to the M2022 Mercurial repository or stay a local file?
