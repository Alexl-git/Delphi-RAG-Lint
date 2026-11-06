# Finalization reaching a unit already finalized (`finalization-after-dependency`)

A finalization section reaches a global variable of a unit that has already been finalized, and that unit's finalization is what tears the variable down. The read sees a freed object, usually as an access violation on exit. ON by default in `lint-all` and `lint-project`.

## Running it
```
drag-lint lint-all --db <project.sqlite> --rule finalization-after-dependency
drag-lint lint-project --db <project.sqlite> --rule finalization-after-dependency
```
It needs an index that holds the `.dpr`, and an index that has resolved references to sections (1.44 or later).

## The order
Finalization runs in the reverse of initialization, so a unit that initializes later is finalized earlier. The initialization order is computed from the `uses` clauses as described in [init-order-hazard](init-order-hazard.md). A unit that uses another without a cycle is always finalized before it, so this rule can only fire inside a uses cycle.

## What it reports
One warning per section's unit, earlier unit and variable, at the call or reference in the section that starts the path. A variable counts as torn down when the earlier unit's finalization, or a routine of that unit the section calls, names it.

## What stays silent
- A routine that also assigns the variable, or tests it against `nil` or with `Assigned`. That covers the `FreeAndNil` plus `Assigned` idiom.
- A local, parameter or class member of the same name.
- A variable the earlier unit's finalization does not name.
- A call through virtual dispatch or a callback, and a call the index resolved only as ambiguous.
- A package: only a `.dpr` gives an order here.