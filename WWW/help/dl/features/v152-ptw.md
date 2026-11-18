---
id: v152-ptw
title: parameter-type-too-wide ON by default, with an autofix
summary: parameter-type-too-wide ships ON as a warning in lint-all / lint-project with an autofix that retypes the parameter through the compile gate
product: DL
group: linting
order: 30072
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# parameter-type-too-wide ON by default, with an autofix

parameter-type-too-wide ships ON as a warning in lint-all / lint-project with an autofix that retypes the parameter through the compile gate.

Read this when lint-all reports parameter-type-too-wide and you want to fix it, or want to know why a similar routine is not reported. The rule reports a class-typed parameter whose routine uses only members an ancestor declares; it skips library code, overrides and virtual methods, interface methods, published and form-bound event handlers and routines taken as a method pointer. The fix re-proves the finding, retypes both routine headers, adds the ancestor's unit to uses when needed, and with --compile-gate keeps the edit only when the project still builds.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output|--report <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none] [--no-budget]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule parameter-type-too-wide
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

```text
drag-lint lint <unit.pas> --db <db> --rule parameter-type-too-wide --fix --fix-rule parameter-type-too-wide [--fix-line <n>] --apply --project <X.dproj> [--compile-gate | --no-compile-gate] [--library-db <lib>] [--no-backup]
```

Example:

```text
drag-lint lint <unit.pas> --db <project.sqlite> --rule parameter-type-too-wide --fix --fix-rule parameter-type-too-wide --apply --project <X.dproj> --compile-gate
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--fix-rule` | `parameter-type-too-wide` |  |  |
| `--fix-line` | `<n>` |  |  |
| `--compile-gate` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Since 1.52 the project rule [`parameter-type-too-wide`](parameter-type-too-wide.md) ships **ON** as a **warning**
in `lint-all` and `lint-project`, and it has an autofix (owner ruling B7).

### What it reports

A class-typed parameter whose routine only uses members that an ancestor of the declared type already declares:

```pascal
procedure FreeMid(pP: TLeaf);   // warning: only members of TMid are used -- declare it TMid
begin
  pP.MidOp;
end;
```

The proof is the one `drag-lint narrow-param --all --plan` makes. The rule reports exactly that plan's fixes, one
warning per parameter, at the routine's declaration.

### What it skips

Where you have no choice about the signature, the rule is silent:

| Skip class | Why |
|---|---|
| library code (a unit outside the project's own roots) | not yours to change; the index must live in the project's `_D-RAG` folder, or pass `--project` |
| `virtual`, `override`, `dynamic`, `abstract`, `message` methods | the signature is shared with the other methods of the chain |
| interface methods | an interface is implemented by name and signature |
| published methods, and methods a `.dfm` binds to an event | a form file binds a handler by name and signature |
| routines taken as a value (assigned to an event or a method pointer / procedural variable) | the pointer's type names the old parameter type |
| overloaded routines, property accessors, `var` / `out` parameters | see [narrow-param](narrow-param.md) for the full list of refusals |

`lint <unit>` evaluates the rule only with `--rule parameter-type-too-wide` and an index: the proof needs the whole
project, so it is not part of the per-file default set (and so not of the IDE gutter).

### Fixing it

```text
drag-lint lint <unit.pas> --db <project.sqlite> --rule parameter-type-too-wide ^
  --fix --fix-rule parameter-type-too-wide --fix-line <n> --apply --project <X.dproj> --compile-gate
```

The fix re-proves the finding first (a body that changed since the index was built is declined, not applied), then
retypes the parameter in the routine's declaration and implementation headers, and adds the ancestor's unit to the
uses clause of the section that declares the routine when it is not in scope yet. With `--compile-gate` the project
is built before and after the write and the edit is rolled back if the build breaks. Without `--fix-line` every
finding of the unit is fixed in one pass; with a platform library index (`--library-db`) VCL and RTL ancestors are
proved too.

### Review instead of fixing

A `dl:ok parameter-type-too-wide` marker on the routine's declaration line reviews one finding; `"parameter-type-too-wide":
{ "enabled": false }` in the project lint config turns the rule off for a project.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
