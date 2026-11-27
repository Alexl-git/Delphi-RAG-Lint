# ask: main-sequence

**How abstract and how stable is each unit, and how far from the balance line.** Robert Martin's main-sequence plot: instability on the horizontal axis, abstractness on the vertical, the line A + I = 1 dashed. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts).

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask main-sequence --target project --db <project.sqlite>
```

`--cap N` bounds the units drawn (default 60); the units farthest from the main sequence are kept. The numbers of every drawn unit are also written as `main_sequence_metrics.csv` (unit, Ca, Ce, I, A, D) beside the diagram.

## You select

Nothing: project-wide (the target is accepted and ignored; use `project`).

## The chart shows

One box per unit at (I, A). Red boxes are off the main sequence: distance D = |A + I - 1| above 0.5. Bottom left (stable and concrete) is the zone of pain, top right (unstable and abstract) the zone of uselessness. Boxes click through to the unit's source; the tooltip carries the numbers.

* Ca = distinct project units that use this unit; Ce = distinct project units this unit uses. Library units (RTL, VCL, third party) are not counted in Ce.
* I = Ce / (Ca + Ce); a unit with no project coupling has I = 0.
* A = abstract types / types, over the unit's classes and interfaces. Interfaces are abstract; a class is abstract when its declaration reads `class abstract` or one of its methods carries the `abstract` directive. Records are not counted; a unit without classes or interfaces has A = 0.

## It stands on

`unit_uses`, the unit, class, interface and method symbols, and the unit's source lines (the index stores no abstract modifier, so the declaration lines are read; an unreadable file counts its classes as concrete and is reported as `SourcesMissing`).

## Read it carefully

* The 0.5 threshold is a reading aid, not a verdict: a unit that is only a set of constants is concrete and stable by design.
* The abstract test reads the source text, so a stale index against edited files can disagree with the file.
