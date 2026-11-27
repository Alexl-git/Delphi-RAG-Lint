# ask: change-coupling

**Which units change together.** Pairs of units that were committed together again and again in the version control history, whether or not one uses the other. One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`) (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask change-coupling --target project --db <project.sqlite> [--since <rev|YYYY-MM-DD>] [--min-support N] [--cap N]
```

* `--since` -- where the history starts: a revision (its later commits are read; the revision itself is not) or a day `YYYY-MM-DD` (that day on). Default: the whole history.
* `--min-support N` -- a pair needs at least N shared commits (default 2).
* `--cap N` -- how many pairs are listed (default 20), heaviest first.

Needs the indexed units to sit in a git or an hg working copy (a folder holding BOTH a `.git` and a `.hg` is refused: the tool is not chosen for you). The history is read when you ask; nothing about it is stored in the index.

## You select

Nothing: the question is project-wide (the target is accepted and ignored; use `project`).

## The chart shows

One row per pair, heaviest first: the shared commits (co-changes), the commits that touched each unit alone or together (support A, support B) and the weight. `weight = 2 * co-changes / (support A + support B)`, between 0 and 1. Row labels click through to the first unit's source; `change_coupling_pairs.csv` beside the chart holds the same table.

## It stands on

The commit log of the working copy (`git log --name-status` / `hg log` with file lists), joined to the unit symbols of the index by file path.

## Read it carefully

* Only units of the index count. A file in a commit that the index does not hold is never guessed into a pair; it is counted as `Unindexed` (it exists) or `Gone` (it was deleted, or renamed: a rename is never detected by similarity, the old name is a deleted file and the new name a new one) in the bundle's meta.
* A commit that touches more than 40 files is a mechanical change (a rename of a folder, a formatter run) and is skipped; the meta says how many (`Excluded`).
* Merge commits are not read. Support counts commits that added or modified a unit.
* Pairs with no `uses` link between them are the point: they are the hidden contracts (a client and a server unit, a unit and its SQL script) that nothing in the compiler ties together.