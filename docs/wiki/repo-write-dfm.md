# Write the field repository into a form

```
drag-lint repo write-dfm --dfm <file.dfm>[;...] [--dataset <Name> [--names <FIELD,...>|all]] --direction repo-to-dfm
                         (--repo | --project) [--apply | --select <id file>] [--dry-run] [--json]
```

Prints the change set that brings the persistent fields of a form in line with the repository. Nothing is written
without `--apply` (the checked changes) or `--select` (exactly the ids in the file). The direction is required. The
repository is only read. Every changed file gets a backup beside it: `<file>.before-write-dfm-<yyyymmdd-hhnnss>`.

**The plan id.** The dry run ends its list with a line `# plan <id>`: a hash of every form and unit it read, of the
repository and of the change list. Ids mean something only in that plan, so a `--select` file must hold that line:

```
# plan 3f0c9a51b7e2d684
6
9
```

Without the line nothing is written (exit 2). When a form, its unit, the repository, `--dataset` or `--names` changed
since, the id no longer fits and nothing is written (exit 1): run the dry run again. `all` in the file takes every
change that is not blocked, removed fields included. Plain `--apply` needs no plan id.

| Change | From | Default |
|---|---|---|
| DisplayLabel, DisplayFormat, EditFormat, DisplayWidth, Alignment | the column of that name; a value the repository does not hold changes nothing | checked |
| Visible | `VISIBLE`; hiding a field is unchecked; the False of a row nobody edited is ignored | see left |
| Size of a string column | `CHAR_LENGTH` (not for BDE datasets) | checked |
| KeyFields, LookupDataSet, LookupKeyFields, LookupResultField | `SOURCEKEY`, `DESTTABLE`, `DESTKEY` (empty = the primary key), `DESTVALUE`, as the names the datasets use; BLOCKED while the table of the current lookup dataset is not known | checked |
| Expression of an aggregate field | `CALC_BODY` | checked |
| FieldKind | `FIELD_KIND`; data, calc and internal-calc only | unchecked |
| a new persistent field (`--names`) | class from the Firebird type, or from `FIELD_AS_TYPE` for a field that is no column | checked; unchecked for the first persistent field of a dataset |
| a removed persistent field (`--names`) | not in the selection | unchecked |

**Adding and removing fields.** `--names` is the field selection of one dataset: field names, or `all`. A calculated
field pulls in the fields it uses, a lookup its key. A new field is written as the IDE would write it, and declared in
the form class of the unit beside the DFM: without that declaration the form compiles and then fails to load. A new
aggregate field is not `Active`: the repository does not hold that. A dataset without persistent fields makes its fields
at run time; with the first persistent field only persistent fields exist, so these changes are unchecked and a warning
says so.

**Conditional compilation.** The declaration goes beside its neighbours, but never inside an `{$IFDEF}` (or other
conditional) that does not hold the whole published section, and never inside a comment. When no such place exists, or
the class is declared twice, the change is blocked.

**Lookups.** A lookup keeps its dataset while the table of that dataset is not known (a join, an inherited table, a
data module of another folder): the whole wiring is blocked with the reason. A dataset inside a frame is no new target.

**What is never written:** calc and event code, graphical columns (they are grid columns), fields that are only
overridden in an inherited form, datasets whose table the DFM does not state.

**BLOCKED**, with the reason: a property the field class does not have; a class, length or lookup dataset the repository or
the form does not settle; a column the SELECT does not return; a new column field in a BDE dataset or an inherited
dataset; a unit that is missing, does not declare the form class or does not use Data.DB; a removed field that the
form or its unit still needs. "Needs" is wide: the component, or the field name as a word of any string of the DFM
(`DataField`, `DataBinding.FieldName`, `KeyFields`, `LookupResultField`, `MasterFields`, `IndexFieldNames`, an
expression or filter, a SQL parameter; captions and hints do not count), or in a string of the unit. A control of
another dataset that binds the same name counts too. Other forms and units are not searched.

**Safety.** Every byte outside a planned change stays the same: encoding, line ends, indentation, hand formatting. A
binary DFM is refused, and so is one that Delphi cannot convert. The result is converted to binary and read back before
anything is written; a file that changed since it was read, or cannot be opened for writing, stops the whole run. Each
file is replaced by a complete new one; when that fails for one file, those before it get their old bytes back and the
message names the backups. A form that is open in the IDE is not detected: save and close it first.

Exit code: 0 ok (also a dry run), 1 a failure (also a plan id that no longer fits), 2 a usage error (also a selected change without the one it needs).
