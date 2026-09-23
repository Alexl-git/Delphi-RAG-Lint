<!-- dl:backlog status=open last-measured=2026-09-23 -->
# STATUS: the 26 diagram questions

The live scoreboard for `charts\question-catalogue.md`. **26 catalogue rows**
(`protocol-trace` appears twice -- field and method are different questions).

Updated 2026-09-23. Branch `feat/archify-ir`, 24 commits, NOTHING PUSHED.

```
SHIPPED                     21   emitters exist, tested, clickable
PLANNED (ready to build)     0
UNPLANNED, unblocked         0   there is nothing left that the index can answer
BLOCKED on data              3   need a live Firebird via fb-snapshot (0 rows today)
BLOCKED on the engine        1   exception-paths -- no raise/handle fact, MEASURED
PARKED by owner              1   compare
                            --
                            26
```

**Every question this index can answer now ships.** The five remaining are
blocked on facts that do not exist yet, not on work nobody has done -- and each
one's blocker was measured, not assumed.

**Selection kinds: method / unit / form-class / field / property / type /
interface / project / command constant / wire field / db column / any symbol.**

---

## SHIPPED (10)

| question | selects | emitter | measured |
|---|---|---|---|
| `butterfly` | method | `Emit-Butterfly.ps1` | 9 callers / 8 callees, 18 anchors |
| `deps` | unit | `Emit-Deps.ps1` | 3 used-by / 18 uses |
| `who-calls` | method | `Emit-WhoCalls.ps1` | 10 sites + 1 cycle @d3 |
| `what-it-calls` | method | `Emit-WhoCalls.ps1 -Direction callees` | 2/8/16 rows @d1/d2/d3, 5 cycles |
| `who-writes` | field / property | `Emit-MemberAccess.ps1 -Mode write` | R: 7 writes over 3 routines |
| `who-reads` | field / property | `Emit-MemberAccess.ps1 -Mode read` | Connected: 602 reads / 598 routines |
| `hierarchy` | type | `Emit-Hierarchy.ps1` | 145 descendants, 2 ancestors (1 RTL) |
| `class-surface` | type | `Emit-ClassSurface.ps1` | 392 members over 2 visibility clusters |
| `event-wiring` | form class | `Emit-EventWiring.ps1` | 41 events / 41 handlers / 40 controls |
| `touches-tables` | method | `Emit-TouchesTables.ps1` | 5 read / 5 written / 2 both |
| `lifecycle` | form class | `Emit-Lifecycle.ps1` | uMain: 2 wired / 1 implemented-not-wired / 4 absent |
| `cycles` | unit / project | `Emit-Cycles.ps1` | CLIENT 2 groups / 5 edges; DL's SCC 5 edges; DataCopy 0 |
| `wiring` | interface | `Emit-Wiring.ps1` | SERVER 2 regs / 4 sites of 535; CLIENT 1 of 4 |
| `effects` | method | `Emit-Effects.ps1` | pure / not-analysed / `g,p0,p3,?` over 6 params |
| `architecture` | project | `Emit-Architecture.ps1` | 563 units / 3 zones / 2,858 edges / 3 back-edges |

| `protocol-trace` | command / wire field | `Emit-ProtocolTrace.ps1` | cmdDelta 38 refs / 2 zones; CommandID 1,043 / 727 routines |
| `protocol-trace` | method | `Emit-ProtocolTrace.ps1` | CommandIDToStr speaks all 42 TCommandID members |
| `crosses-boundary` | method | `Emit-CrossesBoundary.ps1` | crosses (2 cmds / 1 transport / 18 far) &#183; is-the-boundary &#183; no-evidence |
| `shown-where` | db column | `Emit-ShownWhere.ps1` | FTRNAMESTR 4 bindings / 2 forms, of 903 over 459 columns |
| `change-impact` | method / type | `Emit-ChangeImpact.ps1` | 9 routines / 1 unit; a TYPE reaches 591 over 174 units (capped) |
| `tested-by` | any symbol | `Emit-TestedBy.ps1` | 11 / 8 / 13 covering tests, computed from 71 test methods |

