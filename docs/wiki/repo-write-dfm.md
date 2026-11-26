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
| Size of a string column | `CHAR_LENGTH` (not for BDE datasets under `fieldrepo.bde` readonly / none) | checked |
| KeyFields, LookupDataSet, LookupKeyFields, LookupResultField | `SOURCEKEY`, `DESTTABLE`, `DESTKEY` (empty = the primary key), `DESTVALUE`, as the names the datasets use; BLOCKED while the table of the current lookup dataset is not known | checked |
| Expression of an aggregate field | `CALC_BODY` | checked |
| FieldKind | `FIELD_KIND`; data, calc and internal-calc only | unchecked |
| a new persistent field (`--names`) | class from the Firebird type, or from `FIELD_AS_TYPE` for a field that is no column | checked; unchecked for the first persistent field of a dataset |
| a removed persistent field (`--names`) | not in the selection | unchecked |
| a removed grid / layout item | bound to a removed field (see below) | unchecked; the field's removal needs it |
| a new event handler | `ONGETTEXT_BODY`, `ONSETTEXT_BODY`, `ONVALIDATE_BODY`, `ONCHANGE_BODY` of a field the form has or the selection adds, when the DFM assigns no handler | unchecked |

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
data module of another folder): the whole wiring is blocked with the reason. A dataset inside a frame, one whose SQL has
parameters and one that is bound to a master are no targets. Neither is one whose DFM does not show that it holds every
row of its table: no SELECT in the DFM (SQL set in code, a memory table), a SELECT over more than that table, one that
is not understood, one with macros or with `WHERE`, `HAVING`, `FIRST`, `SKIP`, `ROWS`, `FETCH` or `OFFSET`,
`Filtered = True`, an inherited dataset. A lookup that already uses such a dataset keeps it; its other wiring changes are
unchecked and a warning gives the reason. Code that replaces the SQL of the DFM is not searched. A lookup that gets
another dataset gets all four properties; an inherited one too, where its form states only `LookupDataSet`. A part that
the repository does not hold blocks the wiring. `LookupDataSet`, `KeyFields`, `LookupKeyFields` and `LookupResultField` of one field are one wiring: one blocked
part blocks all, and `--select` refuses a part without the others and names the missing ids.

**New event handlers (1.55).** When the repository holds code for a field event and the field has no handler, one change creates it: `OnGetText = <Dataset><Field>GetText` in the DFM (the dataset component name, the field name, the event without `On`), `procedure <Name>(Sender: TField; ...);` after the component declarations of the form class, and the method before `initialization` / `finalization` / `end.`: a DLFR region with the stored code, its `{{FIELD}}` macros expanded, exactly as `repo gen-handlers` writes it, so a later `gen-handlers` run finds it unchanged. The change is unchecked: it writes code. A field the selection adds brings its events; their changes need its insert. BLOCKED: no unit, a name the unit already has, a macro the dataset cannot resolve, no line of its own outside a conditional. A handler the DFM already assigns is `gen-handlers`' job.

**Removing a field takes its grid items (1.55).** A DevExpress item bound to the removed field -- a grid column, card row, layout-view item or tree-list column whose `DataBinding.FieldName` is the field, inside a view or tree list whose `DataController.DataSource` is a data source of the dataset -- is removed with it: an unchecked delete of its own (block and declaration), which the field's removal needs; `--select` refuses the field without them. An item that another property of the DFM names (a footer summary's `Column`) or that the code of the unit uses is BLOCKED, and the field with it. Every other binding still blocks the field.

**What is never written:** calc code, the code of a handler the DFM already assigns, graphical columns (they are grid columns), fields that are only
overridden in an inherited form, datasets whose table the DFM does not state.

**BLOCKED**, with the reason: a property the field class does not have; a class, length or lookup dataset the repository or
the form does not settle; a column the SELECT does not return; a new field in an inherited
dataset; on a BDE dataset (TTable, TQuery, TStoredProc, TBDE*) under the project setting `fieldrepo.bde` = `readonly` / `none` (see [[project-settings]]; default `full` = as any dataset, 1.55) every field insert, new event handler and grid / layout item removal (`BDE dataset: read only (project policy)` / `BDE not allowed in this project`); a unit that is missing, does not declare the form class or does not use Data.DB; a removed field that the
form or its unit still needs. "Needs" is wide: the component, or the field name as a word of any string of the DFM
(`DataField`, `DataBinding.FieldName`, `KeyFields`, `LookupResultField`, `MasterFields`, `IndexFieldNames`, an
expression or filter, a SQL parameter; captions and hints do not count), or as a word of any string in the unit (`Locate`, `Filter`, `IndexFieldNames`, a SQL
text, also a message that happens to have the word). A control of
another dataset that binds the same name counts too. A selection that deletes a field and also makes the form name it is
refused (exit 2). Other forms and units are not searched.

**Safety.** Every byte outside a change stays the same: encoding, line ends, indentation, hand formatting. A
binary DFM is refused, and so is one that Delphi cannot convert. The result is converted to binary and read back before
anything is written; a file that changed since it was read, or cannot be opened for writing, stops the whole run. Each
file is replaced by a complete new one; when that fails for one file, those before it get their old bytes back and the
message names the backups. A replacement that loses the file makes it again from the old bytes. A form that is open in the IDE is not detected: save and close it first.

**When the process or the machine stops in the middle.** The backups of all files exist before the first file is
replaced; then each form is replaced before its unit. A stop between the two leaves a new DFM with the old unit: a new
field has no declaration yet (the form compiles and fails to load), a removed field is still declared (harmless). No file
is ever half written. `write-dfm` does not repair this: copy the two backups of the run (same time stamp) over the form
and its unit, and run it again. The form comes first because the plan is made from it: after a stop the form never lacks
a field that the unit has got. A `*.write-dfm-new` or `*.write-dfm-old` file beside a missing form or unit is its new or
its old text; beside an existing one it can be deleted.

Exit code: 0 ok (also a dry run), 1 a failure (also a plan id that no longer fits), 2 a usage error (also a selected change without the one it needs).
