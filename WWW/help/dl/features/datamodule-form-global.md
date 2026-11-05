---
id: datamodule-form-global
title: Data module reaching a global form (lint rule)
summary: "Project lint rule, OFF by default: a data module unit reads or writes another unit's global form variable"
product: DL
group: linting
order: 30007
since: 1.42.0-alpha
status: shipped
updated: 1.42.0-alpha
---

# Data module reaching a global form (lint rule)

Project lint rule, OFF by default: a data module unit reads or writes another unit's global form variable.

Read this to see what datamodule-form-global reports and what keeps a homonym out. It runs in lint-all and lint-project over a project index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule datamodule-form-global
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A unit that declares a `TDataModule` descendant reads or writes another unit's global form variable. The data layer now needs that form to exist and to have been created. OFF by default.

### Running it
```text
drag-lint lint-all --db <project.sqlite> --rule datamodule-form-global
drag-lint lint-project --db <project.sqlite> --rule datamodule-form-global
```
It needs an index: one unit cannot tell which classes are forms.

### What it reports
One warning per data module unit and form variable, at the first reference, with the number of references in the message. A form variable is a unit-level `var` whose type is `TForm`, `TCustomForm` or a descendant the project index or the platform library knows, so a form built on `TdxRibbonForm` counts.

### What stays silent
- A unit with no data module class.
- A global that is not a form.
- A form variable of a unit the data module does not list in `uses`.
- A name the data module's own unit also declares (a field or local of that name wins in scope).
- A form class whose chain to `TForm` goes through a class neither index knows; with no library index, that means any library base class.
- A member access such as `Foo.MainForm`: only a bare name is the global.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
