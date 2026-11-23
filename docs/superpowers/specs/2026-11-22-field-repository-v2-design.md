# Field Repository v2 -- field kinds, schema facts in the repository, generators, DFM round trip (design)

Date: 2026-11-22 (rev 2, same day: owner answers FR-1..FR-7 folded in, M2022 survey numbers added).
Lane TT-SPEC of the v153 run. Status: DESIGN (controller reviews).
Supersedes: `docs\superpowers\specs\2026-11-20-tabletools-publish-triage-design.md` (publish-fb DROPPED, column
triage dropped, FIB$ reader inventory deferred -- section 11) and its four plans `2026-11-20-tt-*.md`.
Parent design (still valid for the table map, file format, verbs, editor): `docs\superpowers\specs\2026-11-16-tabletools-into-dl-design.md`.
Owner inputs: `C:\TEMP\claude\lanes\v1523\SPEC-TT\OWNER-ANSWERS-TABLETOOLS.md` (TT-Q01..Q25) and
`C:\TEMP\claude\lanes\v1523\SPEC-TT\ANSWERS-REVIEW.md` section 4 (FU-1..FU-14) and section 5 (FR-1..FR-7).
Later answers WIN: section 5 > section 4 > the Q answers. Older requirement notes R1-R5:
`docs\INBOX-tabletools-dfm-fields-grids-calc-lookup.md`.

1.53 plans (one per lane, each executable alone):

| Lane | Plan | Model | State |
|---|---|---|---|
| FR-MODEL | `docs\superpowers\plans\2026-11-22-fr-model.md` | sonnet | RUNNING from 0874f4978 (told FR-2 / FR-4) |
| FR-SCHEMA | `docs\superpowers\plans\2026-11-22-fr-schema.md` | sonnet | after FR-MODEL merges (same files) |
| FR-LINT | `docs\superpowers\plans\2026-11-22-fr-lint.md` | session model | after FR-SCHEMA's read API commit |
| FR-CONSTGEN | `docs\superpowers\plans\2026-11-22-fr-constgen.md` | sonnet | any time |
| FR-SURVEY | `docs\superpowers\plans\2026-11-22-fr-survey.md` | -- | DROPPED: the survey is done (section 1a) |

## 1. What the feature is for

DL becomes a TWO-WAY field repository (TT-Q07, FU-2):

```
   live database (Firebird today; others via FireDAC later)
        |  ^
 read   |  |  per-table ALTER (1.54), full regeneration (later, separate task)
 (add / |  |
 delete |  |
 after  v  |
 confirm)
   +------------------------------+     generate      +-----------------------------------+
   | FIELD REPOSITORY  .dlrepo    | ----------------> | code: iTABLE units (DLFR regions), |
   | hand-kept facts + schema     |                   | shared registry-constant unit      |
   | facts (domains, PK/FK, ...)  | <---------------- +-----------------------------------+
   +------------------------------+   DFM read (1.54) | DFMs: persistent fields (= the     |
        |  apply to open form via OTA (1.54) ------>  | per-dataset selection), grids      |
        v                                             +-----------------------------------+
   schema-aware lint (reads the repository the project config names)
```

### 1.1 Three databases (FR-3, supersedes FU-1)

| DB | Holds | Shared by | Changes |
|---|---|---|---|
| platform library `C:\Projects\.drag-lint\library-<platform>.sqlite` | RTL / VCL / third-party symbols | every project of a platform | rarely |
| project index `<project>\_D-RAG\<base>.sqlite` | the project's code facts | one project | every edit; disposable (`--rebuild`) |
| FIELD REPOSITORY `<primary project>\_DL-REPO\<Database>.dlrepo` | everything about the DATABASE: hand-kept facts (captions, formats, widths, enum mapping, kinds, calc / lookup / layout code) AND the schema facts read from Firebird (domains, lengths, PK / unique / FK, generators) | every project that uses the same database (Micronite: SERVER + CLIENT + PACKAGE), like the library | only by confirmed change sets: new fields added, vanished ones deleted after confirmation |

