<!-- dl:backlog status=open last-measured=2026-09-23 -->
# PLAN: the next five diagram questions (lifecycle, cycles, wiring, effects, architecture)

For a COLD session. Work ONLY under `charts\`. Ten questions already ship and
are the reference implementations; `charts\src\Test-Emitters.ps1` is the gate.

**Every number below was MEASURED on 2026-09-23 against the CLONES named below.
Do not re-derive them -- compare against them.** A number that does not match is
a FINDING: investigate before "fixing" the number.

```
$E     = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe'
$DOT   = 'C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe'
$SRC   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\src'
$CLI   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\scratch\db\CLIENT-Micronite2027.sqlite'
$SRV   = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\scratch\db\SERVER-MicroniteMW1Service.sqlite'
$DL    = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\scratch\db\DL-drag-lint.sqlite'
```

## >>> READ THIS FIRST: why we are on CLONES <<<

On 2026-09-23 at 05:30 the engine team reindexed the whole corpus with
`v=1.17.0-alpha` / `r=1.6.0-alpha`. **The deployed engine in this worktree is
`1.16.0-alpha` with resolver `1.5.1-alpha` -- OLDER than the index on two axes.**

That skew produces WRONG ANSWERS, not errors. Measured: `call_edges` is
unchanged at 20,343 on CLIENT, yet `reverse-calltree --direction callees` on
`SendDeltaOperation` fell from 9 nodes to 4 (callees 8 -> 3). Callers are
unaffected (still 9 / 10). A tool returning a SMALLER CONFIDENT answer from
identical data is the failure mode this project exists to prevent.

So: the three DBs are cloned into `charts\scratch\db\` (gitignored), verified to
open and to return numbers identical to live. Clones remove the LOCK risk
(`graph` already fails `database is locked` against a live DB) and freeze the
counts the suite asserts. **They do NOT fix the skew** -- a clone carries
`r=1.6.0-alpha` with it, so the old engine misreads the copy just as badly.

**Nothing in THESE five depends on the skewed path.** That is why these five and
not the other two -- see "Held" at the end.

**Do NOT run `drag-lint index` / `fb-snapshot` / `autodoc` against ANY database,
clone or live.** Reads are proven safe (a full day of them left both DBs still
reading `r=1.6.0-alpha`); only `index` re-resolves. The engine has no guard
against the downgrade yet -- filed as
`C:\Projects\Delphi-RAG-lint\docs\INBOX-URGENT-resolver-downgrade-not-refused.md`.

---

## THE PREMISES -- every one measured, none assumed

The last batch shipped with SIX wrong premises in a fully-measured plan. These
are listed separately so they can be attacked directly before any code is
written.

| # | premise | evidence | risk if wrong |
|---|---|---|---|
| P1 | `dfm_event` records form lifecycle events, not just control events | `frmWaitingToComplete.OnCreate` / `.OnShow` / `.OnClose`, `frmZ19OSelect.OnDestroy` all present | `lifecycle` has no data at all |
| P2 | `dfm_event` is `Owner.Event` for BOTH forms and controls, so event-wiring's query is reusable unchanged | `btnExit.OnClick` 37, `frmVarNames.OnCreate` 1 -- same shape | lifecycle needs its own extraction |
| P3 | `cycles --format json` returns `[{units[],size,interface_cycle}]` | CLIENT: 2 cycles, sizes 3 and 2, both `interface_cycle:false` | -- |
| P4 | `cycles` unit names are **LOWERCASED** (`blueprint4.viewmodel`) | measured verbatim from the JSON | rows silently fail to anchor |
| P5 | `wiring --qname <I>` returns `implementations[{impl,lifetime,file,line}]` + `resolved_at[{file,line}]`, all anchorable | `IABZLoggingSys` on SERVER: 2 impls, resolved_at 3+ sites | -- |
| P6 | `symbol_facts.wiring` is UNUSABLE -- 0 non-NULL on both indexes. Build on `di_bindings` | CLIENT 0, SERVER 0 | a chart with no rows |
| P7 | `di_bindings` is CLIENT **4** vs SERVER **535** -- the client gap must be DISCLOSED, never drawn as "no DI" | measured both | a confidently wrong "this app has no DI" |
| P8 | **CORRECTED.** `g`=global, `s`=self, `?`=unknown, `h`= *frees or resizes* heap (Dispose/FreeMem), `p<k>` = parameter **k, ZERO-BASED** | `Purity.pas:30-31` says "the 0-based ordinals"; `AddParam` `:65-67`; builtins `Inc`->`p0`, `Insert`->`p1` `:279-291`; `h` at `:292-293` | **off-by-one on every param label**, and `h` mislabelled as "uses heap" |
| P9 | ~~NULL means "not analysed"~~ **WRONG -- see below** | crosstab, verified | would mislabel **2,892 pure methods** |
| P10 | **OVERSTATED.** `deps-report` classifies **EXTERNALS ONLY**; it says nothing about the internal structure of the 563 project units. `project_unit_count` = "project units that use that group" | `deps-report/1` = `{summary{...groups[]}, externals[283]{unit,group,resolved,used_by(capped 20),shortest_path,sections}}`; internal edges live in `unit_uses.target_file_id` (2,858 rows) | `architecture` ships as zones-of-third-party with no internal layering -- i.e. not an architecture chart |
| P11 | **REASON CORRECTED.** `graph` does NOT write -- `DoGraph` (`CLI.pas:8031-8133`) opens a bare RW `TFDConnection` and runs ONE SELECT; "locked" is RW-open vs a WAL writer. **But do not use it anyway**: its edges are `LOWER(s.name)=LOWER(r.name_text)` NAME MATCHES (`:8088`), not uses-edges | read at source | a chart built on name collisions, presented as dependencies |
| P12 | **OVERSTATED.** Raw `sql` is not *misread*, but the tables it exposes ARE resolver-written -- `member_accesses`, `refs.symbol_id`, `call_edges`, `symbol_facts`, `type_ancestors` | `accessor_symbol_id` is NULL for all 602 `Connected` rows ON THE CLONE, so that is STORED data, not a misread | row counts are safe; anything resolver-derived may have genuinely CHANGED, not merely been misread |
| P7b | **UNVERIFIED.** CLIENT's 4 registrations are real (`uClientContainer.pas:41-55`), but "because the client resolves over a pipe" is an inference we have NOT established from the index | -- | disclosing a *cause* we cannot evidence |

### P9 IN FULL -- the premise that would have mislabelled 2,892 methods

A NULL `effect_summary` does **not** mean "not analysed". `TEffectSummary.Encode`
returns `''` for an effect-free routine (`Purity.pas:317-330`) and the writer
stores `''` as NULL (`DRagLint.Storage.SQLite.pas:8023`, `ParamByName('es').Clear`).
So NULL is overwhelmingly the PURE case. Measured on the CLIENT clone:

| `effect_summary` | `effect_free` | rows | means |
|---|---|---|---|
| has tokens | 0 | 7,258 | has effects, listed |
| **NULL** | **1** | **2,892** | **effect-FREE -- pure** |
| NULL | NULL | 855 | genuinely not analysed |

SERVER is the same shape (2,818 / 819).

**`effect_free` is the headline, not the summary's NULL-ness.** Reading absence
as ignorance would have told the reader that 2,892 provably pure methods were
unanalysed -- the exact inversion of the fact.

### Premises the plan RELIED ON without listing

| # | finding | consequence |
|---|---|---|
| U1 | `uMain.TfrmMAIN` has a `FormDestroy` **implemented at `uMain.pas:138,422` but NOT wired** -- `uMain.dfm` carries only OnCreate/OnShow (`:52-53`). 4 such unwired `Form*` handlers on CLIENT | `lifecycle` must distinguish **not wired** from **not implemented**. Printing "(not implemented)" beside a live body is a false statement about the code |
| U2 | N14's "refuse like event-wiring's N4" conflates *not a form* with *a form having zero wired events*; 1 TForm/TdxRibbonForm class has zero `dfm_event` rows | the negative test would pass for the wrong reason; needs a heritage / `type_ancestors` form check |
| U3 | the proposed lifecycle order puts `OnDeactivate` before `OnCloseQuery`, but OnDeactivate is a focus-loss event that fires after OnClose on hide -- it is not a pre-close stage | a chart asserting a sequence Delphi does not have |
| U4 | `dfm_event` records ONE owner per handler (`Emit-EventWiring.ps1:20-22`) | a handler shared by two controls is represented once |

### Measured table sizes on the clones

| | CLIENT | SERVER | DL |
|---|---|---|---|
| symbols | 57,100 | 37,906 | 22,548 |
| files | 625 | 470 | 128 |
| unit_uses | 9,742 | 7,983 | -- |
| di_bindings | 4 | 535 | -- |
| type_ancestors | 1,010 | 937 | -- |
| `symbol_facts.ui_affinity` | 230 | 37 | -- |
| `symbol_facts.wiring` | 0 | 0 | -- |
| `symbol_facts.covered_by` | 0 | 0 | -- |

---

## Task 0 -- shared additions (do first)

* **`Get-CloneDb`** -- resolves a clone path and REFUSES a live corpus path, so
  no emitter can be pointed at the originals by habit. One place.
* **Re-confirm `Get-TopRanked` / `Add-DisclosureRow` / `New-NoteRow`** cover the
  new shapes; `architecture` discloses at GROUP level, not row level.
* **Encoding after EVERY edit** -- strict 7-bit ASCII, CRLF, no BOM (the loop in
  `PLAN-next-five-questions.md`; Write/Edit emit LF).

**One measurement to take BEFORE writing any emitter:** the total `dfm_event`
row count on the clone, and how many are lifecycle events specifically. The
STATUS doc claims 762 dfm_event rows; that was measured pre-reindex and event
counts are the one family the reindex could plausibly have moved.

## Task 1 -- `lifecycle` (S)

Selects a FORM or TYPE. Reuses event-wiring's `dfm_event` query (P2), filtered
to the lifecycle event names rather than to an owner:
`OnCreate, OnShow, OnActivate, OnDeactivate, OnCloseQuery, OnClose, OnDestroy`.

The chart's value is ORDER, so rows render in Delphi's real lifecycle sequence,
NOT alphabetically and NOT in DFM order.

**U3: `OnDeactivate` is NOT a pre-close stage** -- it is a focus-loss event and
fires after OnClose on hide. Either drop it from the sequence or render it
outside the create->destroy spine; do not assert an order Delphi does not have.

**U1 is the design point of this chart.** A stage has THREE states, not two:

| state | row |
|---|---|
| wired in the DFM | anchored to the handler's impl line |
| **implemented but NOT wired** | anchored to the body, marked "not wired" |
| absent | un-anchored, "(not implemented)" |

Measured: `uMain.TfrmMAIN` implements `FormDestroy` at `uMain.pas:138,422` and
the DFM wires only OnCreate/OnShow (`uMain.dfm:52-53`). Collapsing the middle
state into "(not implemented)" would be a false statement about code that
plainly exists -- and there are 4 such handlers on CLIENT.

**VERIFY** `-Form uMain.TfrmMAIN` (must show FormDestroy as implemented-not-wired),
`frmVarNames` (OnCreate + OnDestroy + OnCloseQuery) and DataCopy's
`uMainZeissCopy.TfrmZeissCopy` (a full set: OnCreate/OnShow/OnCloseQuery/OnDestroy).
Corpus counts on CLIENT: OnCreate 31, OnShow 11, OnActivate 18, OnCloseQuery 31,
OnClose 33, OnDestroy 18; owners are TForm 43 / TdxRibbonForm 8 / TDataModule 1.

## Task 2 -- `cycles` (S-M)

Selects a UNIT or the PROJECT. `cycles --format json` for the facts (P3),
`cycles --plan` for the playbook text.

**P4 is the trap:** unit names come back LOWERCASED, so anchoring needs a
case-insensitive match to `files`/`symbols`. Verify every row anchors; a silently
un-anchored cycle chart looks fine and clicks nowhere.

Render each cycle as its own cluster, arrows following the uses-direction, with
`interface_cycle` distinguishing severity -- `false` means implementation-only,
which Delphi permits; do NOT render both alike.

**VERIFY** on `$CLI`: exactly **2** cycles -- `blueprint4 <-> controlplan2 <->
blueprint4.viewmodel` (size 3) and `uiconnect <-> gagefrm2` (size 2), both
`interface_cycle: false`.

## Task 3 -- `wiring` (M)

Selects an INTERFACE. `wiring --qname <I> --format json` (P5).

**Build on `di_bindings`, NEVER `symbol_facts.wiring` (P6).**

LEFT = registrations (`implementations`, labelled with `lifetime`), FOCUS = the
interface, RIGHT = resolution sites (`resolved_at`). A lifetime of
`singleton-per-thread` vs `singleton` is a real architectural fact -- put it on
the row, not in a tooltip.

**P7 must be disclosed on the chart**: a CLIENT index holds only 4
registrations (all in `uClientContainer.pas:41-55`) against SERVER's 535. A bare
"1 registration" there reads as "barely wired" when the honest statement is
"this index has 4 registrations in total -- ask the SERVER index". Follow
`touches-tables`' precedent: an index-wide pre-check FIRST, then the note.

**State the NUMBER, not the CAUSE (P7b).** "The client resolves over a pipe" is
a plausible inference we have NOT evidenced from the index, and this project's
own rule is that a chart asserts what it measured. Say how many registrations
this index has and which index has more; do not explain why.

**VERIFY** `-Interface IABZLoggingSys -DbPath $SRV` -> 2 implementations, both
`TABZLoggingSys`, `singleton`, at `uContainerConfig.pas:425` and
`uDIContainerConfig.pas:429`; resolved_at includes
`uMicronite_MW_Service1.pas:194` and `:227`. `wiring --coverage` on `$SRV`
returns `unresolved: []`.

## Task 4 -- `effects` (M)

Selects a METHOD. Decode `symbol_facts.effect_summary` with the legend in P8 --
read `TEffectSummary.Decode` (`DRagLint.Analysis.Purity.pas:332`), do not
re-derive it from the data.

Render one row per effect the method HAS: writes globals / writes self / mutates
parameter *k* / frees-or-resizes heap / unknown.

**THE HEADLINE COMES FROM `effect_free`, NEVER FROM `effect_summary` BEING
NULL** -- see P9 above. Three states, and they must be three different chart
outcomes:

| `effect_free` | render |
|---|---|
| `1` | **pure** -- 2,892 methods on CLIENT |
| `0` | the decoded effect rows |
| NULL | **not analysed** -- only 855 on CLIENT |

**Parameter ordinals are ZERO-BASED** (P8). `p1` is the SECOND parameter.
Measured: `g,p1` on `(Sender: TObject; var Key: Word; ...)` is `Key`.

**`mutates_params` is not always available** -- 37 of 298 p-token rows on CLIENT
have it EMPTY (e.g. `p1,?` on `(const S: string; out V: Integer)`), so roughly
12% cannot be named. Those rows say `parameter #1` and say WHY the name is
missing; they do not guess and do not silently drop.

