# Read a form into the field repository

```
drag-lint repo read-dfm --dfm <file.dfm>[;...] [--dataset <Name>] --direction dfm-to-repo (--repo | --project)
                        [--apply | --select <id file>] [--dry-run] [--json]
```

Reads the datasets of a form (one with `--dataset`, all without) and prints the change set that brings the repository
in line with their persistent fields. Nothing is written without `--apply` or `--select`; the form and its unit are
never written. The direction is required, there is no default. The repository must be schema 4 or later (`repo migrate --apply`); the editor of a grid column needs schema 5; `repo gen-handlers` needs schema 4 too.

| What | Where it goes |
|---|---|
| FieldKind (or the old `Calculated` / `Lookup` properties) | `FIELD_KIND`, with `ISCALCULATED` / `ISLOOKUP` |
| DisplayLabel, Visible, DisplayFormat, EditFormat, DisplayWidth, Alignment | the column of that name, only when the DFM states the property |
| field class, Size | `FIELD_AS_TYPE`, `VAR_TYPE`, `STRING_SIZE`, for a NEW row only (the schema owns them afterwards) |
| KeyFields, LookupDataSet, LookupKeyFields, LookupResultField | `SOURCEKEY`, `DESTTABLE` (the table of the lookup dataset, also in a data module of the same folder), `DESTKEY`, `DESTVALUE`, as columns (a SELECT alias is followed; a computed result is BLOCKED); a key that is not the primary key is a warning |
| TAggregateField.Expression | `CALC_BODY` |
| OnCalcFields | `CALC_BODY` of each calc / internal-calc field, see below |
| OnGetText, OnSetText, OnValidate, OnChange | `ONGETTEXT_BODY`, `ONSETTEXT_BODY`, `ONVALIDATE_BODY`, `ONCHANGE_BODY` of the field row |
| column events of a TcxGridDBTableView: OnGetDisplayText, OnCustomDrawCell | `GRID_DISPLAYTEXT_BODY`, `GRID_DRAWCELL_BODY` of the row of the column's field; of an unbound column, a banded view or a field without a row: listed, not stored |
| columns of every TcxGridDBTableView and TcxGridDBBandedTableView | `DL_GRID_COLUMNS`, see below |
| PropertiesClassName and the `Properties.*` lines of such a column (1.56) | `PROPERTIES_CLASS_NAME`, `PROPERTIES` of its `DL_GRID_COLUMNS` row, see below |

**The table of a dataset** is `UpdateOptions.UpdateTableName`, else `TableName` (`Tools.DB` is `TOOLS`), else the one
table of its SELECT. A data field of a SELECT belongs to the column its select-list item names, or to the one its
`Origin` property names when that table is in the FROM (`"X.DB".COL`, `ALIAS."X.DB".COL`, `X.DB.COL`, a bare `COL`).
When the select list and the Origin name different columns, the field is reported as a `conflict` and gets no table:
nothing is picked. Everything else is reported as `UNRESOLVED` or `no table column` and gives no change: UNION, derived
tables, TFDMemTable without a table, computed items, fields that are only overridden in an inherited form.
A link source, a lookup dataset and a grid's dataset of an inherited module are read from the ancestor's DFM,
see [Datasets of an inherited form or data module](repo-read-dfm-ancestor).

**Joins (1.54.1).** A SELECT over several tables is `JOIN T1 T2 ...`, not unresolved: every field gets its own table.

| Field | Its table |
|---|---|
| data | the select-list item (`O.Qty AS OQ` is `ORDERS.QTY`); a repeated column without alias is `NAME_1`, `NAME_2` in list order; an unqualified column or a `*` over several tables: the one FROM table whose schema facts have it, or the Origin |
| lookup | the one table of its KeyFields; `SOURCEKEY` is the key field's column there |
| calc / internal-calc | the one table of every table field its calc code reads, also through other calc fields (a cycle is no error); the condition of an `if` whose branches only assign other fields is not counted |
| event code (OnGetText, ...) | stored only when every field it reads is of the field's own table; otherwise BLOCKED |