Rule: a fact goes in the repository unless it genuinely cannot live there. What stays in the project index is
only what is about ONE project's code: links from a column to the code symbols that use it (`link-orm`,
`fb_columns.sql_column_symbol_id` of the existing `fb-snapshot`), and lint findings. The existing `fb-snapshot`
verb and its `fb_*` index tables stay as they are (no extension); the schema-aware features read the repository.
Consequences: no reindex work for schema facts; `index --rebuild` loses nothing schema-related.

### 1.2 How a project finds its repository (proposal adopted for 1.53, mirrors the library)

Resolution order, first hit wins: (1) `--repo <file>` flag; (2) `"fieldRepository": "<path>"` in the project's
`_D-RAG\drag-lint-project.json` (key already read by `repo` verbs: `DRagLint.CLI.Repo.ProjectConfigRepo`);
(3) a `"fieldRepository"` value on the project's section of the manifest `drag-lint.json` (next to its DB path);
(4) none -> repository-backed features are silent and say so once. `resolve-dbs` prints the resolved repository
as a third line (`repo: <path>` or `repo: none`). The resolver is one unit, `DRagLint.FieldRepo.Locate`, used by
lint, `resolve-dbs` and (later) the `repo` verbs.

### 1.3 Survey facts (M2022, 2026-11-22; local CSVs in `C:\Projects\M2022\_DL-SURVEY\2026-11\`, not committed)

| Fact | Number | Design consequence |
|---|---|---|
| Datasets | TTable 443, TQuery 240, TFDMemTable 209 | DFM read must handle BDE TTable / TQuery (M2022 is still Paradox), not only FireDAC |
| Persistent fields by kind | data ~26.1k, calc 1,115, lookup 382, aggregate 0 | calc is the main non-data kind; aggregate stays a stored kind with no generator priority |
| Lookups | 382, ALL single-key; 376 use key `ID`; 6 non-PK keys (look intentional) | multi-field lookup keys not needed now; non-PK key = WARNING (FR-5) |
| Events | OnCalcFields 164, field OnGetText 163, column OnGetDisplayText 54, view OnCustomDrawCell 49, column OnCustomDrawCell 6 | store exactly these five first (TT-Q20 C answered by data); TField OnGetText is a FIELD event, not a grid event |
| Grid views | cxGrid DBTableView 170, DBBandedTableView 3, TableView 2, DBLayoutView 2, CardView 1, TreeList 15 | DBTable is the default layout (FR-4); others go to the layout-event table |
| Unbound grid columns | 55 grid (42 DBColumn, 11 TcxGridColumn, 2 banded) + 24 TreeList | graphical-candidate count for the 1.54 DFM read |

## 2. Final rulings

