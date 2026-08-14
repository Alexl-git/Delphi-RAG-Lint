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

---

## Owner answers, 2026-08-13 (second pass)

* **Refresh, do not full-reindex.** Only (a) units held unsaved in the IDE and
  (b) units post-dating the DB.
* **ORM3 CLIENT and SERVER each have their own DB.** The only interference is
  AutoDoc, and the `dl:shared` unit tag resolves it. So cross-project `--db`
  is not needed for that case.
* **Same interface implemented by different classes per project** should be
  handled by the independent-DB model.

## Remaining concerns, in the order they will bite

### 1. The rule makes every shared unit's public API look dead -- ALREADY FIRING

This is the direct, measured consequence of "no cross-project DB". With per-project
DBs and no fan-out, a public symbol in a shared unit that is only called from
ANOTHER project has zero callers in this project's index, so
`unused-public-symbol` fires. Recorded precedent: YADF reports
`SaveOptionsToIni` unused while it has 15 call sites in a unit only
YADFOT/YADFSetup compile. Live counts right now: **YADFOT 2, YADFSetup 5**.

`dl:shared` currently affects DOC FACTS ONLY. It does not soften this rule.
That was deliberate for v1 ("one mechanism changes one behaviour"), but the
ruling has now removed the other half of the information, so the decision is due.
Options: have `dl:shared` suppress the rule for exported symbols in marked
units; or a `dl:api` marker; or accept and `allow`. **Do not reach zero by
`allow`-ing these -- they are true positives about the wrong question.**

### 2. Same problem, one level up: interfaces implemented per project

An interface declared in a shared unit and implemented by a different class on
CLIENT and on SERVER is, in each DB, an interface with ONE implementor. Any rule
reasoning over implementors sees a partial picture -- `unused-public-symbol`,
`interface-reference-cycle`, and the layering checks. The independent-DB model
does not by itself make this correct; it makes each DB internally consistent and
mutually blind. Decide whether that blindness is acceptable per rule, or whether
those rules need the same marker-based opt-out as #1.

### 3. "Post-dates the DB" is not sufficient as a freshness test

A file restored from backup, a `git checkout` of an older revision, or a clock
skew all produce an mtime OLDER than the DB with DIFFERENT content. That is why
`FileIsUpToDate` takes mtime AND sha. Use "differs from what was indexed", not
"is newer than". Mtime is the fast path; sha is the decider when mtime is equal
or older but size/content differ.

### 4. Indexing an unsaved buffer poisons the DB for the CLI

If the plugin refreshes an in-RAM buffer INTO the project DB, the DB then holds
symbols that exist in no file on disk. The next CLI run compares disk mtime/sha,
sees a mismatch, and re-indexes back to the saved version -- so the two clients
fight, and a lint run from the command line silently contradicts the IDE.
Options: keep buffer-derived rows in a per-session OVERLAY rather than the shared
DB; or mark them provisional with the buffer's hash and have the CLI ignore
provisional rows. **Decide before implementing the refresh**, because writing
buffers into the shared DB is very hard to walk back.

### 5. The last 6 doc-drift are still the `(+N more)` remainder

Unaffected by any of the above. 12 truncated inbound lines across the shared
units; the merge refuses them because a window onto a list is not the list.
Either raise `docs.max_callers` (currently 5) above the real caller counts, or
teach the merge to reconcile truncated lists by count.

### 6. Reaching a true zero is mostly NOT autofixable

Of the 71 remaining across the three YADF projects, only `doc-drift` and
`local-var-casing` are fixable by the engine -- and `local-var-casing`
(7 + 7) has NOT been run yet. The rest need triage: `try-except-swallowed` 16
on YADFOT, `object-leak`, `used-before-assignment`, `unit-too-large`,
plus the `unused-public-symbol` set from #1. YADF has real unit coverage
(`GuardTest.dpr`, `OptionsTest.dpr`), so source fixes there are verifiable;
YADFOT is a design-time BPL and is compile-only.
---

## Owner answers, third pass -- and one concern WITHDRAWN

### Concern 2 is WITHDRAWN. It was wrong.

