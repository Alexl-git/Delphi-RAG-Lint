---
id: v152-defaults
title: Default-on form, dataset and data-module rules
summary: Four lint rules on by default since 1.52 (form object/field, foreign form access, edit without post, data module form global); a shipped exempt-class list
product: DL
group: linting
order: 30068
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Default-on form, dataset and data-module rules

Four lint rules on by default since 1.52 (form object/field, foreign form access, edit without post, data module form global); a shipped exempt-class list.

Read this when a form object without a field, a control reached through another form's global variable or a dataset left in edit mode now shows up without --enable, or when you need to silence a form object class (a third-party sub-object the designer creates without a field) for your project.

## How to run it

```text
drag-lint lint  <path>       [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>] [--no-budget]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint rules [--json] [--category <name>] [--standard cwe|cert|misra] [--rule <id>[,<id>]] [--rules-dir <dir>] [--target-compiler <ver|auto> [--project <.dproj>]] - list every lint rule (catalog; each labelled rule shows its CWE/CERT/MISRA ids, --json adds `compliance` and needs_compiler / compat_since / target_active; --standard lists only rules labelled under it; --rule <id>[,<id>] lists only those rules, an unknown id is exit 2)
```

Full flag list: [rules in the CLI reference](../cli.md#rules).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--profile` | `<name>` |  |  |
| `--target-compiler` | `<ver\|auto>` |  |  |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--json` |  |  |  |
| `--labels` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--build-config` | `<name>` |  |  |
| `--db` | `<index.sqlite>` |  |  |
| `--output` | `<file>` |  |  |
| `--project-rules` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |
| `--json` |  |  |  |
| `--category` | `<name>` |  |  |
| `--standard` |  |  |  |
| `--rule` | `<id>` |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--target-compiler` | `<ver\|auto>` |  |  |
| `--project` | `<.dproj>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Four rules that were opt-in are now on (`datamodule-form-global` in `lint-all` only, it is project-wide; the other three in `lint`, `lint-all` and the editor). Each was re-measured on the CLIENT, SERVER, YADF and Loader indexes before the change.

| Rule | Severity | What it reports |
|---|---|---|
| `form-object-without-field` | hint | an object of the form file with no field in the form class: code cannot reach it by name |
| `foreign-form-control-access` | hint | code that reaches a control of another unit's form through its global variable (`Form2.Edit1`) |
| `dataset-edit-without-post` | warning | `Edit` / `Append` / `Insert` whose record is changed but never posted or cancelled in the unit |
| `datamodule-form-global` | warning | a unit declaring a `TDataModule` descendant reads or writes another unit's global form variable (lint-all) |

Turn one off with `--disable <rule>` or `"disabled"` in the project lint config.

### Exempting classes from form-object-without-field

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

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