A field without a table is listed as `  no table: <field>: <why>` (computed by the SQL, `ID is in 2 tables of the FROM`,
no schema facts, `the calc code reads 2 tables: A B`, `the calc code reads X, which has no table`, no calc code,
the key fields come from two tables). A summary line `joins: N datasets; C calc, L lookup, D data fields with a table;
W without` follows `calc bodies:`; `--json` has `join`, `noTable` per dataset and `totals.joins`. Memory tables filled
in code by field copies are not placed yet (bulk copies and links: below). Design:
`docs/superpowers/specs/2026-11-26-join-field-origin-design.md`.

**Calc fields over several tables (1.55).** A join calc field whose code reads fields of several tables belongs to ONE
of them, the **child end**: the one table from which every other one it reads is reached going UP the relation graph
(`repo paths`: FKs onto a PK / UNIQUE, plus stored FORM / HAND relations). `IPCHART` + `MSCLIST` -> `IPCHART`. The other
tables become input aliases, named like the table (`MSCLIST`, ruling XQ2), and the body is stored with
`{{MSCLIST.DECIMALS}}` for their fields. Each alias gets a `DL_FIELD_INPUTS` row of the default binding with the path the
form's own SQL uses: the equalities of its `ON` conditions and the `WHERE` equalities between two FROM tables (a condition
with a top-level `OR` gives none), matched column for column to the relations; else the stored binding, the IS_DEFAULT
relations, or the only path. The FK steps of a path get their `DL_RELATIONS` row (checked) when a binding first uses
them. A join on a parent key that matches no FK is **offered** as a FORM relation `CHILD_PARENT` (unchecked: choosing it
confirms it, ruling XQ6); a field whose input goes through an offer is unchecked too, so its alias is never undeclared.
Not placed, with the reason: `no table of A B reaches all the others`, `A B each reach all the others (a 1:1 pair)`, `X is
in the FROM 2 times`, `home A; 2 paths to B, none chosen (asked once)`. The summary line is `cross-table calc: P placed,
U unresolved; I inputs; relations: F FK used, O offered`; `--json` has `totals.crossTable`.

**Memory tables (1.55).** A dataset with no table and no SQL takes the source of a link: the kbmMemTable `AttachedTo`
property of the DFM, or a literal call in its unit: `T.AttachTable(S)`, `T.CloneCursor(S, ...)`, `T.CopyDataSet(S, ...)`,
`T.CopyData(S)`, `T.AppendData(S)`, `T.Data := S.Data` (receiver and source a name, `Self.X` or `module.X`; a comment in
the argument is skipped; arrays, locals and FindComponent are not followed). Links are followed transitively: `memB ->
IPCHART (via AttachedTo memA > AttachedTo tblChart)`; a source that is a join makes the memory table that join. A cycle,
two different sources (`linked to 2 sources: ...`) or a source that is no dataset of the form or of a module beside it is
UNRESOLVED. After a COPY (CopyDataSet, CopyData, AppendData, `Data :=`) a data field the unit also writes keeps no table
(`no table: written in code after the copy (Unit.pas:51)`). The summary line is `links: N datasets got a source:
AttachedTo a, CopyDataSet c, ...; M unresolved`; `--json` has `via` per dataset and `totals.links`.

