# Data module reaching a global form (`datamodule-form-global`)

A unit that declares a `TDataModule` descendant reads or writes another unit's global form variable. The data layer now needs that form to exist and to have been created. OFF by default.

## Running it
```
drag-lint lint-all --db <project.sqlite> --rule datamodule-form-global
drag-lint lint-project --db <project.sqlite> --rule datamodule-form-global
```
It needs an index: one unit cannot tell which classes are forms.

## What it reports
One warning per data module unit and form variable, at the first reference, with the number of references in the message. A form variable is a unit-level `var` whose type is `TForm`, `TCustomForm` or a descendant the project index or the platform library knows, so a form built on `TdxRibbonForm` counts.

## What stays silent
- A unit with no data module class.
- A global that is not a form.
- A form variable of a unit the data module does not list in `uses`.
- A name the data module's own unit also declares (a field or local of that name wins in scope).
- A form class whose chain to `TForm` goes through a class neither index knows; with no library index, that means any library base class.
- A member access such as `Foo.MainForm`: only a bare name is the global.

## Measured (2026-11-06)
The rule is OFF by default. On Loader2025 it reports 75 findings, one per data module, all against one form variable (frmLoader2019_Main, 5 to 137 references each). All 75 were checked by hand against the source (a sample of the references: lstSource.Items.Add, LogError, IBD.InTransaction): every one is a real data-layer-to-main-form dependency, none a false positive. It stays OFF because it is a design hint that a legacy loader repeats in every module; enable it with `--enable datamodule-form-global` when untangling that layer.
