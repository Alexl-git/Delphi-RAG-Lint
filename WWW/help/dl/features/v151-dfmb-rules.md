---
id: v151-dfmb-rules
title: Form-file data-binding rules
summary: "Six lint rules check the text .dfm beside a unit: bad data links, duplicate bindings, field-type mismatches, unreachable required fields"
product: DL
group: linting
order: 30049
since: 1.51.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Form-file data-binding rules

Six lint rules check the text .dfm beside a unit: bad data links, duplicate bindings, field-type mismatches, unreachable required fields.

Read this when you want lint to check how datasets, data sources and data-aware controls are wired in a .dfm. Run `drag-lint lint <unit.pas>` or `lint-all`; the checks run for any unit that has a text form file beside it. Each rule is selectable with --rule; disallowed-dfm-property needs entries in the disallowed.names config list that start with dfm:.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Six rules read the text form file (.dfm) that sits next to a unit and check how the
datasets, data sources and data-aware controls in it are wired together. They run from
`lint <unit.pas>` and `lint-all`; a unit without a sibling text form is skipped, and so
is a binary form file. Findings point at the .dfm line.

### The rules
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

### Defaults and fixes
There is no autofix: each finding needs a decision about the form. The defaults per rule
are listed in the REPORT of lane DFM-B and in `drag-lint rules`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
