<!-- dl:backlog status=open last-measured=2026-09-28 -->
# STATUS: the 27 diagram questions

The live scoreboard for `charts\question-catalogue.md`. **27 catalogue rows**
(`protocol-trace` appears twice -- field and method are different questions).

Updated 2026-09-29. Branch `feat/archify-ir`, 92 commits ahead of its merge-base with `main` (4ccd1779) at 65e1419c, before this documentation commit (measured: `git rev-list --count <merge-base>..HEAD`), no remote branch, NOTHING PUSHED.

```
SHIPPED                     26   emitters exist, tested; chart rows and round-trip @file:line anchors are draglint:// links
PLANNED (ready to build)     0
UNPLANNED, unblocked         0
BLOCKED on data              0   consumers / feeds-from / lands-where ship DERIVED (path A)
BLOCKED on the engine        0   exception-paths ships on a source-token classifier
PARKED by owner              1   compare
                            --
                            27
```

**26 of 27 ship; only `compare` does not, by owner decision.** The last four
(`exception-paths`, `consumers`, `feeds-from`, `lands-where`) shipped on
2026-09-23 under `PLAN-last-four-verbs.md`, NOT because the missing facts
arrived: they are built from facts that DO exist, and each chart says which of
its hops are `[inferred]` and what it cannot see. Their caveats are in the
table below and must travel with any claim that "the catalogue is done".

**Selection kinds: method / unit / form-class / field / property / type /
interface / project / command constant / wire field / db column / any symbol.**

---

## SHIPPED (26)

| question | selects | emitter | measured |
|---|---|---|---|
| `butterfly` | method | `Emit-Butterfly.ps1` | 9 callers / 9 callees, 19 anchors |
| `deps` | unit | `Emit-Deps.ps1` | 3 used-by / 18 uses |
| `who-calls` | method | `Emit-WhoCalls.ps1` | 10 sites + 1 cycle @d3 |
| `what-it-calls` | method | `Emit-WhoCalls.ps1 -Direction callees` | 2/9/18 rows @d1/d2/d3, 5 cycles |
| `who-writes` | field / property | `Emit-MemberAccess.ps1 -Mode write` | R: 7 writes over 3 routines |
| `who-reads` | field / property | `Emit-MemberAccess.ps1 -Mode read` | Connected: 602 reads / 598 routines |
| `hierarchy` | type | `Emit-Hierarchy.ps1` | 145 descendants, 2 ancestors (1 RTL) |
| `class-surface` | type | `Emit-ClassSurface.ps1` | 392 members over 2 visibility clusters |
| `event-wiring` | form class | `Emit-EventWiring.ps1` | 41 events / 41 handlers / 40 controls |
| `touches-tables` | method | `Emit-TouchesTables.ps1` | 5 read / 5 written / 2 both |
| `lifecycle` | form class | `Emit-Lifecycle.ps1` | uMain: 2 wired / 1 implemented-not-wired / 4 absent |
| `cycles` | unit / project | `Emit-Cycles.ps1` | CLIENT 2 groups / 5 edges; DL's SCC 7 edges; DataCopy 0 |
| `wiring` | interface | `Emit-Wiring.ps1` | SERVER 2 regs / 4 sites of 535; CLIENT 1 of 4 |
| `effects` | method | `Emit-Effects.ps1` | pure / not-analysed / `g,p0,p3,?` over 6 params |
| `architecture` | project | `Emit-Architecture.ps1` | 563 units / 3 zones / 2,858 edges / 3 back-edges |

| `protocol-trace` | command / wire field | `Emit-ProtocolTrace.ps1` | cmdDelta 38 refs / 2 zones; CommandID 1,043 / 727 routines |
| `protocol-trace` | method | `Emit-ProtocolTrace.ps1` | CommandIDToStr speaks all 42 TCommandID members |
| `crosses-boundary` | method | `Emit-CrossesBoundary.ps1` | crosses (2 cmds / 1 transport / 18 far) &#183; is-the-boundary &#183; no-evidence |
| `shown-where` | db column | `Emit-ShownWhere.ps1` | FTRNAMESTR 4 bindings / 2 forms, of 903 over 459 columns |
| `change-impact` | method / type | `Emit-ChangeImpact.ps1` | 9 routines / 1 unit; a TYPE reaches 591 over 174 units (capped) |
| `tested-by` | any symbol | `Emit-TestedBy.ps1` | 11 / 8 / 13 covering tests, computed from 71 test methods |