**Twenty-one questions, EIGHTEEN emitters** -- `what-it-calls` is a `-Direction`
switch, `who-writes`/`who-reads` are one `-Mode` switch, and both
`protocol-trace` rows are one emitter dispatching on the selection's kind. Say
it that way: counting emitters as questions understates the result, counting
questions as emitters overstates the work.

Gate: `charts\src\Test-Emitters.ps1` (exit 0 = green). Proven to fail correctly
on every batch -- see each commit for the mutation it was checked against.

## NOT SHIPPED (5), each with a MEASURED blocker

Nothing here is waiting on effort. Each row names the fact that does not exist.

| question | selects | blocker, measured |
|---|---|---|
| `exception-paths` | method | **No raise/handle fact.** `refs.kind` has no `raise`/`except` value (only read / type_use / call / member-access / write / event-binding / attribute / di-*), and `symbol_facts` has no exception column. 17 `E*` classes ARE referenced, but a `type_use` of `EMicroniteError` is produced identically by `raise E.Create`, `on E: T do` and a bare declaration -- so a chart would draw handlers as throwers. Asked for two ref kinds in `INBOX-no-raise-handle-fact-blocks-exception-paths.md` |
| `lands-where` | field | `orm_links` **0 rows** |
| `feeds-from` | control | `orm_links`, `fb_datasets` **0 rows** |
| `consumers` | table / column | `fb_columns`, `fb_relations` **0 rows** |
| `compare` | two index runs | parked by owner; no `ir` or `compare` verb exists in the deployed engine |

The three `fb_*` rows all need `drag-lint fb-snapshot` against a **live
Firebird**. That is an INGEST task, not a chart task, and it is on this
session's STOP list. Their effort is unknowable until the ingest runs.

## BLOCKED ON DATA -- not near-term (3)

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

## BLOCKED ON THE ENGINE (4)

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

## >>> THE ENGINE IS AHEAD OF OUR BINARY. READ BEFORE MEASURING ANYTHING <<<

**2026-09-23 05:30 -- the engine team reindexed the whole corpus** (CLIENT,
SERVER and the DL self-index) with `v=1.17.0-alpha` / `r=1.6.0-alpha`.
**Our deployed engine is `1.16.0-alpha` / resolver `1.5.1-alpha` -- OLDER on two
axes**, and `RefuseIfEngineOlderThanDb` does not cover the resolver axis, so
nothing refused.

The skew gives WRONG ANSWERS, not errors: `call_edges` unchanged at 20,343 on
CLIENT, yet `reverse-calltree --direction callees` on `SendDeltaOperation` fell
from 9 nodes to 4. Callers unaffected.

* **The suite is RED -- 9 failures, and they must STAY red.** They are the
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

**All three batches are DONE and there is no next batch.** Every catalogue
question the index can answer now ships; the five that do not are blocked on
facts that do not exist, each measured and each filed.

**Next, when the engine lands:** re-run the suite and re-baseline the 7
callee-direction assertions WITH a note -- they are now known to be a DATA
change, not a misread (see below). Expect the 2 property-accessor ones to
persist. Then re-clone and re-measure before trusting anything here.

### Batch 3 findings (2026-09-23)

1. **The callee-direction mystery is SOLVED, and it was not our engine.** Raw
   SQL over `call_edges` returns the SAME 2 direct callees for
   `SendDeltaOperation` that the verb does, against a frozen assertion of 8. So
   the engine reads the data correctly and the 1.6.0 resolver produced FEWER
   edges. The lost population looks like interface dispatch: that method's body
   has 32 `kind='call'` refs and only 2 with a `call_edges` row, the missing ones
   being `Send`, `SaveToStream`, `CommitUpdates` and friends. Filed as
   `INBOX-resolver-1.6.0-gained-enums-lost-callee-edges.md`.
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
