<!-- dl:backlog status=open last-measured=2026-09-22 -->
# Diagram question catalogue -- the closed set `drag-lint ask` must answer

drag-lint is not a model. Every diagram must come from a FORMAL CALL: a question
id, a selection, and parameters. This is that set.

Rendered companion: `charts\shell\question-catalogue.html`.
Blocking engine work: `docs\INBOX-URGENT-engine-facts-for-diagram-questions.md`.

## The call shape

```
drag-lint ask --list --at <file>:<line>:<col> --db <db> --json
   -> resolves the selection, returns ONLY the questions valid for its KIND

drag-lint ask --question <id> --at <file>:<line>:<col> --db <db>
              [--depth N] [--max-branches N] [--sinks ui,db,boundary,file]
              --format dlgraph|script|svg|mermaid|json
```

The IDE never hard-codes the menu; it asks the engine and renders what comes
back. **`drag-lint typeat <file>:<line>:<col>` already resolves a caret to a
symbol**, so the selection half exists -- `ask` reuses that resolver and
dispatches on the resolved kind.

## Status legend

* **SHIP** -- facts exist AND a verb already emits dot/mermaid, or needs only a
  serializer.
* **ASSEMBLE** -- facts exist, the emitter does not.
* **NO DATA** -- the fact TABLE exists in schema 23 but is empty in every index
  measured (see GAP 3 in the urgent INBOX).
* **BLOCKED** -- needs an engine fact that does not exist.

## The catalogue

| question | select | produces | stands on | status |
|---|---|---|---|---|
| `who-writes` | field / property | fan-in tree of every write site | `member_accesses.mode=write`, `symbol_facts.writes_fields` | SHIP |
| `who-reads` | field / property | fan-out tree of every read site | `member_accesses.mode=read`, `symbol_facts.reads_fields` | SHIP |
| `who-calls` | method | N-deep caller tree, cycle-guarded | `reverse-calltree` (emits dot+mermaid) | SHIP |
| `what-it-calls` | method | N-deep callee tree | `callgraph --direction callees` | SHIP |
| `butterfly` | method | callers above + callees below in one chart | `butterfly` verb (dot+mermaid) | SHIP |
| `change-impact` | method / type | everything a change here could break | `impact` verb | SHIP |
| `touches-tables` | method | which DB tables it reads and writes | `symbol_facts.sql_reads` / `sql_writes` -- **SERVER ONLY** (client has no FireDAC connection; 0/0 is correct) | SHIP* |
| `tested-by` | any symbol | which tests cover this | `symbol_facts.covered_by` -- **0 rows in every index** | NO DATA |
| `effects` | method | what it mutates, owns, and whether it is pure | `effect_summary`, `effect_free`, `mutates_params`, `returns_owner` | SHIP |
| `class-surface` | type | members, visibility, inheritance | `surface` verb | SHIP |
| `hierarchy` | type | ancestors and descendants | `query descendants` / ancestors | SHIP |
| `deps` | unit | dependency neighbourhood | `graph` verb (dot+mermaid) | SHIP |
| `cycles` | unit / project | circular deps + refactoring plan | `cycles --plan` | SHIP |
| `wiring` | interface / type | Spring4D registrations + DFM event edges | `wiring`, `di_bindings` | SHIP* |
| `lifecycle` | form / type | create -> show -> destroy with handlers | `symbol_facts.dfm_event` | ASSEMBLE |
| `event-wiring` | control | which handler runs on which event | `symbol_facts.dfm_event` | ASSEMBLE |
| `architecture` | project | units/packages/DI as trust-zoned rectangles | `graph` + `deps-report` + `di_bindings` | ASSEMBLE |
| `compare` | two index runs | before / delta / after | needs the IR; no new facts | ASSEMBLE |
| `shown-where` | field / column | which forms and controls display this | `ui_affinity` + DFM props (partial) | ASSEMBLE |
| `lands-where` | field | field -> dataset -> table.column | `orm_links` -- **0 rows everywhere** | NO DATA |
| `feeds-from` | control | control -> datasource -> memtable -> table | `orm_links`, `fb_datasets` -- **0 rows** | NO DATA |
| `consumers` | table / column | every unit reading or writing it | `fb_columns`, `fb_relations` -- **0 rows** | NO DATA |
| `protocol-trace` | field / property | the round trip UI -> memtable -> boundary -> server -> DB and back | enum-value binding (GAP 1) | BLOCKED |
| `protocol-trace` | method | call tree pruned to payload-carrying branches, across boundaries to a sink | GAP 1 + branch ranking | BLOCKED |
| `crosses-boundary` | method | whether and where this leaves the process | GAP 1 | BLOCKED |
| `exception-paths` | method | what can be raised and where it is caught | raise/handle fact (GAP 2) | BLOCKED |

`SHIP*` -- `wiring` ships, but `di_bindings` reads CLIENT=4 against SERVER=535.
Confirm local-container registrations are captured before trusting it on a
client project.