| `exception-paths` | method | `Emit-ExceptionPaths.ps1` | BuildSchema: EDatabaseError caught at LoadAllAsync:632 (call inside the try); ReadBuffer: caught on 2 edges, escapes on 3 path ends; 140 callers walked, 139 evaluated for EReadError |
| `consumers` | table / column | `Emit-Consumers.ps1` | CAUSFAIL (SERVER): 1 certain reader, 1 certain writer, 3 triggers; FOLDERS 3 inferred readers; FOLDERS 2 declarations, newest 79 columns. Multi-line `SQL.Add` (engine D18) is covered by the engine's `sql_reads` fact plus the column form's span search (gate `A-CO-D18-COVERED`; 0 statements left for a charts-side join, `A-CO-D18-LINES` 5/0). The column form REFUSES a column whose state is `[stale source]` (not extracted, and the newest declaration's script differs from the index, so it is NOT known): "consumers: cannot tell whether T.C is a column -- [stale source] not extracted as a column by the SQL index (...); X.SQL differs from the indexed copy, so it was not scanned for a quoted identifier -- whether C is a column of T is NOT known. Script-derived; the scripts may lag the live schema." (gate `CO-STALE-REFUSE`: INSPRSLT.DISTHIST over a manufactured stale MS1.SQL) |
| `feeds-from` | control | `Emit-FeedsFrom.ps1` | colREASON: 5 graded hops to CAUSFAIL.REASON; 471 of 808 field-bound CLIENT controls reach one table (267 before the dangling-datasource re-point was followed, 2026-10-05) |
| `lands-where` | ORM property / field / control | `Emit-LandsWhere.ps1` | TmcCAUSFAIL.REASON: 4 server rows, 1 trigger, 1 client binding; convention 1,992 of 1,997 |
| `round-trip` | control / field / TABLE.COLUMN | `Emit-RoundTrip.ps1` | OPERAT.NAME from frmBlueprint4.dxDBGrid1OperationVName: 17/17 golden nodes matched, 3 golden facts disclosed (READ [28]-[29], transport helpers at uPipeSessionBuilder.pas:533/:534/:538), 12/12 guards; 76 steps / 31 conditions / 4 crossings / 2 unresolved (the statement for the posted row and the SELECT STOPS, both E4); ALSO 9 (owner-accepted 2026-09-28: all callers count; dataset scope; anchors only). Limits: guards see the innermost enclosing `if` only (E1); OMITS tests every enclosing `if` up to a loop or case arm; statement texts are FIB$ rows the clones do not hold (E4). A direction that stops after the anchor notes its un-walked tiers and the title claims only the walked direction (`RT-NOWIRE`: frmAssignGroups.grdFtrsColNum, 33/10/2/2). TEXT bundle (`trace.dlgraph`; the page links each anchor to the IDE, 126/126 here -- DOC-R1), no chart yet |
| `round-trip` (holdout, AC-16) | control | `Emit-RoundTrip.ps1` | MSCLIST.NUM from frmBlueprint4.dxDBGrid1FtrsVNum through FMTFtrs / SendDeltaFtrs (a different dataset and sender than OPERAT.NAME; the re-point at Blueprint4.pas:2283 recovered from source, P29): 103 steps / 35 conditions / 4 crossings / 2 unresolved, pinned by gate `RT-HOLD`. Owner-accepted 2026-09-28: the owner checked the path's shape against the OPERAT.NAME trace and the golden, not every line. FtrName (the plan's default) was not used: it is one of 12 calculated fields added to FMTFtrs after BuildMemTable (Blueprint4.ViewModel.pas:748-761), no DB column -- its trace now OFFERS ITS SOURCES (calc-field brief, owner 2026-09-28) |
| `round-trip` (calculated field) | control | `Emit-RoundTrip.ps1` | frmBlueprint4.dxDBGrid1FtrsVFtrName: a calculated field (written by FtrsOnCalcFields, Blueprint4.ViewModel.pas:986-993) -- the STOPS says so with its guards verbatim, and DERIVED offers its 18 source fields (17 TField variables + the local FtrType, one hop), each with a ready command; 27 steps / 2 conditions / 0 crossings / 1 unresolved. Tolerance: 4 source fields + 2 case selectors (fix round 1), 15/2/0/1. InspAsVarStr (every write a constant): the 2 fields its ifs test, 6/8/0/1; USLLSLName: 2 value fields + 3 that choose it + 1 unmappable local, 10/8/0/1 (fix round 2). Row commands are `& '<absolute path>\New-DiagramArtifact.ps1' ...`, runnable as written. The DimAbbr row's command run end to end: MSCLIST.DIMABBR, 98/35/4/2. Pinned by gate `RT-CALC` |

**The caveat each of the last four ships with** -- say it whenever the chart is
quoted:

* `exception-paths` -- the index has NO raise/handle ref kind. Each exception
  ref is CLASSIFIED from the source token before it (`raise` / `on E:`) on a
  file whose sha256 still matches the index; source-only rows (bare `except`,
  `raise;`) are `[inferred]` with directive state not evaluated. A solid catch
  needs the call site inside the handler's `try`. The caller walk is over
  resolved call edges only, so a call the resolver cannot bind (interface /
  event dispatch; parenless calls until engine D1 was fixed in resolver 1.7/1.8)
  thins it; a walk that ends says "no resolved caller", never "unhandled".
* `consumers` -- derived, path A (`orm_links` / `fb_*` are 0 rows): SQL facts
  `[certain]`, upper-case SQL-verb literals `[inferred]`, because `sql_reads`
  misses SQL passed through a variable (`SQL.Add(sTmp)`: 38 of the 40 SERVER
  DataService loads still without a read fact; the multi-line `SQL.Add` gap,
  engine D18, is fixed in extractor 1.19). The schema is the SQL SCRIPTS,
  collapsed on name with the newest file winning -- 5 live `PDF_*` tables are
  absent. `[by name]`
  literals (equal to the table name, exact case) are MENTIONS, drawn in a
  neutral cluster with no read arrow (R15); case-only matches are counted and
  named, not drawn. The header counts reading / writing ROUTINES; unit-level
  SQL literals are counted per unit, apart.
* `feeds-from` -- DFM DataSource -> dataset -> view model -> TABLE.COLUMN, every
  hop graded; past a DANGLING designer datasource it FOLLOWS the code re-point
  (2026-10-05, Task 2: the round-trip's own walk, `Resolve-RePointTable` --
  member, accessor, field, `DataSet :=`, the dataset, the table literal beside
  it, each hop graded as round-trip grades it); it STOPS (never guesses) when
  the owner is re-pointed at several sites with different right-hand sides,
  when it has no re-point site, on an interface-typed view model or several
  candidate tables, and a stale file on the way stops `[stale source]`. Table-name literals match in UPPER
  case (the SQL convention); a literal equal to a table name only
  case-insensitively (`'DueIN'`, a computed-field name) is named on the hop and
  not taken -- measured, every such literal on CLIENT is not a table reference. Measured coverage per control, not
  per datasource: 471 of 808 reach one table (267 before the re-point was
  followed). Of the 426 under a dangling module, 204 reach a table through the
  re-point, 215 stop on the way, 3 are re-pointed with several different
  right-hand sides, 4 have no re-point site (gate `A-FF-REPOINT-AGG`).
* `lands-where` -- the TABLE.COLUMN hop is a naming CONVENTION
  (`Tmc<T>.P` -> `T.P`), drawn `[inferred]` with its coverage measured and
  printed on every chart (1,992 of 1,997). Reads THREE clones (CLIENT, SERVER,
  SQL).

