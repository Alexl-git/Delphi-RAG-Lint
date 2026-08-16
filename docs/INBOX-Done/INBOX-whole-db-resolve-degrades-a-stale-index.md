> # CLOSED 2026-08-16 (session 22) -- FIXED. Stale files are now left entirely alone.
>
> `ResolveCallTargets` now PRESCANS the distinct source files in its resolve
> universe and probes each against the index (raw bytes -> ANSI -> SHA2, plus
> mtime -- the same basis `FileIsUpToDate` uses). Files that no longer match are
> excluded from BOTH the delete and the resolve stream, so their existing call
> edges and receivers survive untouched.
>
> Both fix candidates 1 and 2 from below, unified: the prescan implements (1)
> exactly (only refs whose file still matches get re-derived) and `LinesOf`'s
> probe implements (2) (an unreadable file is "unknown", never "no receiver").
> Candidate 3 is done too -- the pass now prints how many files were withheld
> and says to reindex.
>
> `TCallResolver.LinesOf` / `FileIsStaleProbe`; `TCallEdge.ReceiverUnknown`;
> `ResolveCallTargets` in `DRagLint.Storage.SQLite.pas`.
> Test: `testsutotestun_resolve_stale_receiver_guard.ps1`.
>
> **Two things worth knowing for anyone touching this.**
>
> 1. Fixing the receiver write ALONE is not enough and looks like it works. The
>    first implementation withheld only `receiver_text`; the whole-DB pass then
>    still cleared and rebuilt the edge from the same bad line, so the caller was
>    destroyed anyway -- half the measured damage, silently. The delete had to
>    learn the same exclusion.
> 2. The suite's discriminating assertion is "DATA SURVIVED", not "the guard
>    fires". Verified by neutralising the prescan and rebuilding: the
>    guard-fires assertion still PASSED (the narrower receiver-level guard fires
>    either way) while DATA SURVIVED failed with `0 caller(s)`.
>
> Note also that re-indexing the DECLARING unit legitimately drops a caller's
> edge -- the target symbol id is re-issued and the FK cascades. That is correct
> behaviour and is not this defect; the fixture uses an unrelated third file
> specifically to keep the two apart.

# INBOX: a whole-DB call-target resolve DEGRADES an index whose sources have moved

Found 2026-08-11 while building the equivalence harness for the scoped
`ResolveCallTargets` pass. Not caused by that change -- it is pre-existing, and
the scoped pass is the thing that made it visible.

## What happens

`ResolveCallTargets` re-derives `refs.receiver_text` for every call-site ref it
streams, and it gets the receiver by reading the ref's **source line off disk**:

```
TCallResolver.ResolveOne -> ExtractReceiverExpr(LinesOf(Ref.FileId)[Ref.StartLine], Ref.StartCol)
```

`LinesOf` reads the file as it is on disk **now**. `Ref.StartLine` / `Ref.StartCol`
are where the ref was when that file was last INDEXED. When the two disagree --
any file edited since it was indexed -- the resolver reads an unrelated line at
an unrelated column and stores whatever it finds, usually `''`.

The pass then writes that result over the good value. It is not a failed refresh
that leaves the old answer alone; it is a successful write of a wrong one.

## Reproduction (measured)

`DragLint-Cli.sqlite` as built 2026-08-10, with `src/cli`, `src/core` and
`src/storage` edited on 2026-08-11 but NOT re-indexed. Index one file into it:

```
drag-lint index src\core\DRagLint.Core.Indexer.pas --db <copy> --force-reparse
```

| | before the run | after the whole-DB pass |
|---|---|---|
| `refs` with a receiver set | 31,164 | **20,156** |
| `call_edges` | 5,034 | **4,570** |

11,008 receivers and 464 call edges destroyed by a run whose only stated job was
to index one file. Sample of what the pass overwrote:

```
DRagLint.CLI.pas:11624:22  GetAllFileIds  'Store'  ->  ''
DRagLint.CLI.pas:14363:46  WriteAllText   'TFile'  ->  ''
DRagLint.CLI.pas:12005:97  StartLine      'Uo'     ->  ''
```

The same A/B on a **fresh** index of the same tree is row-for-row identical, in
both directions, which is what isolates staleness as the cause.

## Why it matters

`receiver_text` is what stops a bare `Create` call site being attributed to every
constructor in the index (see the v20 comment in `ResolveCallTargets`). Losing it
silently restores exactly the fabrication it was added to prevent -- and the loss
is invisible: nothing errors, counts only go down, and the next consumer sees a
confident wrong answer.

It also means the pass is **not idempotent on a stale index**, so "re-run the
resolve" is not a safe repair. Today's `--recompile` of one file in a project
whose other files have been edited will strip that project's receivers.

## Scope after the scoping change

The scoped pass (v0.86) narrows the blast radius a long way but does not close
this: it re-resolves refs in changed files plus refs naming an added/removed
symbol, and a stale-but-matching ref inside that set still gets re-derived from
the wrong line. The fallback paths (`--rebuild`, a prune, an eviction, extra
library stores, `DRAGLINT_NO_SCOPED_RESOLVE=1`) take the full-corpus path and so
retain the full exposure.

## Fix candidates, cheapest first

1. **Only re-derive the receiver for refs whose file this run re-indexed.** For
   every other ref the stored value was computed against the source that produced
   the ref, and is by definition the right one. This looks like a strict
   improvement and would also delete most of what the pass writes -- the receiver
   `UPDATE` fires once per streamed ref today, resolved or not.
2. **Refuse to read a file whose sha/mtime no longer match `files`.** The store
   already keeps both for the incremental skip. On a mismatch, leave
   `receiver_text` alone rather than overwrite it with a guess.
3. Make the staleness visible: one line naming how many indexed files no longer
   match their recorded sha. Related to
   `INBOX-lint-scope-stale-files-and-project-members.md`.

(1) and (2) are independent and compose; (2) is the safety net for every other
consumer of `LinesOf`.

## Repro artefacts

`C:\TEMP\claude\cmpcalls.py` (row-by-row, small DBs) and `cmpcalls_sql.py`
(ATTACH + EXCEPT, for the 2 GB indexes). Both take two databases and compare
`refs.receiver_text` / `external_target` and every call edge keyed on
(file path, line, col, name) so re-issued symbol ids do not register as
differences.