**`?` is not an effect, it is an ADMISSION**, and it is the most common token
(3,148 bare `?` on CLIENT). Render it distinctly -- dashed, like the name-match
bucket in who-calls -- and never let `g,s,?` read as a complete answer. Note
`Decode` (`Purity.pas:340-352`) lowercases and folds ANY unknown token to `?`,
so an unrecognised future token degrades to "unknown" rather than erroring.

**VERIFY** one method per shape: `effect_free=1` with NULL summary (2,892
available -- must render PURE, not "not analysed"); bare `s` (2,494); `g,s,?`
(149); `g,p1,?` (59) asserting the named param is the SECOND one; and one
`effect_free IS NULL` (855) rendering "not analysed". Assert each decode against
the raw stored string.

## Task 5 -- `architecture` (XL)

Selects the PROJECT. **Read P10 before scoping this -- the shortcut is half a
shortcut.**

`deps-report --format json` classifies **external** units only: 283 externals,
30,702 external edges, all 283 `resolved:false`, in 5 groups -- RTL 58 units,
DevExpress 163, Spring4D 4, FireDAC 10, unknown 48. (`project_unit_count` is
"project units USING that group", not a count of project units in it.)

**It says nothing about the internal structure of the 563 project units**, which
is most of what an architecture chart is. That has to come from
`unit_uses.target_file_id` (2,858 internal edges) plus a layering rule this
project does not yet have.

