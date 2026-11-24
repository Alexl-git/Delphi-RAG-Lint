# Field repository -- owner rulings 2026-11-23 evening (input for the v3 schema and the 1.54 lanes)

Amends `2026-11-22-field-repository-v2-design.md`. Status: rulings recorded, EVCOLS implemented (section below), ALTERBK not started.

| # | Topic | Ruling |
|---|---|---|
| R1 | read-dfm: joins and memtables | Not designed yet. Measure M2022 first: follow LoadFromDataSet / CopyDataSet and `memX.Value := qryY.Value` to the source SQL; below 100% coverage -> rediscuss. Report: `C:\TEMP\claude\lanes\v154\MEMSURVEY\REPORT.md` |
| R2 | Event bodies | One DL_FIELDS_INFO column per event: ONGETTEXT_BODY, ONSETTEXT_BODY, ONVALIDATE_BODY, ONCHANGE_BODY, GRID_DISPLAYTEXT_BODY, GRID_DRAWCELL_BODY. DL_LAYOUT_EVENTS keeps view-level (FIELD_NAME = '') and non-DBTable layouts only. Layout type `Field` goes away |
| R3 | Macro `{{FIELD}}` | Names the persistent field COMPONENT; the body writes the member (`{{F}}.AsFloat`, `{{F}}.IsNull`). Supersedes Q12 A (typed accessor). `{{TABLE.FIELD}}` stays an error. Fields of other datasets wait for R1's M2022 figures (realistic limits first) |
| R4 | Field events | OnValidate, OnChange, OnSetText stored and generated beside OnGetText |
| R5 | ALIGNMENT | Start fresh: NULL = default of the field type, 0/1/2 = Ord(TAlignment). Live MICRONITEV6A has only NULL (1020) and -2 (1097): import maps -2 to NULL. Check readers of -2 in the FIB$ report |
| R6 | Grid column order | One row per grid view per form: NEW table (form, view, column -> table, field, index). Supersedes FR-2 for this fact only. Table column positions: not stored |
| R7 | `alter-table --select all` | Everything except DROP COLUMN; a drop needs its own id |
| R8 | Widening with dependents | Allowed with a warning that lists the dependents (unchecked change); what Firebird itself refuses stays BLOCKED. Reduce / type change through a temporary column with data pre-verification plus recompile of dependents: parked to January / February 2027 |
| R9 | Backup | `--apply` makes the backup itself (Firebird service API). Default: restore test into a temporary database, compare table list and the row count of the altered table, delete the temporary database; space checked first; `--verify quick` skips the restore; a failed verification refuses the apply |
| R10 | Backup purge | `repo backup purge --keep N` = dry run, `--apply` deletes; only files in drag-lint's manifest, never the newest verified one; total size printed after each backup |
| R11 | FIB$ readers | One-off report, no verb |
| R12 | Micronite hook | unchanged (veto FIB$ tables + reminder) |

## Implemented by lane EVCOLS (schema 3, R2-R6)

* `REPO_SCHEMA_VERSION = 3`. DL_FIELDS_INFO: the six TEXT columns of R2, nullable, last, in the order of R2
  (`FR_EVENT_COLUMNS` in DRagLint.FieldRepo.Kinds is the one list of event, column, parameters). Columns of v2 unchanged.
* DL_GRID_COLUMNS (R6), PK (FORM_NAME, VIEW_NAME, COLUMN_NAME):

  | # | Column | Type | Null | Note |
  |---|---|---|---|---|
  | 0 | FORM_NAME | VARCHAR(128) | N, pk1 | name of the DFM's root object |
  | 1 | VIEW_NAME | VARCHAR(128) | N, pk2 | view component |
  | 2 | COLUMN_NAME | VARCHAR(128) | N, pk3 | column COMPONENT: unique in a form, so an unbound (graphical) column and two columns of one field are rows of their own |
  | 3 | TABLE_NAME | VARCHAR(68) | Y | NULL = unbound, or the dataset has no table |
  | 4 | FIELD_NAME | VARCHAR(68) | Y | NULL = unbound |
  | 5 | COLUMN_INDEX | INTEGER | N | 0-based position among the columns of the view in the DFM |

* Migration 1 -> 3 and 2 -> 3 in one transaction, old-schema text backup first: new columns and tables, ALIGNMENT -2 -> NULL,
  layout-type `Field` events moved into the columns (a row without field row or column stays; `repo check` names it).
* Text backup `#DLREPO 3`; v1 / v2 repositories write what they wrote; older backups restore into v3 row for row (no data change).
* Open details decided conservatively (owner may overrule):
  1. The grid key is the form NAME; two projects on one repository with equal form names share rows.
  2. Order is stored for TcxGridDBTableView and TcxGridDBBandedTableView (DFM order; band positions not stored); card, layout
     and tree views, VCL DBGrids, inherited and frame views are reported or ignored.
  3. A column gone from a form read completely is an UNCHECKED delete (fields are still never deleted by a read).
  4. Column events are stored for TcxGridDBTableView only; an event of a column whose field has no row makes no row.
  5. A field component as a whole is a macro too, except a calculated field's in OnCalcFields code (BLOCKED: the callee may write it).
     `DataSet['X']` and `FieldByName('X').Value` become `.AsVariant`.
  6. Handlers that hold a generated DLFR region are not read for the code in it; an event handler with a region is not read at all.
  7. A read of the own field behind a statement that assigned it is no cycle; an internal-calc field may read itself.
  8. read-dfm and gen-handlers refuse schema 1 and 2 ("run repo migrate").
  9. GRID_* bodies are stored, not generated (no generator asked for them yet).
