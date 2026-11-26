# Read a form into the field repository

```
drag-lint repo read-dfm --dfm <file.dfm>[;...] [--dataset <Name>] --direction dfm-to-repo (--repo | --project)
                        [--apply | --select <id file>] [--dry-run] [--json]
```

Reads the datasets of a form (one with `--dataset`, all without) and prints the change set that brings the repository
in line with their persistent fields. Nothing is written without `--apply` or `--select`; the form and its unit are
never written. The direction is required, there is no default. The repository must be schema 3 or later (`repo migrate --apply`).

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

**The table of a dataset** is `UpdateOptions.UpdateTableName`, else `TableName` (`Tools.DB` is `TOOLS`), else the one
table of its SELECT. A data field of a SELECT belongs to the column its select-list item names, or to the one its
`Origin` property names when that table is in the FROM (`"X.DB".COL`, `ALIAS."X.DB".COL`, `X.DB.COL`, a bare `COL`).
When the select list and the Origin name different columns, the field is reported as a `conflict` and gets no table:
nothing is picked. Everything else is reported as `UNRESOLVED` or `no table column` and gives no change: UNION, derived
tables, TFDMemTable without a table, computed items, fields that are only overridden in an inherited form.

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
in code (bulk copies, field copies) and calc fields over several tables are not placed yet. Design:
`docs/superpowers/specs/2026-11-26-join-field-origin-design.md`.

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

**Hand-kept values.** A column the DFM does not state is kept. A value the DFM states differently is a checked change
(`old -> new`): the DFM wins when you apply, so read the dry run first. A body or lookup wiring of a field that stays a
data field is unchecked. An apply is one transaction.

**Conflicts.** Two datasets that state different values for one column give one UNCHECKED change per value; pick one
with `--select`. A calc field that shadows a real column, a data field the schema facts do not have, and a value longer
than its column are BLOCKED. A read never deletes a field: the persistent fields of a DFM are only that dataset's selection.
An Alignment the DFM does not state is the default of the field type: NULL in a new row (0 left, 1 right, 2 center).

With `--dataset`, `--json` also lists the persistent fields and the repository fields of the table: the [field selection in the IDE](field-repository-forms) reads them.
