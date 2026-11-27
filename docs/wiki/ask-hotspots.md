# ask: hotspots

**Which units are big, and which of those hold complex routines.** A treemap of the units of the index: the area of a rectangle is the unit's size in lines, its colour the largest routine complexity found in it. Complex code that is also big is the code to repair first. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts).

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask hotspots --target project --db <project.sqlite>
```

`--cap N` bounds the units drawn (default 60); the largest units are kept. The numbers of every drawn unit are also written as `hotspots_metrics.csv` (unit, lines, body_loc, cyclomatic, cyclomatic_max, hottest_routine, hottest_cyclomatic) beside the diagram.

## You select

Nothing: project-wide (the target is accepted and ignored; use `project`).

## The chart shows

One rectangle per unit. Area = the unit's lines. Colour = the largest cyclomatic complexity of one routine of the unit: up to 10 low (green), 11 to 20 moderate (yellow), 21 to 50 high (orange), above 50 very high (red). Units above 20 are counted as hotspots. Rectangles click through to the unit's source; the tooltip names the hottest routine.

## It stands on

The frozen metrics rows (`DRagLint.Query.Metrics`, the same numbers as `drag-lint metrics`): the unit row's lines and largest routine complexity, and the routine rows for the name of the hottest routine. Nothing is recomputed.

## Read it carefully

* Lint findings are not stored in an index (a finding exists only while `lint` runs), so the chart carries no finding count per unit; it says "no findings in this DB". Change frequency (how often a file changed) is not read either: it needs the version-control history, which an index does not hold.
* Size is the unit's last line, so a unit that is mostly comments or declarations is large but not complex: read the colour, not only the area.