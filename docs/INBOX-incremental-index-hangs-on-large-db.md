> # STILL LIVE -- REPRODUCED 2026-08-17, and the mechanism is now known.
>
> Indexed 84 new files into a scratch copy of `library-Win64.sqlite` (2.3 GB).
> The walk completed; ancestry 16.7 s; helpers 12.9 s; then **CPU-bound for
> 450 s+ in the calls resolve** (9.9 s CPU per 10 s wall), killed at 8 minutes.
>
> **IT IS NOT A HANG -- it is a silent whole-DB pass.** New units introduce new
> type names, so `ScopedResolveIsSound` fails its type-equality gate
> (`src\storage\DRagLint.Storage.SQLite.pas:3949-3951`) and the run falls back to
> resolving calls across the WHOLE database -- 3.4 M refs, a cost the code itself
> documents as **"37 MINUTES on a 2 GB index"**
> (`Storage.SQLite.pas:8712-8714`).
>
> **The refuted O(corpus) affected-set claim STAYS REFUTED.** This is the GATE,
> not the set. Do not resurrect that line of enquiry.
>
> **Smallest fix is diagnosis, not optimisation:** announce "WHOLE DB + reason"
> on stderr **before** the pass. Today the scoped/whole line (`:8843` / `:8846`)
> prints only *after* it completes, which is precisely why a 37-minute pass looks
> like a hang and why this note exists. ~1 h. Positive control: the unfixed build
> lacks the announce line.
>
> Separate and correctness-sensitive (~1 day, do NOT bundle): relax the gate for
> pure type ADDITIONS. The `DRAGLINT_NO_SCOPED_RESOLVE` A/B hatch (`:3930`)
> provides the equivalence test.
>
> ---
>
> # THE DIAGNOSIS HALF IS FIXED 2026-08-17 (session 25). It was never a hang.
>
> The calls resolve now says WHICH shape it is about to run, and WHY, **before**
> it runs -- on stderr, where the completion line already was:
>
> ```
> resolve: calls      starting WHOLE-DB pass over all 6993 indexed file(s)
> resolve: calls      ... whole database because this run rewrote more than one file
>                         in three (84 changed, limit 27) -- above that share the
>                         scoped pass costs more than it saves
> resolve: calls      ... this is the expensive shape (~37 min on a 2 GB index) --
>                         it is running, not hung
> ```
>
> Previously the scoped/whole line printed only on COMPLETION, so a 37-minute
> pass was indistinguishable from a wedged process for its whole duration. That
> is precisely how this note came to be filed: the run was killed at 8 minutes
> while working correctly.
>
> **The reason had to become a real value, not a guess.** `FScopeWhole` is
> latched by THREE unrelated conditions -- the one-in-three scoping limit, a
> prune/eviction FK cascade, and `--rebuild` -- and by the time the resolve runs
> they are indistinguishable. So the reason is now recorded AT the latch
> (`FScopeWholeWhy`), and `ScopedResolveIsSound` became a thin wrapper over
> `ScopedResolveDeclineReason` so the decision and its explanation cannot drift.
> The first version of the announce guessed, and named the wrong route for a
> first-index run -- caught by the test, which asserts the SPECIFIC clause rather
> than "some reason was printed".
>
> **Test:** `tests\autotest\run_index_calls_resolve_announce.ps1`. It checks both
> branches (a first index announces WHOLE-DB; touching one file of six announces
> SCOPED -- the positive control against a hard-wired string) and, critically,
> that the "starting" line PRECEDES the finished line in the stream. A text match
> alone would pass on the old behaviour, which printed after the fact. Verified
> RED against the previous build.
>
> **The refuted O(corpus) affected-set claim stays refuted:** this is the GATE,
> not the set.
>
> **STILL OPEN:** relaxing the gate for pure type ADDITIONS, so that adding new
> units to a library index does not force the whole-database pass at all. That is
> correctness-sensitive, has an equivalence hatch already
> (`DRAGLINT_NO_SCOPED_RESOLVE`), is ~1 day, and was deliberately NOT bundled
> with the announce.

