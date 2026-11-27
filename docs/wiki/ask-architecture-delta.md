# ask: architecture-delta

**What changed in the unit dependencies between two indexes of the same project.** A question over two indexes (before and after), not a lint rule. One of the questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask architecture-delta --target project --db <after.sqlite> --counterpart-db <before.sqlite> [--cap N]
```

`--db` is the AFTER index, `--counterpart-db` the BEFORE index. `--counterpart-db` is required (or a pairing in `report-pairs.json`); without the before side nothing can be diffed, so the question is refused and names the missing flag. `--cap N` bounds the units drawn.

## You select

Nothing: project-wide (the target is accepted and ignored; use `project`).

## The chart shows

The touched units and the uses edges between them: an added edge is green, a removed edge red and dashed, an unchanged edge grey. The units of a cycle introduced between the two indexes get a thick red outline. The footer states the counts: edges changed and new cycles. The meta lines carry UnitsAdded, UnitsRemoved, EdgesAdded, EdgesRemoved, EdgesUnchanged, CyclesIntroduced, CyclesResolved, Shown and Hidden.

## It stands on

* The unit list (`N unit`) and the uses edges (`E a -> b`) of each index, diffed with the same Myers diff `compare` uses.
* A cycle is a strongly connected group of two or more units. It is **introduced** when it is not contained in one cycle of the before index; **resolved** is the same test the other way round.

## Read it carefully

* Only the unit dependencies are compared, not routine-level calls; a changed call between two units that already used each other shows nothing.
* The two indexes must come from the same project at two points in time; swapping them turns added into removed and introduced cycles into resolved ones.
* Zero changes is an answer ("no dependency changed"), not an error.