**Column states** `consumers`, `feeds-from` and `lands-where` can show for a named
column -- decided by ONE function, `Get-SqlColumnState` (Emit-Common), so the three
cannot disagree, in this precedence order:

| state | means |
|---|---|
| `column` | extracted as a column of the newest script declaration of the table |
| `quoted` | a QUOTED identifier in the newest declaration that the SQL index does not extract, found by a source scan, `[inferred]`. Engine D19 (`INBOX-sql-index-drops-quoted-identifiers.md`) is FIXED in extractor 1.19: `"TABLE"` (FOLDERCOUNT, MS1.SQL:3848) and `"ACTION"` (IPCHART, :2243) are now `column`, so no real column reaches this state; it is kept as a guard and driven synthetically by the gate (`A-COLSTATE-QUOTED`) |
| `older-only` | extracted only from an OLDER declaration of the table; not extracted from, nor quoted in, the newest |
| `server-sql` | not extracted, not quoted, but SQL in the Delphi index names it (`STATIONS.GRIDS`; lands-where searches the server DataService, consumers every routine of `-DbPath` that names the table) -- the scripts lag the schema |
| `[stale source]` | the newest declaration's script differs from the indexed copy, so it was NOT scanned for a quoted identifier -- whether it is a column is NOT known; never rendered as an absence -- lands-where says so on the column box, consumers REFUSES ("consumers: cannot tell whether T.C is a column -- [stale source] ...") |
| `not-a-column` | not extracted, not quoted, named by none of the SQL searched: lands-where says computed or UI-only (`INSPRSLT.DistHist`) -- or, with no TDataService_<T>_SERVER to search, that no DataService was searched and the field is NOT known, consumers refuses ("not extracted as a column by the SQL index ..."), feeds-from counts it `not-column` |

**Twenty-six questions, TWENTY-THREE emitters** -- `what-it-calls` is a `-Direction`
switch, `who-writes`/`who-reads` are one `-Mode` switch, and both
`protocol-trace` rows are one emitter dispatching on the selection's kind. Say
it that way: counting emitters as questions understates the result, counting
questions as emitters overstates the work.

Gate: `charts\src\Test-Emitters.ps1` (exit 0 = green). Proven to fail correctly
on every batch -- see each commit for the mutation it was checked against.

## Engine defects the shipped charts disclose (2026-09-23; re-baselined 2026-09-24)

From `C:\Projects\Delphi-RAG-lint\docs\INBOX-defects-found-2026-09-23-rule-work.md`.
Each was MEASURED on the clones; none is worked around silently. Extractor 1.19 /
resolver 1.8 FIXED D1, D12, D13, D18 and D19: a fixed limit is no longer claimed
on a chart, and each detector stays as a guard (R25).

| defect | affects | what the chart does |
|---|---|---|
| D1 parenless free-function calls were never bound (`N := NextId;`) -- FIXED, resolver 1.7/1.8 (CLIENT call edges 20,409 -> 23,790; e.g. `NextSeq`, `ResolveLogDir` now appear) | every caller/callee walk: `butterfly`, `who-calls`, `what-it-calls`, `change-impact`, `exception-paths` | walks follow resolved edges only; a call the resolver cannot bind is still absent, so a short list is a lower bound |
| D6 butterfly listed duplicate callee rows | `butterfly` | **FIXED here** -- rows are distinct symbols, arrows follow the engine's tree (a hop-2 callee is no longer drawn as called by the focus); gate `A-BF6-*` fails on any duplicate |
| D12 own-name result assignment scored as a GLOBAL write (31 CLIENT functions on 1.18, e.g. `Ap.AP_FP_Greater_Eq`) -- FIXED, extractor 1.19 (0 on every clone; `AP_FP_Greater_Eq` is now pure) | `effects` | guard kept: when the witness is "writes <own name> (non-local)" the `g` moves to a dashed "engine D12" disclosure (driven synthetically, `A-FX12-DETECT`) |
| D13 `write` refs never got a symbol_id (32,909 of 32,909 on CLIENT at 1.18) -- FIXED, extractor 1.19 (21,916 bound) | `who-writes` | the fix gave a bound write NO member-access row (0 of 21,916), so `find-callers` did not report a bare in-class write and the chart disclosed them as "bound, not reported" -- RETIRED 2026-09-27: engine 1.18 (D31) reports them, so `FConnected`'s writes at uPipeClientConnection.pas:164/320/455/543 are its writers wing; what 1.19 leaves unbound (a write in a `with` body, `fLOTSIZE` at uPLANLIST.PAS:2547; bare in-class READS, `FNoRecursion` 9) is listed by name. Both directions, on every mode and in the bundle header: nothing claims zero beside a population the index holds (ruling R26) |
| D18 `sql_reads` misses SQL split over `SQL.Add` lines -- FIXED, extractor 1.19 (SERVER read facts 19 -> 112) | `consumers`, `touches-tables`, `lands-where` | `PrepareLoadQuery` on CAUSFAIL is now a `[certain]` reader; literals stay `[inferred]` beside the facts for SQL passed through a variable (FOLDERS: 3 inferred readers) |
| D19 quoted identifiers not extracted -- FIXED, extractor 1.19 | `consumers`, `feeds-from`, `lands-where` | `FOLDERCOUNT.TABLE` / `IPCHART.ACTION` are ordinary columns; the `quoted` state is a guard |

## NOT SHIPPED (1)

| question | selects | why |
|---|---|---|
| `compare` | two index runs | parked by owner; no `ir` or `compare` verb exists in the deployed engine |

## HISTORY: blocked on data (resolved 2026-09-23 by deriving, path A)

The three rows below were blocked on `orm_links` / `fb_*`. They now ship from
DFM bindings + Delphi SQL literals + the SQL-script index instead; `orm_links`
stays at 0 rows and is only DETECTED (`A-OL-ROWS`), as the switch for path B.
The original text is kept for the record.

`orm_links` / `fb_*` are written by `drag-lint fb-snapshot`, which opens a
**live TFDConnection**. Engine session confirmed 2026-09-22. They are empty by
construction in a pure Delphi index and cannot be planned as if they were
near-term.

