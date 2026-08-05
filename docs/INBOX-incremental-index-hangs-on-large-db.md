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