Measured 2026-11-26 on M2022 (182 DFMs, the schema facts of a production schema copy): unresolved datasets 245 -> 185; 99 calc
fields over several tables placed with a home and every binding, 11 not (4 with two paths and no form join, 1 with no
child end, 1 1:1 pair, 5 reading a field without a table); 94 inputs, 11 FK relations used, 9 FORM relations offered;
60 memory tables got a source (CopyDataSet 59, CloneCursor 1), 33 links did not (22 of them name a dataset of an inherited
data module's ancestor). On Micronite2027 (ORM3 CLIENT, 119 DFMs): 99 -> 96 unresolved, no calc over several tables, 3
CopyDataSet links: its memory tables are filled through the pipe.

**Calc code.** One OnCalcFields handler computes many fields. The body of a field is the part of the handler it needs:
the statements that assign it, the local variables they read (declared inline) and every earlier statement with another
effect. Assignments to the other calculated fields are cut out, except one that also moves a dataset (`Locate`, `FindKey`, ...). `if C then Exit;` at the top level becomes
`if not (C) then begin ... end;`. A persistent field becomes
`{{FIELD}}`: the macro names the field COMPONENT and the code keeps its member, so `tblQTY.IsNull` is `{{QTY}}.IsNull` and
`tblTOTAL.Value := ...` is `{{TOTAL}}.Value := ...`. `DataSet.FieldByName('QTY').AsInteger` is `{{QTY}}.AsInteger`; `DataSet['QTY']` and
`FieldByName('QTY').Value` are Variants: `{{QTY}}.AsVariant`. The change is BLOCKED, with its text, for a field that is not a field of
the dataset's table or has no persistent field, the component of a CALCULATED field handed to other code (that code may
write it), `with`, any other `Exit`, compiler directives, nested routines, a literal `{{`, a local only a left-out
statement may set, a calculated field that changes after the code read it. Functions called in a left-out expression are not checked for other side effects. Code that names other components of the form is stored with a warning.

**Event code** is the whole handler, with the same macros; renamed parameters get the standard names (`Sender`, `Text`, `DisplayText`;
`Sender`, `ARecord`, `AText`; `Sender`, `ACanvas`, `AViewInfo`, `ADone`). A field's component as a whole (`Sender = tblQTY`) is allowed.
Code in a grid column event of a dataset on ANOTHER form keeps its `dmX.tblQTY` as written.

**Generated code is not read back.** The text of a [DLFR region](field-repository-handlers) came from the repository. A calc
field whose code is in a region of the handler, and an event handler that holds a region, give a warning and no change, hand
code beside the region included; the other fields of an OnCalcFields handler are read as usual.

**Grid columns.** One `DL_GRID_COLUMNS` row per form + grid view + column component: the table and field behind it and its
0-based `COLUMN_INDEX` (the order of the columns in the DFM, a stated `Index` applied as at load, for a banded view too; band positions are not stored). An unbound
(drawn) column has no table and no field. A column of a join, a computed SELECT item or an unknown data source keeps its
DataBinding.FieldName without a table. Card, layout and other views, inherited views and columns without a name are listed,
not stored. A stored column that is gone from a form that was read completely is an UNCHECKED delete; `--dataset` limits the read to
the views of that dataset and proposes no delete. The key is the form NAME: two projects that share a repository and have
two forms of one name share its rows.

**Column editors (1.56).** The row also holds the column's in-place editor: `PROPERTIES_CLASS_NAME` is its
`PropertiesClassName`, `PROPERTIES` its `Properties.*` lines as the form has them (a collection, a string list and a
continued string whole; CRLF between lines, the indentation of the first line removed). A changed editor is one checked
update per value; a schema-4 repository gets a warning instead and stores the columns without it. Details:
[grid column editors](grid-column-editors).

**Hand-kept values.** A column the DFM does not state is kept. A value the DFM states differently is a checked change
(`old -> new`): the DFM wins when you apply, so read the dry run first. A body or lookup wiring of a field that stays a
data field is unchecked. An apply is one transaction.

**Conflicts.** Two datasets that state different values for one column give one UNCHECKED change per value; pick one
with `--select`. A calc field that shadows a real column, a data field the schema facts do not have, and a value longer
than its column are BLOCKED. A read never deletes a field: the persistent fields of a DFM are only that dataset's selection.
An Alignment the DFM does not state is the default of the field type: NULL in a new row (0 left, 1 right, 2 center).

With `--dataset`, `--json` also lists the persistent fields and the repository fields of the table: the [field selection in the IDE](field-repository-forms) reads them.