| question | selects | needs |
|---|---|---|
| `lands-where` | field | `orm_links` -- 0 rows everywhere |
| `feeds-from` | control | `orm_links`, `fb_datasets` -- 0 rows |
| `consumers` | table / column | `fb_columns`, `fb_relations` -- 0 rows |

**Effort is unknowable until the ingest runs.** The work is the fb-snapshot
ingest, not the chart.

## HISTORY: blocked on the engine (all four shipped)

| question | selects | waiting on |
|---|---|---|
| `protocol-trace` | field / property | enum-value ref binding (GAP 1) |
| `protocol-trace` | method | GAP 1 + branch ranking |
| `crosses-boundary` | method | GAP 1 |
| `exception-paths` | method | raise/handle fact (GAP 2) |

Interim: keep the `[inferred]` dashed-edge convention.

### >>> GAP 1 IS NOW CLOSED IN THE DATA (measured 2026-09-23, 07:0x) <<<

`INBOX-enum-value-refs-never-bound.md` was RETIRED into `INBOX-Done` at 07:01
with: *"RETIRED 2026-09-23 by resolver 1.6.0-alpha (branch feat/enum-value-refs):
enum-value reads bind by name + scope, certain or NULL; find-callers --resolved
reports them [certain, read]."*

Our corpus is already re-resolved at `r=1.6.0-alpha`, so **the bindings are
present in the clones right now.** The original reproducing case, re-measured on
the CLIENT clone:

| | before | now |
|---|---|---|
| `cmdDelta` refs / bound | 38 / **0** | 38 / **38** |
| `cmdTableLoad` refs / bound | 42 / **0** | 42 / **42** |
| refs bound to an `enum_value` | -- | **5,983** over 592 enum_value symbols |

**But our 1.5.1 engine cannot surface them**: `find-callers --name cmdDelta
--resolved` returns `[]`, because the union arm that reads enum-value bindings
is 1.6.0 code we do not have. Plain name-match `find-callers` still works.

So for `protocol-trace` x2 and `crosses-boundary` the position is now:

* **the fact exists and is queryable by raw SQL over `refs` today**;
* **the verb-level route needs the redeploy.**

An emitter for these built on SQL rather than on `find-callers --resolved` is
buildable NOW. That is a decision for whoever picks them up -- it is recorded
here because "blocked on the engine" is no longer the whole truth.

### >>> DO NOT INDEX ANYTHING. Engine reply, 2026-09-23 <<<

**The resolver re-resolve is version-gated, and OUR engine is on the OLD side
of the gate.** `DRAGLINT_RESOLVER_VERSION` moves 1.5.1-alpha -> 1.6.0-alpha for
the enum binding. Once a corpus DB has been re-resolved under 1.6.0, **an
`index` run from any engine still on 1.5.1 re-resolves it BACK and drops the
enum bindings.** It announces it (`resolver: edges were derived by 1.6.0-alpha,
this build is 1.5.1-alpha`) and redoes the pass.

The archify-ir engine at `third_party\dll-win64\drag-lint.exe` **is 1.5.1**
until that branch merges and `main` redeploys.

Nothing is corrupted and it is recoverable by re-running the 1.6.0 pass -- but
it would look exactly like the feature not working, and we would be the ones
who broke it. The STOP list already forbids `drag-lint index`; this is now the
strongest reason for that rule, not a second one. `delphi-rag-lint-75` will say
when the corpus pass and the redeploy have happened.

### The new fact's shape, settled -- plan against it now

* `refs.symbol_id` bound to the `enum_value` symbol; confidence `certain` or
  left NULL, never a guess laundered into the column.
* BOTH shapes bind: bare (`cmdDelta`) and qualified (`TCommandID.cmdDelta`,
  `Pipes.Protocol.cmdDelta`).
* Explicitly NOT: no `call_edges` row, no `member_accesses` row, no new table,
  no `SCHEMA_VERSION` move, no extractor move.
* So `FindReferencesTo` / `GetReferencedSymbolIds` answer for enum values for
  free, and `find-callers --resolved` grows ONE union arm -- which is the verb
  our `who-writes` plan already builds on.
* Enum-value rows carry **`mode = read`** (the literal string) for both shapes.
  Confirmed against the spec's own sketch, which would have emitted
  `member-access` for the qualified shape; the owner's ruling says `read`.
* Re-resolve cost, measured: ~6 min for project sections, ~74 min per platform
  library. It is a re-RESOLVE, not a re-parse.

Status: implementation under way on `feat/enum-value-refs` (9-task plan, 2
done, guard RED as designed). Our reproducing case confirmed exactly as filed:
CLIENT `cmdTableLoad` 42 / `cmdDelta` 38, SERVER 2 + 2, every one `bound = 0`.
GAP 2 (raise/handle) is NOT touched by this change and they declined to guess.

---

## HISTORY (superseded 2026-09-27): the engine WAS ahead of our binary on 2026-09-23

**Superseded.** Since 2026-09-27 (Task 0 of the trace-core plan) every emitter runs the
SHARED deployed engine `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`
(1.18.x-1.20.x over the trace-core branch -- run `--version` for the one deployed
now), and the clones carry `v=1.20.0-alpha / r=1.11.0-alpha` (re-taken 2026-09-28;
the r=1.9 set is kept as `*.sqlite.pre-1.10`). What follows is the 2026-09-23 record,
kept because it is why the clones and the version guard exist.

**2026-09-23 05:30 -- the engine team reindexed the whole corpus** (CLIENT,
SERVER and the DL self-index) with `v=1.17.0-alpha` / `r=1.6.0-alpha`.
**Our deployed engine WAS `1.16.0-alpha` / resolver `1.5.1-alpha` -- OLDER on two
axes**, and `RefuseIfEngineOlderThanDb` does not cover the resolver axis, so
nothing refused.

The skew gives WRONG ANSWERS, not errors: `call_edges` unchanged at 20,343 on
CLIENT, yet `reverse-calltree --direction callees` on `SendDeltaOperation` fell
from 9 nodes to 4. Callers unaffected.