| Topic | Ruling | Source |
|---|---|---|
| publish-fb | DROPPED; the read-only server-side replacement for FIB$ is GENERATED CODE (section 7) | FU-4 |
| Registry-constant unit | ONE unit shared by SERVER and CLIENT, in a shared folder (e.g. `ORM3\COMMON`); exact path chosen at first generation, `--output` until then | FR-1 |
| Schema facts home | the FIELD REPOSITORY (section 1.1); not the index DB | FR-3 (supersedes FU-1 / Q02) |
| Schema sources | live Firebird AND DDL scripts, all constraint kinds | Q01 A |
| Refresh | manual only; DB -> repository adds new fields, deletes vanished ones only after confirmation | Q03 A, FR-3 |
| Sync model | shared change-set model; CLI prints the diff, writes only with `--apply` (all, or `--select <file>`); IDE checkbox form; direction explicit on every call, NO default | FU-3 A |
| Confirm defaults | DFM -> repository: DFM wins; repository -> DFM: repository wins; lint reports only. Dialog: every change `old -> new`, all checked EXCEPT deletes from the repository (section 3); itemised log | FU-9, FR-3 |
| Silencing | `DL_EXCEPTIONS` table in the repository; the linter reads it | FU-10 A |
| Columns | keep all six low-use columns; ISCALCULATED folds into FIELD_KIND | FU-5 A, Q09 A |
| Field kinds | data / calc / lookup / internal-calc / aggregate / graphical rows in DL_FIELDS_INFO | Q10 B, FU-6 |
| Per-dataset selection | NO repository table: the DFM's persistent fields ARE the selection (rename-proof). The dialog pre-selects from the DFM and writes back by adding / removing persistent fields; calc auto-adds its data fields, never auto-removes | FR-2, FU-6 |
| Graphical / layout code | a graphical column belongs to a grid layout TYPE. DBTable layout code lives on the per-table field row (the row claims the field); other layout types (Banded, Layout, Card, TreeList, ...) keep event code in `DL_LAYOUT_EVENTS` | FR-4 |
| Lookup wiring | repository table + field names; default PK preferred; non-PK key = warning | Q11 A, FR-5 |
| Calc bodies | Pascal text plus `{{FIELD}}` macros -> persistent field with typed accessor; refuse on a cycle, warn at save | Q12 A, Q13 A |
| Volatile regions | marker `DLFR`; whole-unit migration on regeneration; hg is the backup; warn on a hand-edited region | FU-7 A, Q14 |
| DFM read | menu `Field Repository` with several items; ONLY the selected dataset (+ batch for a form) | Q15 |
| DFM write | OTA apply to the open form; change set computed by a lane-testable engine; all-kinds fixture + click-level owner steps | FU-11, Q17 B |
| Grids | cxGrid DBTable view first | Q18 A, survey |
| MAXLEN constants | per iTABLE unit, region `DLFR 2a` after section 2; drift = repository vs code | FU-12 A |
| Golden test | FU-13 C | FU-13 |
| DB change | on-demand PER-TABLE change, refused-change detection, replaceable hook; full regeneration later | FU-2 |
| Schema lint | all five rules eventually, ON by default; 1.53 ships rules 1+2, silent without a repository | Q23 D, FU-14 |
| Local naming match (`tDIMABBR` -> DIMABBR) | 1.54, opt-in rule option, OFF by default | FR-6 |
| Survey output | `C:\Projects\M2022\_DL-SURVEY\<yyyy-mm>\`, local only, never committed | FR-7 |
| Slicing | 1.53: schema facts in the repository + rules 1+2, repository model, generator (survey done). 1.54: DFM read/write + dialogs + OTA, per-table ALTER + hooks, golden port. Overflow -> 1.55 | FU-14 A, Q25 |
| Retirement | after every real entry is covered plus one week of parallel use | Q24 A |

## 3. The change-set model (engine 1.53 in FR-MODEL; producers / UIs 1.53-1.54)

Unit `DRagLint.FieldRepo.ChangeSet`:

```pascal
TFrChangeOp = (fcoInsert, fcoUpdate, fcoDelete);
TFrDirection = (fdDbToRepo, fdRepoToDb, fdDfmToRepo, fdRepoToDfm);
TFrChange = record
  Id: Integer;            // 1-based, stable within one change set; what --select names
  Op: TFrChangeOp;
  Target: string;         // 'DL_FIELDS_INFO MSCLIST|DIMNAME', 'uOrders.dfm qryOrdersQTY', 'MSCLIST.DIMABBR'
  Prop: string;           // column / DFM property; '' for a whole-row insert/delete
  OldValue, NewValue: string;
  Checked: Boolean;       // default: True, except fcoDelete with direction fdDbToRepo (FR-3 "after confirmation")
  Blocked: string;        // non-empty = cannot be applied (e.g. Firebird refuses); never checked
