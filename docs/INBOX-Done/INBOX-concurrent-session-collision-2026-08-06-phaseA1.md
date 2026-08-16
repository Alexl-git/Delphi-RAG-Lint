> **RETIRED to INBOX-Done/ on 2026-08-15.** HISTORICAL INCIDENT REPORT: two sessions writing the same tree. No code defect to fix; the operational lesson (one session per repo, kill orphaned drag-lint.exe holding a DB) is now a standing fact in CLAUDE.md and auto-memory.
>
> Original note follows unchanged.

# RESOLVED: two sessions wrote PHASE A1 into one tree (2026-08-06)

**Status: CLOSED.** The user confirmed at ~22:00 that nobody else is working on drag-lint and
that this session is authoritative. The tree was reconciled to ONE implementation and the
work continued through A5. Kept as a record because the two defects found in the other
session's code are the kind that pass a battery and fail a user.

## What happened

A second `claude` process (started 20:18) implemented the same PHASE A1 rulings in the same
files while this session was working, and committed them as `344711d`. That commit contains
BOTH authors' work: this session's boundary rule in `DRagLint.Doc.Harvest.pas`, and the other
session's D-1/D-5 code in `DRagLint.Doc.Facts.pas`. It also left
`DRagLint.Doc.Harvest` in the INTERFACE uses clause of `DRagLint.Doc.Facts`, which does not
compile -- duplicate of the implementation-side use, and the interface-level cycle the
comment right beside it warns about.

## The two defects that were replaced (both were live in `344711d`)

1. **`DedupeHarvestedSummary` destroyed the summary if it ever fired.** It ended with
   `ANewSummary := NewTokenList.CommaText` -- replacing the prose with a sorted, lowercased,
   comma-separated token list (`becomes,first,paragraph,summary`). Unreachable in practice
   (`HarvestInterfaceComment` guarded on `AFacts.HarvestedSummary <> ''`, which is always `''`
   there because `Build` starts from `Default(TDocFacts)`), so it was a latent landmine rather
   than a live bug -- and the guard is also why no test could have caught it.

   D-1's dedupe now lives where the duplication actually happens: `MergeComment`'s repair
   path, at the ownership handover, where preserved hand prose and regenerated harvested
   prose meet. That case is real, reachable, and now covered.

2. **`HasForeignSymbolInSummary` was far too eager for ruling D-5.** It tested only the FIRST
   identifier in the summary, with no "looks like a symbol reference" filter, and only
   `Symbols[0].FileId`. `Register`, `Create`, `Count`, `Backup` are ordinary English words
   that also resolve as symbols in a large index, so a summary opening on any of them would
   have lost its summary. D-5 says be conservative -- a false demotion loses a good summary.

   The shipped version requires compound-case spelling, resolution in the index, and EVERY
   declaration of the name to be in another file; the runner asserts both conservatism arms
   with cases that a first-identifier demoter would fail.

## The one thing worth keeping from it

The `AUTO_MARK`-at-emit-time comment in `HarvestText` is correct and was kept: the marker is
applied by `MergeComment`, and the harvested text itself stays pure. That session had briefly
prepended the marker in `HarvestText` too (doubling it) and had already reverted that before
this session took over.

## Standing lesson

The collision was only visible because a `system-reminder` said the file had changed between
two reads. Nothing else -- not the battery, not git -- would have surfaced it before the two
implementations were both compiled into one binary. If a file changes under an edit in this
repo, stop and find out who else is writing.
