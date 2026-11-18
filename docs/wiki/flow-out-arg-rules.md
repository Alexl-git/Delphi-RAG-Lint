# Data-flow rules that know a parameter's mode

`write-only-local` and `overwrite-before-read` count every call argument as a use, and
`used-before-assignment` used to ask a parameter's mode for bare-name calls only. So a local passed to
`G.GetOut(X)` looks read, and a local passed to `G.Take(X)` before it is assigned went unnoticed. Two
OFF rules report the `out` shapes; since 1.52 the by-value shape is part of the default
`used-before-assignment`.

```
drag-lint lint <file.pas> --db <project.sqlite> --enable local-only-out-arg,dead-store-before-out-arg
drag-lint lint-all --db <project.sqlite> --rule dead-store-before-out-arg
drag-lint lint-all --db <project.sqlite> --rule used-before-assignment
```

| Rule | Default | Reports |
|---|---|---|
| `local-only-out-arg` | OFF, info | A local passed as an `out` argument that nothing in the routine reads |
| `dead-store-before-out-arg` | OFF, warning | `X := 1; G.GetOut(X); Use(X);`: the store is overwritten before any read |
| `used-before-assignment` (method by-value arm) | ON, error or warning | `G.Take(X);` with X not assigned. Error when no path assigned it, warning when some path did. Message: `Local "X" is passed by value to a method before it is assigned.` |

**1.52 (EX1, owner ruling 2026-11-18):** the 1.46 id `by-value-arg-before-assignment` is folded into
`used-before-assignment` and removed from the catalogue. Its findings now report under
`used-before-assignment` in every default run; a config or `--enable` that still names the old id
names a rule that no longer exists, and a `dl:ok by-value-arg-before-assignment` marker suppresses
nothing (re-review it as `used-before-assignment`).

## Where a mode comes from

A bare callee: its signature, from the index or from this unit. A method: the receiver's static type
in `ref_types`, the method's overload set over the type's whole ancestry, and every applicable overload
agreeing. So on an index older than 1.44, or with no index, only the bare `out` shapes report, and
the method by-value arm of `used-before-assignment` reports nothing.

## What keeps a rule silent

* The mode is not proved: a type name with two declarations, an ancestor the index cannot follow, a
  helper with a method of that name, a member that is not a method, overloads that disagree, a `with`.
* A `var` argument: the callee may read it.
* An argument that is not a bare local: `G.GetOut(R.A)` writes part of R.
* A second mention of the local in the same statement: `G.Two(X, X)`.
* An `out` argument that may not run: right of `and` / `or`, or in a branch of an `if` expression.
* A local a nested routine captures, and the stores `overwrite-before-read` also forgives: a nil
  initialisation before a `try`, `X := nil` on an interface.
* For the by-value arm: a managed local, a static array (Delphi passes its address, and the callee may
  fill it), an untyped parameter, a pointer-typed parameter (`^T`, `Pointer`, `PChar`, `P` + capital,
  `LP` + capital), an assignment under the same guard, a statement that already reports the local as
  an ordinary read (so one line never carries the finding twice).

## Limits

An `out` is taken at its word: a callee that reads what it was handed is not seen. A by-value call still
counts as a possible definition inside the lattice, so a later read of the same local stays silent; the
by-value arm reports the first call only. Making the call a real read belongs in
`DRagLint.Analysis.Flow.Lattices`, an extractor-fingerprint unit, and waits for an extractor bump.

Cost: `lint-all` now always runs the by-value replay pass while `used-before-assignment` is kept (1.47
PF had skipped it for the OFF id).

Design and the fold option: `docs\superpowers\specs\2026-11-06-liveness-out-args-by-value.md`.
