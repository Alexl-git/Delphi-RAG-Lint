# DB authority and freshness

**Owner ruling, 2026-08-13.** Status: SPEC. Not implemented.

## The rule

The only databases that hold reliable, workable information are:

1. **the platform library DB** -- `C:\Projects\.drag-lint\library-<Platform>.sqlite`
2. **the project DB** -- built ONLY from that project's member units, which may
   live in several folders

Everything else -- another project's DB above all -- is noise and misleading, and
is not to be consulted. For now: disallow, do not merely deprioritise.

Both are authoritative **only while the project DB is fresh**. A stale DB is not
authoritative; the answer is to rescan, not to report.

## Authority is per-QUESTION, not per-database

This is the part that is easy to get wrong, and getting it wrong is what produced
the incident this ruling comes from.

| Question | Project DB | Platform Library |
|---|---|---|
| Which unit declares symbol X (`find-unit`, type resolution, `uses` repair) | yes | **yes -- this is what it is FOR** |
| Who calls X / which units use this unit (doc facts, `find-callers`) | yes | **NO** |

A name match against the RTL is not a caller. On 2026-08-13
`document --project YADFOT.dproj` wrote

```
Used in units: dxXMLWriter, FireDAC.Comp.QBE, Spring.Data.ExpressionParser,
               System.Bindings.Evaluator, System.JSON, XPTestedUnitParser, ...
```

into shared source, where the project renders four real units. None of those
names exist in YADFOT's own index. They came from the library DB via
`Doc.Facts.pas:1947`, which does a bare `FindCallersByName(LastSeg(QName))`
against every extra store **with no ambiguity gate**, unlike its `Called from:`
sibling at `:1669` (`NameUnambiguous and LeafNameNotAmbiguous`, every hit marked
`unverified`).

**Implementation order matters.** `8abcc3e` currently excludes the library DB
from the fan-out as a side effect of going explicit-`--db`-only, and that is why
YADF/YADFOT/YADFSetup now reach a stable fixed point. Restoring the library DB as
a fact source BEFORE gating that bucket re-introduces the junk and breaks the
fixed point. Gate first, prove the fixed point holds, then widen.

## Freshness

### What already exists -- do not rebuild it

* `ISymbolStore.FileIsUpToDate(APath, AMtimeUnix, ASha)` -- per-file mtime + sha
  comparison, already the indexer's incremental test.
* `ISymbolStore.GetFileMTime(AFileId)` -- the stored mtime.
* `GetAllFileIds` + `GetFilePath` -- enumerate the DB's members.
* `GetMetaValue` / `SetMetaValue` -- a generic DB-level key/value table. Today it
  carries exactly one key, the indexer fingerprint (`CLI.pas:2385`).

So the per-file half of the checker is assembly, not new storage.

### What must be added

1. **A DB-level last-indexed stamp.** `SetMetaValue('indexed_at_unix', ...)` at
   the end of every successful index run. Cheap, and it gives a single fast
   answer before any per-file walk.
2. **The member-unit set as the source of truth for the sweep.** The project DB
   is defined as its member units, so freshness is asked about THOSE, not about
   whatever rows the DB happens to hold. This matters: YADF's DB reports 18 files
   where the compile closure is 9 -- the rest are ghosts that no reindex evicts
   (`docs/INBOX-ignored-files-already-indexed-are-never-evicted.md`). A freshness
   check driven by DB rows would ask about ghosts; one driven by member units
   would not.
3. **Unsaved IDE buffers count as modified.** A unit open in the IDE with
   unsaved edits is, for every purpose the user cares about, newer than the DB --
   its mtime on disk says otherwise, so mtime alone silently reports "fresh"
   about source that no longer exists as indexed. Only the plugin can see this:
   the OTA exposes the editor buffer and its modified flag
   (`IOTASourceEditor` / `IOTAEditBuffer.IsModified`). The CLI cannot, so the
   contract must be explicit about which side answers.

### Verdicts

Three outcomes, and they are not the same:

* **FRESH** -- every member unit's mtime/sha matches, no unsaved buffers.
* **STALE** -- at least one member unit is newer, or the DB stamp predates a
  member unit. Action: rescan the changed members incrementally, then answer.
* **UNKNOWN** -- the DB has no stamp (pre-upgrade), or a member unit is missing
  from disk. Action: say so; do not report UNKNOWN as FRESH.

A checker that folds UNKNOWN into either of the other two is worse than no
checker, because it converts "I do not know" into a confident answer.

### Open, to be decided before implementing

* **Where the gate lives.** Per-consumer-command (each of `query`, `find-unit`,
  `context`, `lint-all`, `document` checks) or once in DB resolution? Once is
  cheaper and cannot be forgotten; per-command allows `--allow-stale` for the
  cases where a fast wrong answer beats a slow right one.
* **What a failed gate does:** refuse, warn-and-continue, or auto-reindex.
  Auto-reindex is the friendliest and the most surprising -- a query that
  silently rewrites a 1.4 GB index is not a query.
* **Cost.** A per-file sha over every member on every command is not free. The
  DB-level stamp plus mtime-only comparison is the fast path; sha is the
  tiebreaker when mtime is equal but size differs.
* **Does this retire explicit multi-`--db` cross-project callers?** That path
  exists precisely to surface an ORM3 `COMMON` reference
  (`Doc.Facts.pas:1661-1705`). It is unverified by construction, so retiring it
  may be right -- but it should be a deliberate retirement, not a side effect of
  a resolution-rule change. **ASK.**

## Consequences elsewhere

* `C:\Projects\CLAUDE.md` -- updated 2026-08-13 for the authoritative set,
  per-question authority, and the freshness requirement.
* `drag-lint resolve-dbs` should report the verdict alongside each path, so
  "which DB" and "is it usable" are one question.
* The IDE plugin is the only component that can answer the unsaved-buffer half.