* **The suite WAS RED -- 9 failures, which had to STAY red.** They are the
  detector for the redeploy. Two families only: callee-direction (7) and the
  field-backed property accessor (2). Everything else still passes.
* **Work on CLONES** in `charts\scratch\db\` (gitignored, verified identical to
  live). They remove the lock risk -- `graph` fails `database is locked`
  against a live DB -- and freeze the asserted counts. They do NOT fix the skew.
* **Reads are safe** -- a full day of them left both DBs still `r=1.6.0-alpha`.
  Only `index` re-resolves, and we never run it.
* Filed urgent:
  `C:\Projects\Delphi-RAG-lint\docs\INBOX-URGENT-resolver-downgrade-not-refused.md`
  -- `DRagLint.CLI.pas:4362` guards extractor + schema but not resolver, and
  `:1880`'s `Prev <> Cur` is direction-blind.

## Resume point

**As of 2026-09-29 (HEAD 65e1419c + this docs commit): the branch is complete pending the review of this documentation pass; then the engine team merges it and publishes.**

Shipped on this branch since the trace-core plan started (2026-09-27):

* `round-trip` -- the trace core (plan Tasks 0-9): a TEXT bundle through `New-DiagramArtifact.ps1`; OPERAT.NAME 76/31/4/2, golden 17/17, guards 12/12, ALSO 9 (owner-accepted); holdout `RT-HOLD` MSCLIST.NUM 103/35/4/2 (owner-accepted by the path's shape).
* The calc-field offer -- a calculated anchor field stops and offers its source fields and the fields that choose its value (`DERIVED`, grammar spec 8.5; gate `RT-CALC`, commits f1cd1eb8..e5cbb459).
* Click-through (DOC-R1, c20fda3f) -- the chart page no longer cancels a `draglint://` click, and round-trip anchors are links (126/126 on OPERAT.NAME) -- plus the HARDENED handler (dc8217ba, 2a4915a1, 65e1419c: one argument only, local drive path and source extension only, Notepad fallback, capped log) and a registration that copies the handler to `%LOCALAPPDATA%\drag-lint` with a stable interpreter (`-DryRun`, worktree refusal).
* `Ask-Report.ps1` (4587182c, d134a4da) -- one command for AI agents (README "For AI agents"), with the user skill `drag-lint-reports` (`C:\Users\alexanderl\.claude\skills\drag-lint-reports\SKILL.md`) that tells an agent when to run it.
* Clones re-taken at `v=1.20.0-alpha / r=1.11.0-alpha` (99c540c8); the deployed engine is 1.20.1-alpha.

Latest full gate: `Test-Emitters.ps1` PASS, 2026-09-28 23:56 - 2026-09-29 00:22, on the tree committed as 2a4915a1 (65e1419c touched no gated file; `Test-DragLintProtocol.ps1` PASS on it). Protected counts unmoved: 76/31/4/2, 17/17, 12/12, ALSO 9, 103/35/4/2, DimAbbr 98/35/4/2.