end;
```

* Text: `[<id>] <op> <target> <prop>: <old> -> <new>` (+ `  BLOCKED: <reason>`, `  (unchecked)`); header
  `direction <dir>, <n> changes, <b> blocked, <u> unchecked`. `--json` mirrors the record.
* `--apply` applies the CHECKED changes; `--select <file>` replaces the default checks (ids one per line, or
  `all`; `#` comments; unknown id = exit 2, nothing applied). `all` still never selects a blocked change.
* Every apply logs `replacing <old> with <new>` per applied change. Direction is a REQUIRED argument.

## 4. Repository model v2 (1.53, lane FR-MODEL)

### 4.1 FIELD_KIND values (existing column DL_FIELDS_INFO.FIELD_KIND, SMALLINT)

Live data (MICRONITEV6A): 1 = 2046 rows, 2 = 3 rows (all ISCALCULATED), NULL = 68. TableTools writes 1 for a real
column, i.e. `Ord(TFieldKind) + 1`; v2 keeps that and adds one DL value:

| Code | Kind | Meaning | TField |
|---|---|---|---|
| NULL / 1 | data | real table column | fkData |
| 2 | calc | body in CALC_BODY | fkCalculated |
| 3 | lookup | wiring in DESTTABLE / SOURCEKEY / DESTKEY / DESTVALUE | fkLookup |
| 4 | internal-calc | generated like calc | fkInternalCalc |
| 5 | aggregate | expression in CALC_BODY (0 in M2022: stored, no generator priority) | fkAggregate |
| 10 | graphical | no data field; a grid column drawn by events; DBTable code on this row (4.3) | none |

Consistency (`repo check`): ISCALCULATED = (kind in 2, 4); ISLOOKUP = (kind = 3). Migration sets FIELD_KIND = 2
where ISCALCULATED and FIELD_KIND is NULL/1. `CleanOrphanFields` skips rows whose kind is not NULL/1; an orphaned
data row keeps today's behaviour (ISCALCULATED = True) and gets FIELD_KIND 2.

### 4.2 Lookup wiring (reuses the four zero-row columns)

SOURCEKEY = key field in THIS table (`KeyFields`); DESTTABLE = lookup table; DESTKEY = key in the lookup table
(`LookupKeyFields`; empty = its PK); DESTVALUE = `LookupResultField`. Single field only (all 382 M2022 lookups are
single-key). The lookup dataset component is resolved on apply (1.54), not stored.

### 4.3 New DL_FIELDS_INFO columns (TEXT, nullable, appended LAST in this order)

| Column | Holds |
|---|---|
| CALC_BODY | Pascal statements for kinds 2 / 4, aggregate expression for kind 5 |
| ONGETTEXT_BODY | TField.OnGetText handler body (field event, any kind; 163 in M2022) |
| GRID_DISPLAYTEXT_BODY | DBTable-layout column OnGetDisplayText body (FR-4: DBTable code on the field row) |
| GRID_DRAWCELL_BODY | DBTable-layout column OnCustomDrawCell body |

Macros `{{FIELD}}` name a field of the SAME table; `{{TABLE.FIELD}}` is reserved (error); no escapes in 1.53.
Dependencies of a calc field = every macro except the assignment target (the macro left of the first `:=` of a
statement): pure `CalcDependencies(pBody, pSelf)`. Column NAMES above are provisional: if the running FR-MODEL lane
already chose other names for the same content, its names win and this table is updated at INT.

### 4.4 Per-dataset selection: no table (FR-2)

The selection is the set of persistent fields in the DFM. FR-MODEL keeps only the PURE rule unit
`DRagLint.FieldRepo.FieldUse` (`ExpandSelection(pSelected, pAllFieldsOfTable): TArray<string>`) used by the 1.54
dialog: S1 selecting a calc / internal-calc / aggregate field adds its dependencies transitively; S2 unselecting
never removes another field; S3 idempotent; S5 unknown field = error. Open point (section 12): datasets built at
run time with no DFM have no persistent fields to hold a selection.

