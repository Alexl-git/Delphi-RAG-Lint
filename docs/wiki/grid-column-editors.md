# Grid column editors in the field repository

A cxGrid column can carry its own in-place editor: `PropertiesClassName` names the class (a combo box, an image combo,
a currency edit, a check box, ...) and the `Properties.*` lines configure it. From 1.56 the field repository keeps both
per column, beside the column's place, so the editor of a column survives the form and can be compared, backed up and
written back.

| DFM | `DL_GRID_COLUMNS` (schema 5) |
|---|---|
| `PropertiesClassName = 'TcxComboBoxProperties'` | `PROPERTIES_CLASS_NAME` = `TcxComboBoxProperties` (no quotes) |
| every `Properties.<name> = <value>` line of the column | `PROPERTIES`: the lines as the DFM has them |

Both are NULL for a column without an editor of its own. A repository of schema 4 has neither column: run
`drag-lint repo migrate --repo <file> --apply` once (`v4 -> v5`).

## Reading them from a form

```
drag-lint repo read-dfm --dfm <form.dfm> --direction dfm-to-repo --repo <file> [--apply | --select <id file>]
```

[`repo read-dfm`](repo-read-dfm) reads the editor of every column it stores: the columns of each `TcxGridDBTableView`
and `TcxGridDBBandedTableView` of the form. There is no flag for it. The dry run shows the values in the column's change:

```
[9] insert DL_GRID_COLUMNS frmEditors|view1|colKind:  -> TABLE_NAME=ORDERS; FIELD_NAME=KIND; COLUMN_INDEX=2; PROPERTIES_CLASS_NAME=TcxComboBoxProperties; PROPERTIES=Properties.DropDownListStyle = lsFixedList\r\nProperties.Items.Strings = (\r\n  'One'\r\n  'Two')
```

**What `PROPERTIES` holds.** The text of the form, not an interpretation of it: every property of the column whose name
starts with `Properties.`, in DFM order, each with all of its lines. A value over several lines is whole: a collection
(`Properties.Items = <` ... `end>`), a string list (`Properties.Items.Strings = (` ... `)`), a long string the form
designer continued with `+` (the blank it leaves after `=` is kept). Lines are separated by CRLF; the indentation of the
first line is removed from every line, so a continuation line keeps the two blanks per level it had below its property.
An event of the editor (`Properties.OnChange = colStatusPropertiesChange`) is such a line too: the handler NAME is
stored, its code is not. `Options.*`, `Position.*`, `Width` and the other properties of the column are not editor lines.

A binary DFM is read through its text form, so its rows equal those of the same form saved as text.

**Changes.** The DFM wins, value by value: a column whose class or lines differ from the stored ones gives one checked
`update ... PROPERTIES_CLASS_NAME: old -> new` or `update ... PROPERTIES: old -> new`; a column that lost its editor
gets NULL again. A second read after `--apply` has no change. A class name longer than its column (128) is BLOCKED.

**Not read.** A column of an inherited grid view (its own properties are in the ancestor's DFM), of a card, layout or
other view, and a column without a name: as for the column order. An editor that comes from a repository item
(`RepositoryItem = ...`) is a link to another component, not `Properties.*` lines, and is not stored. A column that has
`Properties.*` lines and no `PropertiesClassName` (the lines then belong to the default editor of the field type) is
stored with the lines and a NULL class.

**A schema-4 repository** is read as before 1.56: the columns and their order are stored, the editors are not, and the
run says so once: `warning: the repository is schema 4: the editor properties of N grid columns are not read (run repo
migrate --apply)`.

## Backup

`repo backup` writes both columns (`PROPERTIES_CLASS_NAME=...`, `PROPERTIES:` with one ` |` line per line); `repo
restore` reads them back unchanged, and a read of the same form against the restored repository has no change.

## Writing them into a form, and handlers of existing columns

Writing a stored editor back ([`repo write-dfm`](repo-write-dfm)) and offering a missing `OnGetDisplayText` /
`OnCustomDrawCell` handler of a column the form already has ([`repo gen-handlers`](field-repository-handlers)) are the
other two parts of this feature; their pages say what each plans and writes.