# INBOX: `index <folder> --db <large.sqlite>` never finishes (2026-08-05)

Class: **wrong/performance** (not a stale index, not out-of-scope). Reproduced
twice, with and without unrelated local changes, so it is not something this
session introduced.

## Repro

```
drag-lint index C:\Projects\tpshellshock\source --db C:\Projects\.drag-lint\library-Win32.sqlite
drag-lint index C:\Projects\SysTools\source     --db C:\Projects\.drag-lint\library-Win32.sqlite
drag-lint index C:\Projects\kbmMemTable\Source  --db C:\Projects\.drag-lint\library-Win32.sqlite
```

Target DB: `library-Win32.sqlite`, schema v19, **2096 MB** -- 7726 files,
2,295,181 symbols, 3,430,565 refs, 23,603,768 `symbol_trigrams` rows.

Input is tiny: **145 `.pas` files, 4.5 MB total**; largest single file
`kbmMemTable.pas` at 685 KB.

## Observed

The rows ARE written -- after killing the runs, the DB had grown correctly:

| | before | after |
|---|---|---|
| `files` | 7726 | 7974 (+248) |
| `symbols` | 2,295,181 | 2,324,425 (+29,244) |

...and every target unit resolves (`StDrop`, `SsBase`, `StAbout`, `StBrowsr`,
`StShrtCt`, `StTrIcon`, `StStrL`, `StRegINI`, `kbmMemTable`).

But the process **never prints its `Done. Files: N, Symbols: N, Refs: N, Ns`
summary and never exits**. After the commit it sits at 100% CPU with the WAL
completely static:

```
CPU: 602.1 -> 621.2   (19.1 s CPU over 20 s wall -- fully CPU-bound)
WAL: 14.32 -> 14.32 MB (no growth over the same window)
```

Run 1 was killed after ~21 min (1246 s CPU) still on the FIRST of three
folders. Run 2 behaved identically.

## Control: it is the DB SIZE, not the input

Same binary, same folders, into a **fresh empty DB**:

| folder | files | into fresh DB | into 2.1 GB DB |
|---|---|---|---|
| `SysTools\source` | 84 | **66.9 s** | never finished |
| `kbmMemTable\Source` | 38 | **186.5 s** | never finished |

So parsing terminates fine. Something in the **post-insert phase scales with the
whole database instead of with the batch just written** -- candidates worth
profiling first: FTS5 / `symbol_trigrams` maintenance (23.6M rows), a
call-target resolution pass over the full `refs` table, or a final
checkpoint/optimize.

(Note the fresh-DB timings are themselves slow for 4.5 MB of source -- 187 s for
38 files -- so there may be a second, smaller constant-factor problem in the
parse/insert path. Separate question.)

## Impact

Incremental enrichment of a library index is effectively unusable: the only
supported way to add a source root to `library-<platform>.sqlite` becomes a full
`--scan-libraries-win` rebuild (hours). That matters because
`used-unit-not-resolvable` depends on the library index being complete -- adding
three third-party roots took this corpus from 46 unresolved units to 1.

## Workaround used

Run the command, let it commit, then kill it once `files`/`symbols` counts stop
changing. The written data is intact and correct -- the hang is strictly after
the useful work. Ugly, but it is what unblocked the DataCopy review.

## Not the cause

An unrelated `COLLATE NOCASE` change was in the binary for run 1 and reverted
for run 2; the hang is identical either way. (That change WAS a real latent
problem for a different reason -- it defeats `idx_symbols_name`, exactly as the
`CaseSensitiveLookups` remarks in `DRagLint.Storage.SQLite.pas` warn -- and has
been reverted at the one site that touched `symbols.name`. See
`docs/lint/PLAN-lint-false-positives-2026-08-03.md` B10.)
