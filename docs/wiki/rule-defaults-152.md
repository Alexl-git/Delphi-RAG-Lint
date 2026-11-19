# Rules that are on by default since 1.52

Four rules that were opt-in are now on (`datamodule-form-global` in `lint-all` only, it is project-wide; the other three in `lint`, `lint-all` and the editor). Each was re-measured on the CLIENT, SERVER, YADF and Loader indexes before the change.

| Rule | Severity | What it reports |
|---|---|---|
| `form-object-without-field` | hint | an object of the form file with no field in the form class: code cannot reach it by name |
| `foreign-form-control-access` | hint | code that reaches a control of another unit's form through its global variable (`Form2.Edit1`) |
| `dataset-edit-without-post` | warning | `Edit` / `Append` / `Insert` whose record is changed but never posted or cancelled in the unit |
| `datamodule-form-global` | warning | a unit declaring a `TDataModule` descendant reads or writes another unit's global form variable (lint-all) |

Turn one off with `--disable <rule>` or `"disabled"` in the project lint config.

## Exempting classes from form-object-without-field

Designer-created sub-objects (bar and layout items, grid levels, views and columns, styles) have no field in the form class by design. They are skipped by a shipped list, `rules\form-object-without-field.exempt.txt`, one class name per line, `#` for comments, a trailing `*` as the only wildcard, matched without regard to case. The shipped file is replaced by an upgrade: do not edit it.

Add your own classes to the project lint config:

```json
{
  "form_object_without_field": {
    "exempt_classes": ["TMyThing", "TVendorItem*"],
    "use_default_list": true
  }
}
```

`"use_default_list": false` turns the shipped list off; your `exempt_classes` still apply.