So this task has TWO halves, and only the first is de-risked:

1. **Third-party zones** -- ships on `deps-report` almost directly. Disclose the
   48 `unknown` units rather than hiding them, and note the classifier gap the
   red-team found: bare `spring` (the Spring4D root unit) lands in `unknown`
   while `spring.Collections.Dictionaries` is correctly Spring4D.
2. **Internal layering** -- needs a design decision (folder? namespace prefix?
   declared layer?) and a layout strategy. **Budget this separately.** If it is
   not converging, ship half 1, which is useful alone, and say so.

**Do NOT use `graph` (P11)** -- not because it writes (it does not; `DoGraph` at
`CLI.pas:8031-8133` runs one SELECT), but because its edges are
`LOWER(s.name)=LOWER(r.name_text)` NAME MATCHES (`:8088`), not uses-edges. A
dependency chart built on name collisions would be confidently wrong, which is
worse than absent. Its RW connection is also what makes it fail `database is
locked` against a live DB.

The hard part is LAYOUT, and it is genuinely new: the other ten emitters are
row-clusters around a focus, and this one is zones of units. Budget the design
separately from the build; if the layout is not converging, ship the
group-summary chart (5 zones + counts + the unknown disclosure) first, which is
useful on its own, and treat per-unit placement as a follow-up.