### 4.5 New table DL_LAYOUT_EVENTS (FR-4: non-DBTable layouts, and view-level events)

| # | Column | Type | Null | Note |
|---|---|---|---|---|
| 0 | TABLE_NAME | VARCHAR(68) | N, pk1 | |
| 1 | FIELD_NAME | VARCHAR(68) | N, pk2 | '' = view-level event (e.g. view OnCustomDrawCell, 49 in M2022) |
| 2 | LAYOUT_TYPE | VARCHAR(20) | N, pk3 | `DBBanded`, `DBLayout`, `Card`, `TreeList`, `Table`, ... ; `DBTable` only when FIELD_NAME = '' |
| 3 | EVENT_NAME | VARCHAR(63) | N, pk4 | `OnCustomDrawCell`, `OnGetDisplayText`, ... |
| 4 | BODY | TEXT | N | Pascal text with macros |

Lookup order for a column event: layout DBTable -> the field row's GRID_* column; any other layout -> this table.
A non-'' FIELD_NAME must exist in DL_FIELDS_INFO for TABLE_NAME (`repo check`).

### 4.6 New table DL_EXCEPTIONS (FU-10)

PK (RULE_ID, DATASET_KEY, TABLE_NAME, FIELD_NAME, PROP), all VARCHAR NOT NULL default '' except RULE_ID; REASON
VARCHAR(220) NOT NULL. Empty key = wildcard; `*` rule = any rule. Pure `IsExcepted` in `DRagLint.FieldRepo.Exceptions`.

### 4.7 Schema version 2, migration, text backup, check

* `REPO_SCHEMA_VERSION = 2`; open accepts 1 and 2 and validates that version's table set. v2 is UNRELEASED until
  1.53 ships, so FR-SCHEMA (section 5) AMENDS v2 after FR-MODEL merges instead of adding a v3.
* `repo migrate [--apply]`: dry run changes no byte; apply writes `<repo>.before-migrate-<ts>.txt` first, one
  transaction; on v2 prints `already at schema 2`. Nothing dropped or renamed.
* Text backup: v2 -> `#DLREPO 2`; v1 -> `#DLREPO 1` byte-identical to today. `#DLREPO 1` into v2 accepted;
  `#DLREPO 2` into v1 refused (exit 2, "migrate first"); restore into a missing file creates the file's version.
* `repo check [--json]` (read-only): kind consistency, lookup wiring complete, non-PK lookup key = WARNING (FR-5),
  macro targets exist, calc CYCLE named `A -> B -> A`, DL_LAYOUT_EVENTS field rows exist. Exit 0 clean, 1 errors
  (warnings alone exit 0).

## 5. Schema facts in the repository (1.53, lane FR-SCHEMA; amends v2)

New repository tables (all schema-derived, written only by the DB -> repository change set):

| Table | PK | Columns |
|---|---|---|
| DL_DOMAINS | DOMAIN_NAME | FIELD_TYPE, FIELD_SUBTYPE, FIELD_LENGTH, CHAR_LENGTH, FIELD_SCALE, FIELD_PRECISION, NULL_FLAG, DEFAULT_SOURCE, CHECK_SOURCE, CHARSET |
| DL_CONSTRAINTS | CONSTRAINT_NAME | TABLE_NAME, KIND (`PK`, `UNIQUE`, `FK`, `CHECK`), REF_TABLE, REF_CONSTRAINT, UPDATE_RULE, DELETE_RULE |
| DL_CONSTRAINT_COLUMNS | (CONSTRAINT_NAME, POSITION) | COLUMN_NAME |
| DL_GENERATORS | GENERATOR_NAME | (no current value: it changes on every insert and would make the backup volatile) |

DL_FIELDS_INFO gains schema-derived `DOMAIN_NAME` and `CHAR_LENGTH` (appended after the 4.3 columns). DL_META gains
`schema_read_at_utc`, `schema_source` (`live` / `ddl`), `schema_database` (Database value only, never a password).

