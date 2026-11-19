---
id: datamodule-form-global
title: Data module reaching a global form (lint rule)
summary: "Project lint rule, ON by default since 1.52: a data module unit reads or writes another unit's global form variable"
product: DL
group: linting
order: 30009
since: 1.42.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Data module reaching a global form (lint rule)

Project lint rule, ON by default since 1.52: a data module unit reads or writes another unit's global form variable.

Read this to see what datamodule-form-global reports and what keeps a homonym out. It runs in lint-all and lint-project over a project index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none] [--no-budget]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule datamodule-form-global
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A unit that declares a `TDataModule` descendant reads or writes another unit's global form variable. The data layer now needs that form to exist and to have been created. ON by default since 1.52 (it was OFF before).

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

### Measured (2026-11-06)
On Loader2025 it reports 75 findings, one per data module, all against one form variable (frmLoader2019_Main, 5 to 137 references each). All 75 were checked by hand against the source (a sample of the references: lstSource.Items.Add, LogError, IBD.InTransaction): every one is a real data-layer-to-main-form dependency, none a false positive. It was OFF until 1.51 because a legacy loader repeats it in every module; 1.52 turns it ON by default (rule-defaults-152). Silence it with `--disable datamodule-form-global` or a config entry.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