Owner actions after the merge: re-register the protocol from `C:\Projects\Delphi-RAG-lint\charts\src\Register-DragLintProtocol.ps1` (this machine still runs the versioned 7.6.6.0 pwsh on the worktree's handler) and check one live click into RAD Studio -- never checked end to end.

**Follow-ons, recorded, not designed (one line each):**

1. **The round-trip CHART** drawn from the Form A text -- the next spec -- together with the owner's grammar decisions: drop the quotes around conditions (the parser takes `WHEN` / `UNLESS` ... up to the final `@File:line`); DocInsight-ready text is the default output, with an option for other docs.
2. **A generic TABLE.COLUMN trace** (verb) -- round-trip traces one field INSTANCE; every dataset of a column is another verb.
3. **A drill-down into a routine** at its place in the protocol chain (verb) -- ALSO rows stay anchors; expanding one is another verb.
4. **Table-in-a-constant resolution** -- `colREASON`'s trace stops where the table name is a constant (`CAUSFAIL_TABLE`) rather than a literal.
5. **Multi-assigned locals in calc fields** -- USLLSLName's local `Spec` (set at 5 places) is a named `not mapped` row; its inputs are not followed.
6. **Audit emitter queries near the engine's 10 s `sql` cap** -- `Get-FieldVarWriteRows` ran 9-10 s before its rewrite (1.3 s); other correlated `JOIN ... OR` queries are unaudited.
7. **Plugin-side pipe hardening (engine)** -- `DoOpenInIDE` opens any existing file a local process sends (UNC, `.dproj`); `CreateNamedPipe` has no security attributes and no `PIPE_REJECT_REMOTE_CLIENTS`.
8. **An in-IDE chart viewer (engine)** -- charts open in a browser today.
9. **For the owner, an APP bug, not a charts defect:** in Micronite, `frmAssignGroups` Num edits never reach the database -- the Save (`AssignGroups.ViewModel.pas:507-521`) sends deltas for TOOLASSG / TOOLS / TOOLDEF / TOOLGR12 but none for MSCLIST, and its `FMTFtrs` has no AfterPost (or other update) handler wired, so nothing sends the edit to the server (the `RT-NOWIRE` trace stops at [09] for exactly that reason).

**HISTORY -- NEXT ACTION of 2026-09-27 (done: the trace core shipped 2026-09-28): implement the Interface report trace core,
SUBAGENT-DRIVEN** (owner's choice). Local, gitignored (public repo):
spec `docs\superpowers\specs\2026-09-27-interface-report-trace-core-design.md`,
plan `docs\superpowers\plans\2026-09-27-interface-report-trace-core.md`
(9 tasks, AC-1..AC-16 mapped; drafted by a Fable agent, self-reviewed).
Invoke `superpowers:subagent-driven-development` on the plan.

**OWNER ANSWERED 2026-09-27 (session charts-86 owns the branch from now): all
three as recommended -- (1) Task 0 engine switch FIRST, (2) double-quoted
conditions, (3) re-point hop in the new trace ONLY.** The decisions were:
1. **Task 0 before Task 1: switch engines.** The engine session
   (`delphi-rag-lint-4a`) deployed engine 1.18.0 / resolver 1.9.0 and asked
   every worktree to stop using its own build. Proposed: every emitter's
   default `$Engine` -> `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`;
   re-clone all 9 DBs (keep `*.pre-1.9`); re-run the gate, tracing every moved
   pin; drop the who-writes "bound, not reported" workaround (their D31).
   Also D22: unit-qualified vars/consts bind (+4 CLIENT member_accesses). The
   plan's Global Constraints and measured basis name the OLD engine/clones --
   amend them in Task 0; Task 1 re-measures on the new clones. We acked them.
2. Conditions double-quoted: `UNLESS "SQL = ''"` (Pascal `''` breaks single quotes).
3. The code re-point hop lives only in the new trace (`Get-RePointChain`
   after a `dangling` chain); wiring it into feeds-from/lands-where re-grades
   ~30 pins (426 dangling controls) and is a separate later change.
   **SUPERSEDED 2026-10-05** (owner: "close all the existing gaps"): wired into
   feeds-from and lands-where (Task 2 of the R-items plan), see open item 2 below.
   (Informational: DISPATCH takes the first call after the constant INTO
   ANOTHER UNIT -- plain "first call" picks the unit-local ParseTableFromPayload.)

Programme after this spec (owner, 2026-09-27): holdout field -> chart drawn
from the Form A text -> shared IDE selection (control / its interface field /
a .pas variable) -> IDE command (text to clipboard, open chart) -> review the
other questions -> PORT all of them into the drag-lint engine with docs and
ORM3 examples. Regenerate on demand; no drift tracking; no bookmarks.

**DONE 2026-09-24: the Blueprint4 "Operation Name" example**, engine-made, in
`charts\docs\examples\protocol-trace\` (gitignored output) with
`README-Blueprint4-Operation-Name.md` (column -> wire mapping, IDE path, where
text and graphics come from). The column binds dataset field `Name` on
`FMTOperation` -- not a symbol -- so protocol-trace runs in METHOD mode on the
two wire routines, `SendDeltaOperation` (cmdDelta/rspOK) and `LoadOneTable`
(cmdTableLoad/rspData); crosses-boundary, feeds-from and lands-where were run
beside them.

Two emitter defects found by LOOKING at the output, fixed test-first, gate
green (1072 s):
* method-mode row note was the FIRST ref's constant x site count --
  `CommandIDToStr` read `cmdUnknown x42`. Now names up to 3 distinct constants,
  counts beyond (A-PT3-NOTE-*, A-PT4-*).
* `Add-DisclosureRow` escaped the `&#183;` separator, so 9 call sites in 7
  emitters printed it literally (E-ENTITY sweeps every .dot a run writes).

**OPEN for the owner (from this example):**
1. **protocol-trace does not meet its own golden**
   (`fixtures\golden-operat-name-roundtrip.md`, "the acceptance target for the
   protocol-trace emitter"): 2 of 17 nodes, no guards, no failure edge, one DB
   per chart. "25 of 26 ship" is true of the catalogue, not of the golden.
   (Answered 2026-09-28 by the new question `round-trip`, which matches 17 of 17
   golden nodes and 12 of 12 guards; protocol-trace itself is unchanged.)
2. **feeds-from / lands-where stop at a dangling designer datasource** and do
   not follow the runtime re-point (`Blueprint4.pas:2282`,
   `:= FBlueprint_ViewModel.pdsrOperation`) -- the one hop that would reach
   `FMTOperation` -> `'OPERAT'`. **DONE 2026-10-05 (Task 2):** both follow it
   through `Resolve-RePointTable` (Emit-Common: `Get-RePointPick` -- the ONE copy
   of the stale / several-right-hand-sides rule, lifted out of Trace.Walk --
   then `Get-RePointChain`, then `Get-DataSetTableLiterals`). The Operation Name
   column now reaches `FMTOperation` -> `OPERAT.NAME` (gate `A-FF-REPOINT`,
   `A-LW-REPOINT`). Several sites with different right-hand sides stop with the
   sites named ("cannot tell which feeds the grid"); a stale file on the way
   stops `[stale source]` and no table is drawn.
3. lands-where with no table prints `TDataService__SERVER` / `Imc.` with blank
   names (cosmetic).

**Still open:** (1) owner decides the R24 wave (6 pre-existing unpaged
population queries -- ledger `.superpowers\sdd\PLAN-last-four-verbs\progress.md`).
(2) DONE 2026-09-27 (Task 0, below): the deployed engine is adopted and the
who-writes "bound, not reported" workaround is dropped.

**The earlier batches are all done.** 26 of 27 catalogue questions ship (`round-trip` 2026-09-28); only
`compare` does not, parked by the owner.

**THE SUITE WAS GREEN (2026-09-28 18:59-19:26, the re-clone; the latest green run is in the Resume point) on re-taken clones at `v=1.20.0-alpha / r=1.11.0-alpha`**
(engine 1.20.0-alpha; all 9 copied 18:17-18:18, DL first; the r=1.9 set kept as `*.sqlite.pre-1.10`; the CLIENT
live DB had a 5-commit WAL rewriting only `schema_meta` with identical values, so its main file was copied and
verified equal to the live DB by stamps and table counts -- ruling RC-R3). Moved pins, each traced:
* extractor 1.20, sql_column on its own identifier line (+1): IPCHART.ACTION 2242 -> 2243, FOLDERCOUNT.TABLE
  3847 -> 3848, CAUSFAIL.REASON 1410 -> 1411, OPERAT.NAME 2808 -> 2809 (MScript2 1640 -> 1641, IPCHART.ACTION's
  older 1902 -> 1903). `INBOX-sql-column-start-line-one-early.md` is fixed. A-LW-N31-QUOTED's old 3847 still
  passed only through the table node's CREATE TABLE line; it now pins 3848.
* resolver 1.11 RB-1 (unit-var receiver calls bind): GetTable x4 and PushTableChanged now bound; EnsureLoaded /
  GetTable / PushTableChanged lose `[by name]` and `ask receiver-typed-calls` in every round-trip.
* RB-1 also moved the broadcast into the transport skip (a BOUND call into `uBroadcast%`): 76/31 -> 75/30 and
  golden 17 -> 16 until RC-R6 kept a transport callee whose body calls WriteFile (and kin) as a step, not
  descended. OPERAT.NAME 76/31/4/2, holdout 103/35/4/2, DimAbbr 98/35/4/2, golden 17/17, ALSO 9: unchanged.
  The check that the rule does not over-trigger (RC-R5) was index-wide for the WriteFile callers (all pipe or
  broadcast code) but only trace-scoped for the callees the walk skips or prunes.
* AS OF stamps. `Self.X` writes (CLIENT 32,915) moved no pin; CLIENT / SERVER / SQL sources identical to the old
  clones (per-file sha).

**THE SUITE WAS GREEN (2026-09-28 14:33-15:00, after the round-trip final fix wave) on the shared deployed engine
(`--version`: 1.19.1-alpha) and the same r=1.9 clones.** OPERAT.NAME 76/31/4/2 and the holdout 103/35/4/2 did not move;
the wave's own pins are listed in its commits.

**THE SUITE WAS GREEN (2026-09-28 00:13) on the SHARED engine 1.18.0-alpha /
resolver 1.9.0-alpha** (Task 0 of the trace-core plan). Every emitter now runs
`C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`, not this
worktree's 1.16 build. All 9 clones re-taken 2026-09-27 23:15 at
`v=1.19.0-alpha / r=1.9.0-alpha` (old copies kept as `*.sqlite.pre-1.9`); the
DL clone was re-taken again at 23:50 because the 21:45 DL index had NO call
edges for the 20 units edited since their parse (7,429 vs 13,095 edges; kept as
`DL-drag-lint.sqlite.withheld-2145`). Moved pins, each traced:
* who-writes (engine D31: `find-callers --resolved` reports a bare write BOUND
  to the member, at the same lines the chart used to list): FConnected writes
  0 -> 4, fLOTSIZE 0 -> 5, FNoRecursion 0 -> 48. The "bound, not reported"
  disclosure and `BoundUnreported` are gone; the site SQL anchors bound bare
  refs; counts read "N resolved write(s) reported by find-callers" (was
  "member-access"); the bundle-header label test moved to who-reads
  FNoRecursion (9 unbound reads still need it).
* `A-AR1-EXTEDGES` 30716 -> 6880: engine deps-report fix c4034b21 (their D5);
  both engines on the SAME clone give 30716 / 6880; 6880 = distinct unresolved
  (file, unit) `unit_uses` pairs.
* D22 (+4 CLIENT, +1 DataCopy member_accesses) moved no pin.
* find-callers JSON `line` is now the call SITE (`caller_line` = declaration):
  no emitter read the resolved `line`; the Emit-Common comment that said
  otherwise, and protocol-trace's "cannot see enum values" note, are corrected.

**THE SUITE WAS GREEN (2026-09-24 03:48) on extractor 1.19.0 / resolver 1.8.0** --
all 9 clones re-taken 02:53 (previous copies kept as `*.pre-1.19`), every moved pin
traced against them (commit 8e17bedf: D1 parenless calls, D12, D13, D18, D19, and
two SOURCE changes in the DL self-index). Before that:

**THE SUITE WAS GREEN (2026-09-23 10:31) on extractor 1.18.0 / resolver 1.6.0.**
All 8 project clones were re-taken after the engine's full re-parse (pre-1.18
copies kept beside them as `*.pre-1.18`; the 05:30 CLIENT as
`*.pre-reindex-0530`). Plus `SQL-drag-lint-sql.sqlite`, cloned at 10:01, final.

Every re-baseline on the way was traced to a mechanism before it was made:

* withheld-file reindex (09:42): the 9 callee/accessor failures cleared;
  `A-PT2` 1043/727 -> 1047/728 (4 recovered CommandID reads).
* extractor 1.18 define-profile fix (EUREKALOG now live): `A-EW1` +2 handlers
  (`EurekaLogEvents1`), `A-FX3` `s` -> `s,?` (`HandleException` body is all
  EurekaLog, calls `ExceptionManager.Handle`), `A-AR1` +1 internal / +10 external
  units (the .dpr's EurekaLog uses block). `EXTEDGES` +14 vs +12 raw uses rows:
  deps-report attribution, asked in the engine INBOX.

The last four verbs (`charts\PLAN-last-four-verbs.md`) shipped the same day:
25 of 26. Only `compare` remains, parked by the owner.

### Batch 3 findings (2026-09-23)

1. **The callee-direction mystery is SOLVED -- and our first answer was WRONG.**
   We concluded "the 1.6.0 resolver binds strictly less, and what it lost is
   interface dispatch". The engine team corrected it the same day and we then
   verified their mechanism independently on our own clone:

   > a whole-DB resolve calls `ClearCallEdges`, which clears UNCONDITIONALLY --
   > including rows of files the stale prescan then WITHHOLDS -- while
   > re-derivation is narrowed to skip stale files. A withheld file's
   > `call_edges` and `member_accesses` are cleared and never rebuilt.

   **On CLIENT exactly ONE file was withheld**, and all 9 red assertions trace
   to it. Verified by us, not taken on trust:

   | file | `kind='call'` refs | `call_edges` |
   |---|---|---|
   | `uPipeClientConnection.pas` | **161** | **0** |
   | `Blueprint4.ViewModel.pas` | 1,847 | 656 |
   | `uMain.pas` | 255 | 41 |

   `ExecuteCommand` lives in it with 0 outgoing edges, so 9 nodes -> 4 is the
   SUBTREE below it, not the root -- `SendDeltaOperation`'s two direct edges are
   intact and `certain`, exactly as our raw SQL found. `Connected` is in the same
   file, which is why its 602 rows lost `accessor_symbol_id`.

   **DO NOT re-baseline the 9 assertions.** They are a recoverable data defect,
   not a version skew, and they do NOT clear when the engine is redeployed --
   they need one incremental reindex of CLIENT with a 1.6.0-alpha engine (which
   we must not run: ours is 1.5.1). After that reindex, RE-CLONE and the suite
   should go green.

   The unsafe step on our side was concluding a CAUSE from two correlated
   symptoms without a mechanism. `Get-EdgelessFiles` in `Emit-Common.ps1` now
   DETECTS the signature instead of any chart asserting a story about it -- and
   it deliberately does not guess the cause, because on SERVER the same
   signature is produced innocently by `uContainerConfig.pas`, whose 137 call
   refs are all external Spring4D registrations.
2. **Which is why `change-impact` and `tested-by` shipped anyway.** Both walk
   CALLERS -- from a symbol up to its dependents, and from code under test up to
   the tests -- and the caller direction is intact (9 callers, matching the
   pre-reindex assertion).
3. **`shown-where`'s premise was wrong in KIND, not degree.** `ui_affinity` is a
   thread-affinity hint carried only by routines; **0 of 13,131 fields and
   properties have one**, and 0 of its 230 tokens match any control. Rebuilt on
   DFM data bindings (903 rows / 459 columns / 38 forms), which resolve to a
   `component` symbol every time.
4. **`tested-by` is a SINGLE-DB pass** -- the test closure contains the code
   under test (MicroniteTests: 5,152 symbols, 724 of them from `MSCTYPES.PAS`).
   One `[Test]` marks the NEAREST FOLLOWING declaration; a "+/-2 lines" window
   matched three methods per attribute on these fixtures.
5. **The `sql` 200-row cap bit again, and silently.** An unpaged
   `SELECT DISTINCT path FROM files` returned the first 200 of 625 -- all under
   `\CLIENT\` -- so the common root came back as `...\ORM3\CLIENT` and every
   protocol-trace row collapsed into ONE zone. Page every population query.
6. **`@(Invoke-IndexQuery ...)` bit again too**, exactly as the contract warns:
   the nesting makes `.Count` read 1 on an empty result, which made every method
   report "is the boundary".

### Deviations and findings from the second batch (2026-09-23)

Seven, all measured, each one a premise that would have shipped a wrong chart:

1. **`cycles` returns strongly-connected COMPONENTS, not rings.** DL's "size 4
   cycle" is two loops sharing `regions` and has no Hamiltonian cycle. A
   ring-walk refused to draw its arrows; the emitter now draws every measured
   edge and assumes no traversal order.
2. **`units[]` is not in cycle order** (P3 extension). Following the array would
   draw `blueprint4 -> controlplan2`, an edge that does not exist.
3. **`mutates_params` is not the p-token name column.** It lists `var`/`out`
   params; EVERY multi-p row on CLIENT has it empty. Names now come from parsing
   `symbols.signature` by ordinal -- validated against the engine's own witness
   text on **351 of 351 rows** (256 CLIENT + 95 SERVER), zero disagreements. The
   plan's "roughly 12% cannot be named" no longer holds: 0 could not be named.
4. **`cycles --plan` costs 46.5s against 0.8s for `--format json`** -- 58x, for
   one label per cycle. It is now behind `-Playbook`, off by default.
5. **`wiring` cannot distinguish a class from an unregistered interface** -- it
   returns the same empty document for both. The kind check moved into the
   emitter.
6. **No namespace or folder layering exists for `architecture`**: 512 of 563
   units have no dot. Zones are SOURCE DIRECTORIES (100% coverage). This
   surfaced **3 back-edges** -- 13 edges against a 1,170-edge flow.
7. **Two plan counts were off**: form classes owning lifecycle events are **44**,
   not 43; and **2** form-rooted classes wire nothing (1 TForm + 1 TDataModule),
   not 1.

`Get-CloneDb` now guards every emitter, and `Test-Emitters.ps1` defaults to the
clones instead of the live corpus.

**Still owed, and not ours to do yet:** the `with`-block attribution
measurement from Task 0 remains ON HOLD pending the engine team's Task 7,
which measures a DIFFERENT population (enum-value reads inside `with`, not
member accesses generally). Reuse their method when the note lands, then
decide whether our half needs its own pass. Until then `who-writes` /
`who-reads` may UNDERCOUNT on legacy code that uses `with` heavily, and that
is not yet disclosed on the chart.

`charts\src\Test-Emitters.ps1` must stay green throughout.

## Gotchas that will bite a cold start

* `$E` and `$e` are THE SAME VARIABLE in PowerShell.
* `Invoke-IndexQuery` returns `, $array` -- assign DIRECTLY, never `@(...)`.
* Dot-sourcing a scriptblock inside a function runs it in THAT function's
  scope; a test harness needs `$script:`.
* PowerShell has no heredoc; `@'...'@`, closer at column 0.
* `--format json` splices a staleness note INTO the JSON.
* `sql` caps at 200 rows and truncation is SILENT. The VERBS are not capped.
* `PRAGMA table_info` is refused by the authorizer -- use `schema --format json`.
* A column existing in schema 23 does not mean it holds rows.
* **`member_accesses.accessor_symbol_id` looks broken and is NOT** -- it names
  the property backing, by owner ruling. Do not file it. Twice now a review has
  called it a defect.
* **`$pal` and `$PAL` are the same variable**, like `$E` and `$e`. PowerShell
  names are case-insensitive; a loop-local `$pal` wiped a palette and dot
  warned `'' is not a known color`.
* **`$x = if (...) { @() }` assigns `$null`** -- an empty array enumerates to
  nothing -- and `@($null)` is a ONE-element array holding `$null`.
* **Ask the SCHEMA before writing SQL**, not just the verb. The plan's
  containment subquery for the enclosing routine recomputed
  `refs.enclosing_symbol_id`, which agrees on 9,311/9,311 CLIENT and
  14,836/14,836 SERVER rows.
* **Forward declarations are not alternatives.** Collapse on
  (`qualified_name`, `generic_params`) -- the pair, because a generic and a
  non-generic type legitimately share a name (`IDataService`).
