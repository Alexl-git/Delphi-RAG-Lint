# Read a form into the field repository

```
drag-lint repo read-dfm --dfm <file.dfm>[;...] [--dataset <Name>] --direction dfm-to-repo (--repo | --project)
                        [--apply | --select <id file>] [--dry-run] [--json]
```

Reads the datasets of a form (one with `--dataset`, all without) and prints the change set that brings the repository
in line with their persistent fields. Nothing is written without `--apply` or `--select`; the form and its unit are
never written. The direction is required, there is no default.

| What | Where it goes |
|---|---|
| FieldKind (or the old `Calculated` / `Lookup` properties) | `FIELD_KIND`, with `ISCALCULATED` / `ISLOOKUP` |
| DisplayLabel, Visible, DisplayFormat, EditFormat, DisplayWidth, Alignment | the column of that name, only when the DFM states the property |
| field class, Size | `FIELD_AS_TYPE`, `VAR_TYPE`, `STRING_SIZE`, for a NEW row only (the schema owns them afterwards) |
| KeyFields, LookupDataSet, LookupKeyFields, LookupResultField | `SOURCEKEY`, `DESTTABLE` (the table of the lookup dataset, also in a data module of the same folder), `DESTKEY`, `DESTVALUE`, as columns (a SELECT alias is followed; a computed result is BLOCKED); a key that is not the primary key is a warning |
| TAggregateField.Expression | `CALC_BODY` |
| OnCalcFields | `CALC_BODY` of each calc / internal-calc field, see below |
| OnGetText | `DL_LAYOUT_EVENTS`, layout type `Field`; other field events are listed, not stored |

**The table of a dataset** is `UpdateOptions.UpdateTableName`, else `TableName` (`Tools.DB` is `TOOLS`), else the one
table of its SELECT. A data field of a SELECT belongs to the column its select-list item names, or to the one its
`Origin` property names when that table is in the FROM. Everything else is reported as `UNRESOLVED` or
`no table column` and gives no change: joins (for calc and lookup fields), UNION, derived tables, TFDMemTable without a
table, computed items, fields that are only overridden in an inherited form.

**Calc code.** One OnCalcFields handler computes many fields. The body of a field is the part of the handler it needs:
the statements that assign it, the local variables they read (declared inline) and every earlier statement with another
effect. Assignments to the other calculated fields are cut out, except one that also moves a dataset (`Locate`, `FindKey`, ...). `if C then Exit;` at the top level becomes
`if not (C) then begin ... end;`. A persistent field becomes `{{FIELD}}` when the code uses `Value` or the typed
accessor of its class. The change is BLOCKED, with its text, when the code uses something a macro does not mean:
`IsNull`, another accessor, a Variant (`DataSet['X']` read), the component itself, `with`, any other `Exit`, compiler
directives, nested routines, a literal `{{`, a local only a left-out statement may set, a calculated field that
changes after the code read it. Functions called in a left-out expression are not checked for other side effects. Code that names other components of the form is stored with a warning.

**Hand-kept values.** A column the DFM does not state is kept. A value the DFM states differently is a checked change
(`old -> new`): the DFM wins when you apply, so read the dry run first. A body or lookup wiring of a field that stays a
data field is unchecked. An apply is one transaction.

**Conflicts.** Two datasets that state different values for one column give one UNCHECKED change per value; pick one
with `--select`. A calc field that shadows a real column, a data field the schema facts do not have, and a value longer
than its column are BLOCKED. A read never deletes: the persistent fields of a DFM are only that dataset's selection.
