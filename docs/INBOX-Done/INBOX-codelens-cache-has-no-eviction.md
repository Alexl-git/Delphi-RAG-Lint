> # CLOSED 2026-08-16 (session 23) -- bounded, tested, and BOTH BPLs rebuilt.
>
> `TDragLintCodeLensCache` is now capped at `CODELENS_MAX_FILES` (32) with
> least-recently-used eviction, touched on BOTH paint (`GetForLine`) and
> activation (`PopulateOnce`). Commit `5f62f21`.
>
> Two correctness details the bound exposed: `StoreForFile` must free the map it
> replaces (or the overwrite leaks exactly what the cap bounds), and
> `InvalidateFile` must drop the ORDER entry unconditionally (a stale one would
> later be chosen as a victim, evict nothing, and let the cache grow past the cap).
>
> Test `tests\CodeLensCacheLruTests.dpr`, 26 assertions, run by
> `tests\plugin\run_codelens_cache_lru.ps1`. Every eviction assertion is paired
> with a retrievability assertion, because "FileCount <= MaxFiles" is satisfied by
> a cache that stores nothing. The LRU-vs-FIFO pair was CONFIRMED RED: with
> touch-on-read neutralised and rebuilt, exactly those two fail and the other 24
> pass.
>
> **The "needs the IDE closed" blocker is discharged.** RAD Studio was confirmed
> closed and BOTH design-time packages were rebuilt (`a9b587a`) -- 37.0 registers
> a 32-bit and a 64-bit IDE separately (`Known Packages` / `Known Packages x64`),
> and the Win32 copy had been stale since 2026-08-13 because `_bpl_build.bat`
> only builds Win64. In-IDE BEHAVIOUR is still unverified; the binary is current.
# INBOX -> drag-lint engine team: CodeLens cache has no eviction (32-bit IDE RAM)

**From:** graph-viewer workstream
**Date:** 2026-08-11
**Urgency:** LOW-MEDIUM. Not a crash, not a correctness bug -- a monotonic growth
in the one process that cannot afford it.
**Class:** resource leak (bounded-by-nothing cache)

## The finding

`src/delphi-plugin/DragLint.Plugin.CodeLensCache.pas`:

```pascal
FByFile: TDictionary<string, TDictionary<Integer, string>>;
```

One inner dictionary per file, one string per line within it. The only reclaim
path is `TDragLintCodeLensCache.Clear` (line 363), which drops **everything**.
There is no per-file removal, no LRU, no size cap, and nothing hooked to the editor
closing a file.

So over a long session -- which is the normal way this IDE gets used -- the cache
grows with every unit ever opened and never shrinks until something calls `Clear`.

## Why it matters more than the size suggests

`dclDragLintWizard.bpl` is **Win32**, in-process, inside a RAD Studio that is
already tight on address space. Everything else in the plugin is admirably careful
about this and we verified it while auditing the graph viewer:

* the graph viewer is a separate **Win64** process, reparented via
  `--parent-hwnd` (`DragLint.Plugin.GraphWindow.pas:212`), with a JobObject for
  teardown;
* the LSP runs out-of-process too;
* the plugin **never opens SQLite in-process** -- no `TFDConnection` or FireDAC
  anywhere under `src/delphi-plugin/`; it resolves DB paths and shells out to the
  Win64 exe. The 2.2 GB library indexes never touch the IDE heap;
* `DragLintGraphDcl.bpl` is not even installed (registry Known Packages holds only
  `dclDragLintWizard.bpl`).

Given how deliberately everything else was kept out of the 32-bit process, an
unbounded in-process dictionary looks like an oversight rather than a decision.

## Suggested fix, in preference order

1. **Drop a file's inner dictionary when the editor closes that file.** Most
   correct, and the notifier infrastructure to hook it already exists
   (`DragLint.Plugin.ProjectNotifier.pas`).
2. **LRU cap on `FByFile`** (N files, or a total-entry budget). Cheaper, no
   notifier wiring, bounded worst case.
3. At minimum, call `Clear` on project close.

(1) and (2) compose; either alone fixes the unbounded case.

## What we did NOT verify

We did not measure actual RSS growth over a real session -- this is a code-shape
finding, not a profiled one. If you already `Clear` on some editor event we did not
find, this is a non-issue and we would rather hear that than have you patch around
nothing.

## Unrelated, for the same file's benefit

While auditing: the graph viewer is confirmed compatible with schema **v21** and
needs no update. v19 -> v21 added no tables and no columns, only three indexes
(`idx_call_edges_receiver`, `idx_symbol_docs_symbol`, `idx_symbol_facts_symbol`).
Two of those help queries the viewer already issues. Note DBs on this machine are
currently at **mixed** versions -- library at v21, project DBs at v19.
