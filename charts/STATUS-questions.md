<!-- dl:backlog status=open last-measured=2026-09-23 -->
# STATUS: the 26 diagram questions

The live scoreboard for `charts\question-catalogue.md`. **26 catalogue rows**
(`protocol-trace` appears twice -- field and method are different questions).

Updated 2026-09-23. Branch `feat/archify-ir`, 24 commits, NOTHING PUSHED.

```
SHIPPED                     10   emitters exist, tested, clickable
PLANNED (ready to build)     0   the five-question batch is DONE
UNPLANNED, unblocked         9   implementable today, nobody has planned them
BLOCKED on data              3   need a live Firebird via fb-snapshot
BLOCKED on the engine        4   waiting on enum-value binding / raise-handle
                            --
                            26
```

**16 of 26 are not resolved**, down from 21. Nothing is planned-but-unbuilt any
more: the next person picks from the nine unplanned ones and measures first.

**Selection-kind coverage is now method / unit / form-class / field / property /
type** -- the batch's actual purpose. It was three kinds this morning.

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

**Ten questions, EIGHT emitters** -- `what-it-calls` is a `-Direction` switch and
`who-writes`/`who-reads` are one `-Mode` switch. Say it that way: counting
emitters as questions understates the result, counting questions as emitters
overstates the work.

Gate: `charts\src\Test-Emitters.ps1` (exit 0 = green). Proven to fail correctly
on every batch -- see each commit for the mutation it was checked against.

## UNPLANNED but IMPLEMENTABLE TODAY (9)

Nothing blocks these; no one has measured or planned them. Effort is a first
estimate, NOT a measured one -- treat each as needing its own measurement pass
before it is trusted, exactly as the shipped five did.

| question | selects | effort | why that effort |
|---|---|---|---|
| `lifecycle` | form / type | **S** | reuses event-wiring's `dfm_event` query wholesale (762 rows); adds create/show/destroy ordering |
| `cycles` | unit / project | **S-M** | `cycles --plan` verb already emits a followable playbook; unit-graph shape like `deps` |
| `change-impact` | method / type | **M** | `impact` verb exists (text/json); fan-out tree, close to who-calls |
| `effects` | method | **M** | facts well populated (`effect_free` 10,150 / `effect_summary` 7,254) but the encoding (`g,s,?`) must be decoded first -- the encoder is IN-REPO, so read it; do NOT wait on the engine |
| `wiring` | interface / type | **M** | `wiring` verb + `di_bindings`, but CLIENT 4 vs SERVER 535 registrations -- the client gap must be disclosed, not rendered as "no DI" |
| `shown-where` | field / column | **L** | `ui_affinity` only 230 CLIENT / 37 SERVER rows; partial by nature, needs a DFM join and honest coverage reporting |
| `tested-by` | any symbol | **L** | `covered_by` is 0/0 BY DESIGN -- must be COMPUTED from a test project's call edges, so it needs a second index and a reachability pass |
| `architecture` | project | **XL** | project-scale trust-zoned rectangles; `graph` + `deps-report` + `di_bindings`, and a layout strategy that does not exist yet |
| `compare` | two index runs | **XL** | needs the IR and a diff model; no emitter precedent, and two indexes must be opened at once |

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

Interim: keep the `[inferred]` dashed-edge convention. Do not attempt these.

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

## Resume point

The five-question batch is DONE (commits `94c6f634`, `d99e283a`, `769d47c4`).
`charts\PLAN-next-five-questions.md` records what was built and where reality
differed from the plan.

**Next:** pick from the nine unplanned-but-unblocked questions above and
MEASURE FIRST, exactly as the shipped ten did. `lifecycle` (S) and `cycles`
(S-M) are the cheapest; `effects` (M) is deferred but NOT blocked -- the
`effect_summary` encoder is in this repo and can simply be read.

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
