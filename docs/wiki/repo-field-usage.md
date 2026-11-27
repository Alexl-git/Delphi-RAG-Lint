# Where a field is used

```
drag-lint repo field-usage --fields "A,B,C" [--json] (--db <project index> | --project <project file>)
```

Asks the PROJECT index (not the field repository) where each named field is used, and answers one line:

```
{"usage":[{"field":"ID","kinds":["dfm","grid","lookup","code"]}]}
```

| Kind | Found when |
|---|---|
| `dfm` | a DFM control has `DataField` = the field |
| `grid` | a grid column (`*Column*` object) has `FieldName` or `DataBinding.FieldName` = the field |
| `lookup` | `KeyField`, `ListField`, `LookupKeyFields`, `LookupResultField`, `Properties.KeyFieldNames` or `Properties.ListFieldNames` names the field (one name or a `;` list) |
| `code` | the index holds a literal-name field access of it (`FieldByName('ID')`, `Fields`-style accesses) |

Names are compared without case and without blanks; the answer upper-cases them and folds duplicates. Kinds come in the
order dfm, grid, lookup, code. A field with no use is omitted, so `{"usage":[]}` means nothing is used. Without `--json`
each used field is one line, `ID: dfm, grid, code`.

The index is `--db` when given, else the one the manifest names for `--project`. Reindex after editing a DFM or unit,
or the answer is the old one. An index made before the DFM tables existed has no `dfm` / `grid` / `lookup` answer, only
`code`.

| Exit | Meaning |
|---|---|
| 0 | answered |
| 1 | no project index, or it cannot be opened |
| 2 | no `--fields` |

The IDE plugin (Select Fields) runs this verb and reads the JSON above; while the verb is missing it shows blank icons.
Tests: `tests\autotest\run_v156_FUSAGE.ps1` (fixture project; a use removed drops exactly its kind).
