# Scoped validation on Save

Validating a whole rule book costs one engine process per From/To pair. A Save
therefore validates only what changed: the syntax of the whole text, then each
CHANGED `#convert` block against its own pair. Unchanged blocks are presumed
validated earlier.

## Where it shows
**File > Save** (after the backup) and **File > Validate**. Findings become marks on
the rule lines; the status bar reads `OK`, `OK, N warning(s)` or the first error.

## What to know
* A block whose last validation was cancelled stays pending and is checked again on the
  next Save, even though it no longer differs from the snapshot.
* Blocks that share a From/To pair share ONE engine answer; each block keeps only the
  diagnostics on its own lines and on the `#mapping` lines it applies.
* A cancel never replaces a mark: only completed passes do.