The claim was that an interface implemented by different classes on CLIENT and
SERVER leaves each DB with a partial picture. It does not. Each project compiles
the interface AND its own implementation AND its own call sites, so each DB is
COMPLETE and self-consistent for that project -- and "one implementor" is the
correct answer for that project, not a missing one. COMMON\OBJECTS interfaces
used 1000+ times in each of CLIENT and SERVER are fully represented in both.

The only shape that would still bite is a rule advising "this interface has a
single implementor, consider removing it". No such rule appears in the observed
findings. Nothing to do.

### DB ROLE, not just DB identity -- the owner's refinement, and it is better

The tension in concern 1 was: dropping cross-project DBs is required to stop
noise, but it is also what makes shared-unit public API read as dead. The
resolution is to classify each DB by the ROLE it plays, and let role decide which
questions it may answer:

| Role | May answer | Must NOT answer |
|---|---|---|
| **Library** (`library-<Platform>.sqlite`) | which unit declares X; type resolution | who calls X; used-in-units |
| **Project** (this project's own) | everything, authoritative | -- |
| **External / sibling project** (explicitly declared, "extra documentation only") | INCOMING facts only: `Called from:`, `Used by:`, `Used in units:` | declaration lookup, type resolution, any finding |

This is exactly the distinction the 2026-08-13 incident violated: the LIBRARY DB
was allowed to answer an INCOMING-facts question, which is the one thing it must
never do, and that is where `dxXMLWriter`/`FireDAC`/`Spring`/`System.JSON`
came from. Role-scoping fixes that WITHOUT losing cross-project inbound facts --
so it also addresses `unused-public-symbol` on shared units, because an
external role DB can supply the missing callers.

**Prerequisite unchanged:** the ungated `Used in units:` bucket
(`Doc.Facts.pas:1947`) must be gated first. Roles decide WHICH DB may
contribute; the gate decides whether a name match is evidence at all.

### Concern 3 -- accepted, with a stated budget

Any mismatch between DB and source triggers a COMPLETE reindex. Time it: the
budget is **under 2 minutes**; consider multi-threading for large projects.
Note the existing ghost-row problem: only `--rebuild` evicts rows for files
that left the compile closure, so "complete reindex" must mean rebuild
semantics, not `--force-reparse` (which parses 9 files while the DB reports 18).

### Concern 4 -- OPEN, owner wants it thought through

Direction: re-address ALL indexing to the in-memory data, so there is one source
of truth rather than a disk index that the IDE's buffers silently contradict.
This is an architectural change, not a patch. Do not implement the unsaved-buffer
refresh until it is designed.
### Refinement: DESTINATION is a third axis, and OUTGOING vs INCOMING is the line

"Library must not answer who-calls-X" was too blunt. The owner's correction:

* We MAY ask the library DB who uses `Max(Int, Int)` and where. That answer is
  legitimate **for an IDE popup**. It may **never** be written into documentation.
* What MAY be documented is that our own `HugeValues` **calls** the library
  function `MAX` -- and that is the total extent of it. That is an OUTGOING
  call fact, not an incoming one.

So three axes govern every query, not two:

| | Library | Project | External |
|---|---|---|---|
| declaration / type resolution | yes | yes | no |
| OUTGOING facts (`Calls:`) | yes -- naming an RTL callee is true and useful | yes | no |
| INCOMING facts (`Called from:`, `Used by:`, `Used in units:`) -- **persisted to source** | **NEVER** | yes | yes (this is its only job) |
| INCOMING facts -- **interactive display only** (hover, popup, `find-callers` at the console) | yes | yes | yes |

**Why outgoing is safe and incoming is not.** An outgoing fact is anchored in OUR
source: the call site is in a unit this project compiles, so the project's own
index already records it, and the library DB is needed only to RESOLVE the callee
-- which is the declaration-lookup role already granted. An incoming fact sourced
from the library is the reverse: it asserts something about code we do not own,
discovered by an unverified name match, and then welds it into our source. That
is exactly how `dxXMLWriter` and `FireDAC.Comp.QBE` reached YADF's shared
units.

**The operative test is therefore not "which DB" but "does this fact get
WRITTEN?"** A fact that is rendered and discarded can afford to be speculative;
a fact that is committed to a `.pas` file cannot. Any future surface that
persists what a hover currently only shows inherits this rule.