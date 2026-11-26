# Fields of a form in the IDE

The `Field Repository` submenu of the drag-lint menu has three commands for the form in the editor. The active project names the repository
(`fieldRepository`); it must be schema 3 or later. Nothing is written before you press Apply.

| Command | What it does | CLI |
|---|---|---|
| Read Fields from Dataset... | reads one dataset into the repository | [repo read-dfm](repo-read-dfm) `--dataset` |
| Read Fields of All Datasets of Form... | reads every dataset and grid view of the form | `repo read-dfm` |
| Select Fields of Dataset... | adds and removes persistent fields of a dataset from the repository | `repo write-dfm --names` |

**The form.** It is read from disk: unsaved changes are saved first, after a question. The dataset is the one selected in
the designer, or the only one of the form; otherwise a list asks.

**Select Fields.** The list has every field the repository has for the table of the dataset. Checked at first: the
persistent fields of the form.

* Checking a calculated, internal-calc or aggregate field adds the fields its code names, a lookup adds its key.
* Unchecking a field removes nothing else. A field that a checked field needs stays, and the status line names that field.
* A graphical field is a grid column, a field of another table and a field the repository does not know are listed and
  cannot be changed: they stay as they are.
* An empty selection is refused. Delete all persistent fields in the form designer instead.
* A dataset without a table (a join, a memory table, SQL built in code) has no list; the message says why.

**The changes.** Each row is one change with its old and new value. It starts checked as the engine proposes it: a removed
field, a hidden field and contradicting values are unchecked. A blocked change shows its reason and cannot be checked.
Warnings are below the list. Enter does not write; Apply does.

**Between preview and write.** `write-dfm` takes the plan id of the preview: when the form, its unit or the repository
changed, nothing is written. For a read the dry run is repeated and compared. A form edited after the preview is neither
written nor read. After a write the form is reloaded; the old files are beside it (`*.before-write-dfm-*`). A form that was
edited while the write ran is not reloaded: the message says `written to disk, NOT reloaded: your editor buffer is older`.
After a failed run that changed a file you are asked whether to reload.

The calculation code of an added field is not written into the unit: see
[generated handlers](field-repository-handlers).

`repo read-dfm --dataset <Name> --json` has what the dialog shows: `persistent` (field, component, class, kind, table,
column) and `tableFields` (field, kind, sourceKey, body).
