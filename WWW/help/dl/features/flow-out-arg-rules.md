---
id: flow-out-arg-rules
title: Data-flow rules that know a parameter's mode
summary: "Three OFF rules: a local that only receives out arguments, a store overwritten by an out argument, a local passed by value to a method before it is assigned"
product: DL
group: linting
order: 30016
since: 1.46.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Data-flow rules that know a parameter's mode

Three OFF rules: a local that only receives out arguments, a store overwritten by an out argument, a local passed by value to a method before it is assigned.

Read this to see what write-only-local, overwrite-before-read and used-before-assignment cannot see, and the three OFF rules that report it.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Three OFF rules for what the default data-flow rules cannot see. `write-only-local` and
`overwrite-before-read` count every call argument as a use, and `used-before-assignment` asks a
parameter's mode for bare-name calls only. So a local passed to `G.GetOut(X)` looks read, and a local
passed to `G.Take(X)` before it is assigned goes unnoticed.

```text
drag-lint lint <file.pas> --db <project.sqlite> --enable local-only-out-arg,dead-store-before-out-arg,by-value-arg-before-assignment
drag-lint lint-all --db <project.sqlite> --rule dead-store-before-out-arg
```

| Rule | Default | Reports |
|---|---|---|
| `local-only-out-arg` | OFF, info | A local passed as an `out` argument that nothing in the routine reads |
| `dead-store-before-out-arg` | OFF, warning | `X := 1; G.GetOut(X); Use(X);`: the store is overwritten before any read |
| `by-value-arg-before-assignment` | OFF, error or warning | `G.Take(X);` with X not assigned. Error when no path assigned it, warning when some path did |

### Where a mode comes from

A bare callee: its signature, from the index or from this unit. A method: the receiver's static type
in `ref_types`, the method's overload set over the type's whole ancestry, and every applicable overload
agreeing. So on an index older than 1.44, or with no index, only the bare `out` shapes report, and
`by-value-arg-before-assignment` reports nothing.

### What keeps a rule silent

* The mode is not proved: a type name with two declarations, an ancestor the index cannot follow, a
  helper with a method of that name, a member that is not a method, overloads that disagree, a `with`.
* A `var` argument: the callee may read it.
* An argument that is not a bare local: `G.GetOut(R.A)` writes part of R.
* A second mention of the local in the same statement: `G.Two(X, X)`.
* An `out` argument that may not run: right of `and` / `or`, or in a branch of an `if` expression.
* A local a nested routine captures, and the stores `overwrite-before-read` also forgives: a nil
  initialisation before a `try`, `X := nil` on an interface.
* For `by-value-arg-before-assignment`: a managed local, a static array (Delphi passes its address, and
  the callee may fill it), an untyped parameter, a pointer-typed parameter (`^T`, `Pointer`, `PChar`,
  `P` + capital, `LP` + capital), an assignment under the same guard.

### Limits

An `out` is taken at its word: a callee that reads what it was handed is not seen. A by-value call still
counts as a possible definition for `used-before-assignment`, so a later read of the same local stays
silent; the rule reports the first call only.

Why these are separate ids, and how they could fold into the default rules:
`docs\superpowers\specs\2026-11-06-liveness-out-args-by-value.md`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
