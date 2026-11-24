# Write the field repository into a form

```
drag-lint repo write-dfm --dfm <file.dfm>[;...] [--dataset <Name> [--names <FIELD,...>|all]] --direction repo-to-dfm
                         (--repo | --project) [--apply | --select <id file>] [--dry-run] [--json]
```

Prints the change set that brings the persistent fields of a form in line with the repository. Nothing is written
without `--apply` (the checked changes) or `--select` (exactly the ids in the file). The direction is required. The
repository is only read. Every changed file gets a backup beside it: `<file>.before-write-dfm-<yyyymmdd-hhnnss>`.

| Change | From | Default |
|---|---|---|
| DisplayLabel, DisplayFormat, EditFormat, DisplayWidth, Alignment | the column of that name; a value the repository does not hold changes nothing | checked |
| Visible | `VISIBLE`; hiding a field is unchecked; the False of a row nobody edited is ignored | see left |
| Size of a string column | `CHAR_LENGTH` (not for BDE datasets) | checked |
| KeyFields, LookupDataSet, LookupKeyFields, LookupResultField | `SOURCEKEY`, `DESTTABLE`, `DESTKEY` (empty = the primary key), `DESTVALUE`, as the names the datasets use | checked |
| Expression of an aggregate field | `CALC_BODY` | checked |
| FieldKind | `FIELD_KIND`; data, calc and internal-calc only | unchecked |
| a new persistent field (`--names`) | class from the Firebird type, or from `FIELD_AS_TYPE` for a field that is no column | checked |
| a removed persistent field (`--names`) | not in the selection | unchecked |

**Adding and removing fields.** `--names` is the field selection of one dataset: field names, or `all`. A calculated
field pulls in the fields it uses, a lookup its key. A new field is written as the IDE would write it, and declared in
the form class of the unit beside the DFM: without that declaration the form compiles and then fails to load. A new
aggregate field is not `Active`: the repository does not hold that.

**What is never written:** calc and event code, graphical columns (they are grid columns), fields that are only
overridden in an inherited form, datasets whose table the DFM does not state.

**BLOCKED**, with the reason: a property the field class does not have; a class, length or lookup dataset the repository or
the form does not settle; a column the SELECT does not return; a new column field in a BDE dataset or an inherited
dataset; a unit that is missing, does not declare the form class or does not use Data.DB; a removed field that the
form, the unit or a lookup still needs (other units are not searched).

**Safety.** Every byte outside a planned change stays the same: encoding, line ends, indentation, hand formatting. A
binary DFM is refused, and so is one that Delphi cannot convert. The result is converted to binary and read back before
anything is written; a file that changed since it was read, or cannot be opened for writing, stops the whole run.

Exit code: 0 ok (also a dry run), 1 a failure, 2 a usage error.
