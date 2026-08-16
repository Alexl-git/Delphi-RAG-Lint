> # CLOSED 2026-08-16 (session 22) -- the fixes are now ROW-IDENTICAL PROVEN.
>
> The concurrency theory in this note's headline was refuted long ago; the real
> problem was that an incremental index re-ran the call resolve over the WHOLE
> database, which at 2 GB is indistinguishable from a hang. The scoped-resolve
> fix and the per-pass logging were already landed. What was missing was any
> proof the scoped path AGREES with the unscoped one -- `DRAGLINT_NO_SCOPED_RESOLVE`
> existed precisely to make that a one-binary A/B, and no test used it that way.
>
> `testsutotestun_scoped_resolve_equivalence.ps1` now does: one fixture, one
> body-only edit, two DBs, and every `refs.receiver_text` / `external_target`
> plus every resolved call edge compared row for row (keyed on file+line+col+name
> so re-issued symbol ids cannot register as a difference). They match exactly.
>
> **Two vacuity traps had to be closed for that to mean anything**, and both
> would have passed silently:
>
> 1. If `ScopedResolveIsSound` ever returns False for both runs, the comparison
>    is whole-DB against whole-DB. The suite asserts run A logs
>    `affected call-site ref(s)` and run B logs `WHOLE DB`.
> 2. `ScopedResolveIsSound` declines when the changed set reaches a THIRD of the
>    corpus (`FScopeFiles.Count * 3 >= CountFiles`). The first fixture had 3
>    units and edited 1 -- so it took the whole-DB path and passed while proving
>    nothing. The fixture is now 5 units; **do not shrink it**.
>
> This matters beyond this note: per-file resume, and any future narrowing of the
> added-type fallback, both lean on the scoped path being trustworthy. It now is.

# INBOX -- the "livelock" is FOUR whole-database resolve passes (not a concurrency bug)

**Filed:** 2026-08-11. **DIAGNOSED 2026-08-11** -- the original concurrency theory in
this note was WRONG and is corrected below. Kept in full because the wrong theory is
instructive.

## The finding

After the file walk, every `index` run executes four passes over the ENTIRE database:

```pascal
// DRagLint.CLI.pas:2727-2733  (also at 1900-1902, 2681-2683, 15812-15814)
Store.ResolveUnitUseTargets;
Store.ResolveAncestry;   { v11 (M1): link class/interface heritage cross-unit }
Store.ResolveHelpers;    { v15: link record/class helper targets cross-unit }
Store.ResolveCallTargets;{ v14 (D5): resolve call sites to target symbols }
```

**Their cost scales with the size of the whole index, not with the number of files
just indexed.** Re-indexing 83 files into a 2.1 GB database (2,240,573 symbols,
3,320,946 refs) therefore pays four full-corpus resolutions.

## The reproduction (non-destructive, ~5 minutes)

```
copy library-Win32.sqlite -> liv-A.sqlite, liv-B.sqlite     (2.1 GB each)
drag-lint index "...\DevExpress\VCL\ExpressBars\Sources" --db liv-A.sqlite --force-reparse --no-prune
drag-lint index "...\DevExpress\VCL\ExpressBars\Sources" --db liv-B.sqlite --force-reparse --no-prune
```

Observed, both processes, identically:

| t | state |
|---|---|
| t+0..t+5m | indexing: writes climb 534 -> 2,461 MB, **all 83 files logged** |
| t+5m onward | **writes stop dead at 2,461 MB**, CPU 0.77-0.82 cores, no output |

Then, over a 90 s window in that state: **read +15.2 MB, readOps +1,907, write +0.0 MB.**

**So it is not hung.** It is reading steadily and making no progress a human can see:
a whole-corpus scan with the result written only at the end.

## Why the first diagnosis was wrong

The original theory was a livelock triggered by two platform sections running
concurrently, because win64 hung only ever while win32 ran. That correlation was
**coincidence**:

* Both processes in this reproduction hang, and hang at the SAME byte count -- they
  are not contending, they are each independently doing the same expensive scan.
* The original win64 `--recompile` case printed **zero indexed files** before
  "hanging". That now makes sense: `--recompile` skipped every up-to-date file
  SILENTLY (no per-file line for a skip), then entered the resolve passes. Nothing to
  do with win32.

What genuinely was ruled out still stands, and remains useful: not corruption
(`quick_check` ok, `foreign_key_check` clean), not memory (766 MB WS, 9.9 GB free),
not a DB lock (separate files; a lock wait burns ~0% CPU), not fsync (0 write IOPS),
and not the FTS5 trigram delete triggers (measured 1.0x).

## What to fix

1. **Make the four passes incremental.** They should resolve only rows affected by the
   files just indexed, not the whole corpus. This is the single highest-value indexer
   change remaining -- it is most of the cost of any incremental re-index against a
   large database, and it is pure waste when 83 of 7,412 files changed.
2. **Failing that, make them skippable** (`--no-resolve`) for a run that will be
   followed by another index pass, and run them once at the end of `index --all`
   rather than once per section.
3. **They must print something.** A multi-minute phase that emits no output is
   indistinguishable from a hang -- which is exactly the error this note originally
   made. One line per pass, with row counts, would have made this obvious immediately.

## Consequence for the threading plan

**Threading would not have fixed this**, and would have hidden it: the work is one
serial whole-DB scan per pass. Fix the passes first. See
`docs/PLAN-2026-08-11-indexer-performance-and-concurrency.md`.

## Consequence for running Win32 and Win64 together

There is no longer a known reason they cannot run concurrently -- the blocking theory
was wrong. They write to separate databases. Re-test after the resolve passes are
fixed; the earlier throughput drop (win32 84 -> 28 files/min with win64 running) is
worth re-measuring then, since both processes were partly inside these scans.

Related: `docs/INBOX-library-reindex-25x-slower-on-large-db.md` (the FK-index fix),
`docs/INBOX-index-runs-are-not-resumable.md`.