`deps-report` returns 185,053 bytes of JSON -- parse it once, do not re-run it
per zone.

---

## Negative tests -- each MUST fail as stated, leaving no `.svg`

| # | command | expected |
|---|---|---|
| N14 | `Emit-Lifecycle -Form <a non-form class>` | refuses. **U2: this must check HERITAGE (`type_ancestors`), not "has zero dfm_event rows"** -- a real form with nothing wired also has zero, and the two are different answers |
| N14b | `Emit-Lifecycle -Form uMain.TfrmMAIN` | **U1**: `FormDestroy` exists at `uMain.pas:138,422` but is NOT wired in the DFM. The row must read "implemented, not wired", NEVER "(not implemented)" |
| N15 | `Emit-Wiring -Interface <a class, not an interface>` | refuses naming the kind |
| N16 | `Emit-Wiring -Interface <unregistered interface>` | 0 registrations is an ANSWER: renders, exits 0, discloses the CLIENT/SERVER split (P7) |
| N17 | `Emit-Effects -Qname <NULL effect_summary AND effect_free=1>` | renders **PURE**, exits 0. The naive reading calls this "not analysed" and is wrong for 2,892 CLIENT methods -- see P9 |
| N17b | `Emit-Effects -Qname <effect_free IS NULL>` | renders "not analysed", exits 0. Only 855 on CLIENT genuinely are |
| N18 | `Emit-Cycles` on an acyclic index | "no cycles" is an answer; renders, exits 0 |
| N19 | any emitter pointed at a LIVE corpus DB | refuses via `Get-CloneDb` |

