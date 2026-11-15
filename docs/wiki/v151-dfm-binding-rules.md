# Form-file data-binding rules (DFM-B)

Six rules read the text form file (.dfm) that sits next to a unit and check how the
datasets, data sources and data-aware controls in it are wired together. They run from
`lint <unit.pas>` and `lint-all`; a unit without a sibling text form is skipped, and so
is a binary form file. Findings point at the .dfm line.

## The rules
* **dfm-circular-datasource** -- MasterSource / DataSource / DataSet links lead back to
  where they started (tblA -> dsB -> tblB -> dsA -> tblA). One finding per cycle, on the
  earliest object in it.
* **dfm-duplicate-binding** -- two visible, editable controls name the same DataSource and
  DataField. Display-only controls (TDBText, labels), read-only controls, radio buttons
  and hidden controls are ignored.
* **dfm-master-without-fields** -- a dataset has MasterSource but no MasterFields, so the
  detail is not filtered. Query-like datasets (SQL, CommandText, Params, ProviderName)
  are skipped: their parameters link to the master by name.
* **dfm-control-field-type-mismatch** -- a control does not suit the persistent field it
  is bound to (a text edit on a boolean or blob field, an image on a string field ...).
  Persistent fields are the field objects stored in the form file; fields created at run
  time are not seen, because a lint run has no database schema.
* **dfm-required-field-without-control** -- a persistent field with Required = True that
  no visible data-aware control edits. A grid without explicit columns counts for every
  field of its dataset. Auto-increment, read-only, calculated and defaulted fields, and
  datasets no control is bound to (data modules), are skipped.
* **disallowed-dfm-property** -- project policy. Entries are written in the existing
  `disallowed.names` list of the lint config, with a name that starts `dfm:`:
  `dfm:TButton.Cursor`, `dfm:*.ParentFont=False` (any class, optional value). `reason` and
  `except` work as for the other disallowed entries. It reports only what the table lists.

## Defaults and fixes
There is no autofix: each finding needs a decision about the form. The defaults per rule
are listed in the REPORT of lane DFM-B and in `drag-lint rules`.
