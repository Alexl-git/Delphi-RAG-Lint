# Ancestor not in project (`ancestor-not-in-project`)

A project-wide lint rule, severity **error**: a form, frame or data module whose ancestor class is declared in no unit of the project and not in the platform library.

Delphi finds a unit through the `.dproj` / `.dpr` OR through the search path. A form that inherits from `TBaseForm` compiles on your machine because `uBaseForm.pas` happens to be on your search path; on a machine where it is not, the project stops compiling. The project index is the compile closure of the `.dproj` / `.dpr`, so an ancestor that is in neither the project index nor the library index is an ancestor whose unit is not a project member. Add that unit to the project and the finding goes away (and the unit gets indexed).

This is the class-side sibling of `unit-not-in-dpr` (which compares the `.dproj` and `.dpr` lists). The converter blocks a conversion on the same condition; this rule reports it before anyone converts.

## Running it from the CLI
```
drag-lint lint-all --db <project.sqlite>                                 (ON by default)
drag-lint lint-all --db <project.sqlite> --rule ancestor-not-in-project  (only this rule)
drag-lint lint-all --db <project.sqlite> --disable ancestor-not-in-project
```

## What it reports
* One error per class, at its declaration line, naming the class, the ancestor and the unit to add: the qualifying unit of a dotted ancestor (`class(uBase.TBaseForm)`), otherwise the used units of the file that resolve in neither index.
* A class counts as a form / frame / data module when it is the ROOT class of the text `.dfm` / `.fmx` beside its unit (`object` / `inherited` / `inline Name: TClass` on the first line). A binary `.dfm` is skipped.

## What it does not report
* Platform-library ancestors (`TForm`, `TFrame`, `TDataModule`, vendor bases): exempt when the library index declares them.
* Without a library index the rule stays SILENT -- it cannot tell a VCL base from a missing project base.
* Classes without a form file, and non-root classes in a form unit.

Guard: `tests\autotest\run_ancestor_not_in_project.ps1` (fixture `tests\lint-project\ancestor-not-in-project`).