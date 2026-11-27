# ask: dependency-matrix

**Which unit uses which, as a matrix.** One row and one column per unit of the project; a filled cell means "the row's unit names the column's unit in a uses clause". One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask dependency-matrix --target project --db <project.sqlite>
```

`--cap N` bounds the number of units drawn (default 40); the busiest units (most uses edges) are kept and the rest is counted as Hidden in the bundle's meta.

## You select

Nothing: the matrix is project-wide (the target is accepted and ignored; use `project`).

## The chart shows

Rows are numbered units, the columns carry the same numbers. A cell reads `I` when the row's unit uses the column's unit in the interface section, `i` when only in the implementation section. The last column, `lib`, is every library unit as ONE column (RTL, VCL, third-party units that are not in the index): its cell is the number of distinct library units the row's unit uses. Row labels click through to the unit's source.

## It stands on

`unit_uses` (one row per uses entry) joined to the unit symbol of the entry's file. A uses entry that names no indexed unit is a library use. A unit naming itself is not drawn.

## Read it carefully

* Cells are distinct unit pairs: a unit that lists another twice is one cell. The right-hand count (uses edges) is the number of filled unit-to-unit cells.
* A cell above the diagonal is not a fault; a cell pair `A->B` and `B->A` is a cycle, and [`cycles`](ask-cycles) names it.
* The `lib` column counts distinct library units per row, not uses entries.