## STOP -- do not

* Touch anything outside `charts\`.
* Run `drag-lint index` / `fb-snapshot` / `autodoc` on ANY database, clone or live.
* Use the `graph` verb (P11) or `symbol_facts.wiring` (P6).
* Re-baseline the 9 currently-red assertions -- see below.
* `git push`, `git add -A`, bare `git stash`, or commit `scratch\`/`artifacts\`.

---

## The 9 red assertions -- LEAVE THEM RED

The suite currently exits 1 with 9 failures, in exactly two families. **They do
NOT have the same cause, and the red-team corrected this:**

* **The 2 property-backing failures are a DATA CHANGE, not a misread.**
  `accessor_symbol_id` is NULL for all 602 `Connected` rows *on the clone*, so
  that is what the 1.6.0 resolver STORED. Redeploying the engine will not bring
  `FConnected` back -- only the engine team restoring the binding would. This is
  the question the INBOX note asks them.
* **The 7 callee-direction failures are still unattributed.** `call_edges` row
  COUNT is unchanged at 20,343, but its CONTENTS are resolver-written too
  (P12), so "our engine misreads 1.6.0 edges" and "the 1.6.0 resolver produced
  different edges" are both live explanations. Do not assert either.

```
callee-direction (7)   A-BF-CALLEES 8->3, A-BF-CLICKS 18->13,
                       A-WIC2-ROWS/NODES, A-WIC3-ROWS/NODES/CYCLES
