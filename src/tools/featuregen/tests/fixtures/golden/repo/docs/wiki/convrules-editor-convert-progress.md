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

## What it needs
A Convert run (Conversion > Convert..., then Convert). Nothing to configure.

## Limits
The engine's own progress inside one convert-apply call is not shown; a long
apply shows `applying` with a ticking clock until it returns.