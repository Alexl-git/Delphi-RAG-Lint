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