property backing (2)   A-MA3-BACKING FConnected->'', A-MA4-READS 602->0
```

Everything else passes: callers 9/10, deps 18/3, event-wiring 41/41/40 and 96,
touches-tables 5/5/2, hierarchy 145/2, class-surface 392, member-access on
R / VERDICT / Connected.

**Do not edit those numbers to match.** They are the detector. When the engine
matches the index, re-run: whichever failures persist were DATA changes and
need the numbers re-baselined with a note saying what moved and why; whichever
clear were skew. Editing them now destroys the only evidence either way.

Expect the 2 property-backing ones to PERSIST on current information.

## AFTER the five are done -- the re-assessment step

This is part of the plan, not an afterthought.

1. **Check the INBOX** -- `C:\Projects\Delphi-RAG-lint\docs\INBOX-*` -- for the
   engine team's replies, specifically:
   * the resolver downgrade guard (our urgent note);
   * whether the **field-backed property accessor going NULL** was intended
     (`Connected` -> `FConnected` binding lost; property->method accessors
     survived at 5,343 of 5,952). Asked, deliberately not filed.
2. **Check whether the engine has been redeployed**: one command --
   `drag-lint --version` plus `schema_meta` on a clone. If it now reads
   `1.17.0-alpha` / `r=1.6.0-alpha`, the skew is over.
3. **Re-measure the premises of the HELD two** (below) and of the remaining
   catalogue rows, because what is doable will have changed. Do NOT trust the
   effort estimates in `STATUS-questions.md` -- they are first guesses, and the
   last batch proved a fully-measured plan still carried six wrong premises.
4. **Re-clone** from the then-current corpus before measuring anything.

### HELD until the engine matches the index

| question | why held |
|---|---|
| `change-impact` (M) | the `impact` verb walks `call_edges`; the callee direction is demonstrably wrong under the skew |
| `tested-by` (M, re-sized from L) | reachability over `call_edges`, same exposure. NOTE: cheaper than STATUS says -- the TEST project DB already CONTAINS the code under test (`MicroniteTests.sqlite` holds `MSCTYPES.pas` 724 symbols and `uCompGroupTree.pas` 106 alongside DUnitX, 1,448 call_edges), so it is a SINGLE-DB pass per test project, run four times, not a cross-DB join |

### Still blocked, unchanged

`shown-where` (L, `ui_affinity` 230/37 -- partial by nature);
`lands-where` / `feeds-from` / `consumers` (need a live Firebird via
`fb-snapshot`); `protocol-trace` x2 / `crosses-boundary` (enum binding);
`exception-paths` (raise/handle); `compare` (XL -- parked by owner decision, and
genuinely dependent on the IR; there is no `ir` or `compare` verb in the
deployed engine, confirmed against a deliberate fake control).
