# Initialization reaching a later unit (`init-order-hazard`)

An initialization section reaches a global variable of a unit that initializes later, and that unit's own initialization is what sets the variable. The read sees the value from before it was set: the classic "works in Debug, access violation at startup in Release" bug, which appears or goes away when someone reorders a `uses` clause. OFF by default.

## Running it
```
drag-lint lint-all --db <project.sqlite> --rule init-order-hazard
drag-lint lint-project --db <project.sqlite> --rule init-order-hazard
```
It needs an index that holds the `.dpr`, and an index that has resolved references to sections (1.44 or later).

## The computed order
The index stores `uses` clauses, not an order, and the order follows from them: a depth-first post-order from the `.dpr`'s uses list, each unit visiting its interface uses, then its implementation uses, then taking its place. A unit already being visited is skipped, and that is what decides the order inside a cycle. Checked against the Win64 compiler on a program with overlapping implementation-uses cycles: the order it printed matched this model exactly.

A unit that uses another without a cycle always initializes after it, so this rule can only fire inside a uses cycle.

## What it reports
One warning per section's unit, later unit and variable, at the call or reference in the section that starts the path. The message names the routine that reads the variable and the program whose order was used.

A variable counts as set by a unit's initialization when the section, or a routine of that unit the section calls, assigns it or passes it to `New`, `GetMem` or `SetLength`.

## What stays silent
- A routine that also assigns the variable (lazy creation), or tests it against `nil` or with `Assigned`.
- A local, parameter or class member of the same name.
- A variable the later unit's initialization does not set.
- A call through virtual dispatch or a callback, and a call the index resolved only as ambiguous: only certain call edges are walked.
- A package: only a `.dpr` gives an order here. A unit no program reaches has no position.
- A unit whose name two files of the index share.