* `repo refresh-schema` becomes a change-set producer, direction `db-to-repo`: new tables / fields / domains /
  constraints = inserts (checked); changed schema-derived values = updates (checked); vanished ones = deletes
  (UNCHECKED, applied only when selected -- FR-3 "delete after confirmation"). Hand-kept columns are never in the
  set. `--dry-run` = no `--apply`. Sources: `--connection` (live, read-only transaction over RDB$FIELDS,
  RDB$RELATION_FIELDS, RDB$RELATION_CONSTRAINTS, RDB$INDEX_SEGMENTS, RDB$REF_CONSTRAINTS, RDB$GENERATORS) or
  `--ddl <file.sql>[;...]` (offline subset parser: CREATE DOMAIN / TABLE / GENERATOR / SEQUENCE, ALTER TABLE ADD
  [CONSTRAINT], CREATE INDEX ignored, SET TERM blocks skipped, unknown statements counted + listed, never fatal).
* `repo seed-fb` on an empty repository = the same producer with every change checked.
* Read API for lint and generators: `DRagLint.FieldRepo.SchemaFacts` -- `HasSchema`, `SchemaInfo` (utc, source),
  `ColumnCharLength(pTable, pColumn)` (field CHAR_LENGTH, else its domain's, else -1), `PrimaryKey(pTable)`.

## 6. Schema-aware lint, rules 1 + 2 (1.53, lane FR-LINT)

Both ON by default (Q23 D). Repository found by section 1.2; none, or a repository without schema facts ->
SILENT (no findings, one `schema rules: no field repository` note in verbose mode only). When they run, lint prints
once: `schema facts <utc> (<source>) from <repo file name>` (Q03 A). DL_EXCEPTIONS suppress findings.

| Id | Severity | Fires when |
|---|---|---|
| `schema-maxlen-drift` (rule 1) | warning | a constant `<TABLE>_<FIELD>_MAXLEN` (case-insensitive; `$` written `_`) whose column is known has a value different from its char length; or a string LITERAL longer than the char length assigned to a resolved column target |
| `schema-length-bound` (rule 2) | warning | `Copy(x, i, N)` assigned to a resolved target, `.Size := N` / `MaxLength := N` on a resolved field, or a DFM `TStringField` / `TWideStringField` persistent field whose `Size` differs, where N (literal or a constant the index resolves) > char length (DFM: <>) |

Target resolution (conservative; unresolved = silent): (1) ORM fields / properties linked by `link-orm`; (2) DFM
persistent field = dataset name + field name, dataset table from `UpdateOptions.UpdateTableName`, `TableName`, or an
ORM link naming exactly one known table; (3) `FieldByName('<Y>')` on such a dataset. Local `t<FIELD>` / `fld<FIELD>`
naming is NOT resolved (FR-6: 1.54, opt-in, off by default). Rules 3-5 are 1.54+. Default-on frame guard 356 -> 358.

## 7. Registry-constant generator (1.53, lane FR-CONSTGEN)

Purpose (FU-4, FR-1): the read-only replacement for the FIB$ tables, ONE unit shared by SERVER and CLIENT.

`drag-lint repo gen-const (--repo|--project) --unit <UnitName> --output <file.pas> [--table DL_X,...]
[--datamodule <Name>] [--dry-run]`

`drag-lint repo check-const (--repo|--project) --unit-file <file.pas>` (FR-PRELOAD)

* Default tables: DL_FIELDS_INFO, DL_DATASETS_INFO, DL_ENUMVALUES, DL_ERROR_MESSAGES; never DL_META, DL_EXCEPTIONS,
  DL_LAYOUT_EVENTS or the section 5 schema tables. Generic over `RepoTables`, so v1 and v2 both work.
* Per table: record `T<Table>Row`, `<Col>IsNull` companion only for columns holding a NULL,
  `const <TABLE>_ROWS: array[0..N-1] of T<Table>Row` in PK order; ASCII-escaped literals in `+`-joined pieces of
  <= 200 characters, no line over 250.
* Pre-filled mem tables (owner ruling 2026-11-22, lane FR-PRELOAD; replaces `--memtable` / `Fill<Table>`):
  `--datamodule <Name>` writes `<unit>.pas` + text `.dfm` instead of the constant unit; one read-only `TFDMemTable` per
  table, FIB$ names / types / sizes, rows in the FireDAC binary `Content` property, no fill code. A separate call, not
  part of the constant unit, because a reader needs one or the other and the rows must not be linked twice. Measured
  on 2,229 real rows (median of 30 fresh Release processes, Win32 / Win64): const + Fill 31.7 / 35.9 ms, tuned Fill
  21.8 / 23.9 ms, data module 12.7 / 12.3 ms, const lookup 0.3 / 0.4 ms.
* Repository mark: SHA-256 per table over its column layout and canonical backup text, one hash over all, in the
  header AND as `REPO_CONTENT_HASH`; the data module also carries the hash of its `.dfm`. `repo check-const`: exit 0
  current, 1 stale naming the tables, 2 error. A sub-verb of its own, not part of `repo check`: that one judges the
  repository alone and needs no generated file, and a pre-build step must tell "stale" (1) from "cannot tell" (2).
* 7-bit ASCII, CRLF, deterministic, DocInsight on every public symbol, lint-clean. Target path: a shared folder
  (e.g. `ORM3\COMMON`) chosen at first generation; until then only `--output` (no default path into ORM3).

## 8. Survey (DONE 2026-11-22; no 1.53 lane)

The M2022 survey ran as ad-hoc read-only SQL over the index (22 CSVs, local, section 1.3). A repeatable
`dfm-survey` verb is NOT built: the 1.54 DFM reader (section 9) reads the same `dfm_objects` / `dfm_properties`
rows per dataset, and a batch "read all datasets, dry run" over a project gives the same counts as a change-set
summary. Re-surveys before that use the saved SQL (keep it beside the CSVs; owner-local).

## 9. 1.54 designs (outline -- planned after the 1.53 lanes land)

* DFM read (`Field Repository > Read Fields from Dataset...`, `... All Datasets of Form...`, CLI `repo read-dfm
  --dfm <file> [--dataset <name>] --direction dfm-to-repo`): change set; all kinds, lookup props, field events,
  calc handler text -> CALC_BODY with macros; BDE TTable / TQuery as well as FireDAC (survey).
* Field-selection dialog per dataset (FR-2): lists every field of the table with its kind; pre-checked = the
  DFM's persistent fields; select all / unselect all; `ExpandSelection` (4.4); OK produces a repo -> DFM change
  set adding / removing persistent fields.
* Repository -> DFM: engine over DFM TEXT (byte-tested, dry run) + OTA adapter applying the same set to the OPEN form;
  all-kinds fixture form (data, calc, lookup, aggregate, graphical DBTable column, a TreeList graphical column).
* Handler generation in `DLFR` volatile regions; first insert at the END of an existing handler; hash in the region
  header detects hand edits. `DB-RAD n` -> `DLFR n` per whole unit on regeneration; `DLFR 2a` = MAXLEN region.
* Golden test port (FU-13 C); `tests\fieldrepo\ormgen-golden-known-drift.txt` becomes the exception file.
* Per-table ALTER (`repo alter-table --table T --direction repo-to-db --connection ...`): refused changes detected
  before executing (VARCHAR shrink, string -> numeric, type change on a column with RDB$DEPENDENCIES / constraints /
  indices / computed-by) -> BLOCKED, or on selection the safe path (pre-scan overflow / failed casts, ADD c_NEW,
  UPDATE with CAST, DROP c, ALTER c_NEW TO c, ALTER POSITION, one transaction, verify). `IFrDbProvider` (Firebird +
  InterBase testable) and replaceable `IFrSchemaHook`; the Micronite hook in its own unit.
* Opt-in local naming match for rule 2 (FR-6). FIB$ reader inventory (switch ORM3 readers to the shared unit).
* Full DB regeneration (DDL + initial data + legacy Paradox load + FKs last): separate later task.

## 10. 1.53 lanes, dependencies, shared files

| Lane | Starts | Own units | Shared files (ONE `hub:` commit each; INT unions) |
|---|---|---|---|
| FR-MODEL | running | `.Kinds`, `.FieldUse` (pure), `.Exceptions`, `.Check`, `.Migrate`, `.ChangeSet`, `CLI.RepoModel` | `FieldRepo.Schema`, `.TextBackup`, `.SchemaSeed` (owned), `CLI.Repo`, dpr/dproj |
| FR-SCHEMA | after FR-MODEL merges | `.SchemaFacts`, `.FbSchemaRead`, `.FbDdl`, `.Locate` | `FieldRepo.Schema`, `.TextBackup`, `.SchemaSeed`, `CLI.Repo` (refresh-schema), `CLI.pas` (`--ddl`, `resolve-dbs` repo line), dpr/dproj |
| FR-LINT | after FR-SCHEMA's first commit (frozen `SchemaFacts` + `Locate` API) | `src\lint\DRagLint.Lint.SchemaRules.pas` | `Lint.RuleCatalog`, lint dispatch in `CLI.pas`, frame-guard counts |
| FR-CONSTGEN | any time | `.ConstGen`, `CLI.RepoConstGen` | `CLI.Repo`, dpr/dproj |

No lane bumps DRAGLINT_VERSION / extractor / resolver. Registry entries: `field-repository` (MODEL, SCHEMA,
CONSTGEN), new `schema-lint` (LINT); each runs `featuregen verify --id <id> --by ENGINE`.

## 11. What is superseded and why

| Item | Fate |
|---|---|
| `repo publish-fb`, plans `tt-publish-fb`, `tt-publish-ui` | DROPPED (FU-4) |
| Column triage, `DL_COLUMN_FATE`, plan `tt-column-triage` | DROPPED (FU-5); its v1/v2 rules reused in 4.7 |
| FIB$ reader inventory, plan `tt-fib-removal` | DEFERRED to 1.54 |
| Marker DL / DLTT | DLFR (FU-7) |
| Schema cache in the index DB (FU-1, rev 1 of this spec) | REPLACED by schema facts in the repository (FR-3) |
| DL_DATASET_FIELD_USE (rev 1 of this spec) | DROPPED: the DFM's persistent fields are the selection (FR-2) |
| `dfm-survey` verb, plan `fr-survey` (rev 1) | DROPPED: survey done ad hoc (section 8) |

## 12. Open questions for the owner

1. **Datasets built in code.** Some datasets get their fields at run time (no DFM, no persistent fields), so there
   is nothing to hold their field selection (FR-2). Should DL (a) leave them out of the selection dialog, (b) treat
   the code that creates the fields as the selection (DL edits that code later), or (c) keep a small selection list
   in the repository only for such datasets?
2. **Deleting vanished fields.** When Firebird no longer has a column, the refresh lists a delete that is NOT
   pre-checked (you must tick it). Are hand-kept facts on that row (caption, calc code) to be deleted with it, or
   kept as an orphan you can reuse if the column comes back?
3. **Manifest key.** Lint finds the repository through `fieldRepository` in the project's
   `drag-lint-project.json`, or the same key on the project's section of `drag-lint.json`. For Micronite all three
   projects would point at one file under SERVER's `_DL-REPO`. Is SERVER the right owner folder, or should the
   repository sit in a neutral shared folder (like the library under `C:\Projects\.drag-lint\`)?