## Branch policy for the trace questions -- decided 2026-09-22

The owner asked whether a forking method trace should follow the longest path.
**No.** Longest is a proxy for "interesting" and a bad one -- a logging helper or
a validation chain out-runs the real path every time.

1. **Follow the payload, not the calls.** A trace is a data slice; keep a branch
   only while it still carries the selected value. This is why the OPERAT.NAME
   trace is 33 steps and not hundreds.
2. **A trace is defined by its endpoints, not its depth.** Closed sink set: UI
   control, SQL table/column, process boundary, file/log, and "consumed and
   discarded" -- which is a real answer, not a failure.
3. **Rank, cap, disclose.** Order: crosses a boundary > reaches DB > reaches UI >
   terminates internally. Show the top few, collapse the rest as an explicit
   expandable row. **Never drop a branch silently** -- same rule as the linter;
   a hidden finding teaches the reader to distrust every shown one.
4. **When the payload cannot be followed, say where it stopped.** Mark every edge
   `[certain]` or `[inferred]`; render inferred dashed.

## Rendering decisions that came out of the same review

* **Steps group into UNIT RECTANGLES**: header = unit name, steps are clickable
  TEXT ROWS inside it, not separate nodes. This collapses 33 nodes into 6
  rectangles AND makes the chart near-lossless -- guards become rows, so the
  `OTHERWISE` clauses that a node-per-step chart drops are preserved.
  * UNVERIFIED: whether Graphviz `HREF` on an HTML-like table cell survives into
    the SVG as a real anchor. If not, row bands must be computed from font
    metrics against `-Tplain` geometry.
* **Provenance granularity is the STEP, never the enclosing routine.** Measured:
  steps 28-32 of the OPERAT.NAME trace all live inside `HandleTableLoad`
  (uPipeSessionBuilder.pas:533-597). Per-method provenance would have collapsed
  five distinct actions onto one header.
* **These artifacts are NOT autodocumentation.** They are large, slow to
  produce, and stable over time. The user generates one deliberately and inserts
  a REFERENCE into the code or its documentation. Put the volatility in the FILE
  (stable path + regenerated artifact), never in the comment -- which also
  sidesteps the generated-vs-hand-written provenance question, and keeps the
  autodoc rewriter out of it entirely.
## Engine answers received 2026-09-22 (session `delphi-rag-lint-75`)

**NO DATA is worse than it looked -- treat `orm_links` / `fb_*` as optional
ENRICHMENT, never as a source.**

* `fb_relations` / `fb_columns` / `fb_datasets` / `fb_field_info` /
  `fb_enum_values` are written by `drag-lint fb-snapshot`, which opens a
  **TFDConnection with DriverID=FB** -- populating them REQUIRES A LIVE FIREBIRD
  CONNECTION.
* `orm_links` is a CROSS-DB link table (`delphi_symbol_id`, `delphi_db_index`,
  `sql_symbol_id`, `sql_db_index`) joining a Delphi index to the SQL index, so it
  is empty in a pure Delphi project DB **by construction**.
* Both are also empty in the SQL index itself -- the ingest has never been run on
  this box.
* **Consequence:** a diagram that must be reproducible FROM THE INDEX ALONE
  cannot depend on them today, and cannot tomorrow either unless someone runs
  `fb-snapshot` against a live Firebird and ships the resulting SQL index as an
  input. `lands-where`, `feeds-from` and `consumers` are therefore not near-term
  work, and should not be planned as if they were.

**Cross-DB identity -- safe, with a caveat we had not considered.**

`qualified_name` + declaring file path + `start_line` identifies the same
declaration across two Delphi indexes that both compile that file.
`symbols.id` is per-database and must never cross a DB boundary.

> **The caveat: preprocessor branches.** Two projects compiling the same unit
> with different `{$IFDEF}` sets do not necessarily hold the same SET of symbols
> -- a declaration inside a branch one project does not take is absent from that
> index entirely. **The join must tolerate ABSENCE on either side and must never
> infer "removed" from "not present in the other DB".** Source positions do not
> shift with defines; membership does.

Status: engine-session statement of 2026-09-22, cited as such. NOT yet an
owner-blessed normative contract.

**Resolver bump cost, corrected.** Our urgent note overstated it. Measured by the
engine session: ~6 min across project sections and ~74 min per platform library,
and it is a re-RESOLVE, not a re-parse. It slots against A1 and C2.4 in the
engine queue rather than jumping them.

**The parallel-stream promise survives for 23 of 24 questions.** Only the
enum-value binding needs a `DRAGLINT_RESOLVER_VERSION` move; everything else in
this catalogue still needs no bump, no re-parse and no schema change.

## Reader beware -- `butterfly/1` JSON

The CALLEES tree nests its children under a field named **`callers`**. Reading
`callees.root.callees` returns nothing, with no error, so a method with 8 real
callees reports 0. Flatten both sides on the `callers` key.