# Convert progress

While a Convert run is in progress, ConvRulesEditor shows what it is doing right
now: unit k of N, book j of M, the phase, and how long the unit and the whole
run have taken. Use it to see that a long run is still working, and where it is.

## Where it shows
On the status bar and on a line under the Convert / Cancel buttons of the
Convert tab, for example:

```
Unit 2 of 5: SystemData2 -- book 1 of 2 BDE-to-FireDAC: applying (0:42, total 3:10)
```

The phases are: reindexing before apply, backing up, applying, reindexing after
apply, restoring from backup (when a book failed), and the final reindex
(`Final reindex (total 3:10)`). The clocks tick once a second while one phase
runs. Each unit's rows appear in the results grid as soon as that unit has
finished.

### Batch mode
With two or more units, an unscoped run and an engine that reports
`batch_units`, the tab converts book by book with ONE convert-apply per book over
up to 8 units (the start status says `-- batch mode (8 per call)`). The line then
names the chunk:

```
All 20 unit(s): reindexing before apply (0:03, total 0:03)
Book 1 of 2 BDE-to-FireDAC: applying units 1-8 of 20 in one batch (0:42, total 3:10)
Book 1 of 2 BDE-to-FireDAC: reindexing after batch apply, units 1-8 of 20 (0:51, total 3:19)
```

The grid fills per unit when its last book's chunk is done, and the report gets
one `batch: N unit(s) -- a ok, r refused, f failed; ...` note per chunk. Set
`CONVRULES_BATCH=off` in the editor's environment before starting it to convert
one unit at a time (an IDE-scoped run and a single unit always do).

## What it needs
A Convert run (Conversion > Convert..., then Convert). Nothing to configure.

## Limits
The engine's own progress inside one convert-apply call is not shown; a long
apply shows `applying` with a ticking clock until it returns.

## Where to click

**Convert tab progress line**
1. Choose Conversion > Convert... (opens the Convert tab)
2. Check the books, add the units (Add...), click Convert
3. Read the progress line under the buttons and in the status bar: unit, book, phase, elapsed
