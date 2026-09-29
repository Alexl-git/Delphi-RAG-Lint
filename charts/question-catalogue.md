<!-- dl:backlog status=open last-measured=2026-09-23 -->
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
| `tested-by` | any symbol | which tests cover this | COMPUTED, not stored -- see the covered_by note below | SHIP |
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
| `lands-where` | ORM property / field / control | property -> server write/read path -> TABLE.COLUMN -> triggers | DFM bindings + SERVER member accesses and SQL literals + SQL-script index; TABLE.COLUMN by naming convention `[inferred]` (`orm_links` 0 rows) | SHIPPED (derived) |
| `feeds-from` | control | control -> datasource -> dataset -> view model -> TABLE.COLUMN | DFM bindings + dataset assignments + SQL literals + SQL-script index (`orm_links`, `fb_datasets` 0 rows) | SHIPPED (derived) |
| `consumers` | table / column | readers, writers, triggers, procedures, indexes | `sql_reads`/`sql_writes` `[certain]` + SQL-verb literals `[inferred]` + SQL-script index (`fb_*` 0 rows) | SHIPPED (derived) |
| `protocol-trace` | field / property | the round trip UI -> memtable -> boundary -> server -> DB and back | enum-value binding (GAP 1, closed) | SHIPPED |
| `protocol-trace` | method | call tree pruned to payload-carrying branches, across boundaries to a sink | GAP 1 + branch ranking | SHIPPED |
| `crosses-boundary` | method | whether and where this leaves the process | GAP 1 | SHIPPED |
| `exception-paths` | method | what can be raised and where it is caught | exception refs CLASSIFIED by source token (no raise/handle fact exists) + caller walk | SHIPPED (classified) |
| `round-trip` | control / interface field / TField variable / TABLE.COLUMN | the data anchor, then WRITE (handler -> sender -> pipe -> server -> apply -> column -> response) and READ (fill -> pipe -> server -> query -> back), plus every other route, as Form A text | DFM bindings + code re-point + refs/call_edges/string_literals on CLIENT and SERVER queried separately + SQL-script index; conditions from fresh SOURCE (E1), dispatch by adjacency (E2), wiring by name (E3), statement text absent (E4) | SHIPPED (text; chart later) |

`SHIP*` -- `wiring` ships, but `di_bindings` reads CLIENT=4 against SERVER=535.
Confirm local-container registrations are captured before trusting it on a
client project.

**Status as of 2026-09-28: every row except `compare` is SHIPPED** (26 of 27;
live scoreboard `STATUS-questions.md`). The status column above keeps the
original legend for the rows that were SHIP from the start; `shown-where` runs
on DFM data bindings, not `ui_affinity` (a thread-affinity hint, 0 of 13,131
fields carry one).

## The last five questions -- how to ask them, what they answer, what they cannot see

All five are bundled by `src\New-DiagramArtifact.ps1` (writes `graph.svg` --
or, for the TEXT question `round-trip`, `trace.dlgraph` shown in a `<pre>` --
`index.html`, `meta.json` with the regenerate command, and the xref). The
paths are the CLONES under `charts\scratch\db\`; `Get-CloneDb` refuses anything
else.

```
New-DiagramArtifact.ps1 -Question exception-paths -Target <Unit.Class.Method> -DbPath <clone> [-Depth 3] [-Cap 20]
New-DiagramArtifact.ps1 -Question consumers  -Target TABLE|TABLE.COLUMN -DbPath <Delphi clone> -SqlDbPath <SQL clone>
New-DiagramArtifact.ps1 -Question feeds-from -Target <Form>.<Control>    -DbPath <Delphi clone> -SqlDbPath <SQL clone>
New-DiagramArtifact.ps1 -Question lands-where -Target <Tmc/Imc property | field | Form.Control> `
                        -DbPath <CLIENT> -ServerDbPath <SERVER> -SqlDbPath <SQL>
New-DiagramArtifact.ps1 -Question round-trip -Target <Form>.<Control> | <Unit>.<TForm>.<Control> | <Unit>.<TClass>.<TField var> | TABLE.COLUMN `
                        -DbPath <CLIENT> -ServerDbPath <SERVER> -SqlDbPath <SQL> [-Depth 4]
```

`exception-paths` defaults to `-Depth 3` and `round-trip` to `-Depth 4` (the
shared default is 2); an explicit `-Depth` wins. `consumers` / `feeds-from` /
`lands-where` refuse without `-SqlDbPath`; `lands-where` also refuses without
`-ServerDbPath`; `round-trip` refuses unless both `-ServerDbPath` and `-SqlDbPath` are given.
A `round-trip` `TABLE.COLUMN` selection that is not loaded by exactly one dataset
ends in ONE named `STOPS` listing the datasets (gate `RT-N2`: `OPERAT.NAME`, 5
datasets load OPERAT in the CLIENT clone) -- pass the control or the dataset field.
A `round-trip` selection bound to a CALCULATED field (written by the dataset's
`OnCalcFields` handler) stops at its anchor saying so, and offers its source fields
in a `DERIVED` section, each with a ready command to trace it instead (gate
`RT-CALC`: `frmBlueprint4.dxDBGrid1FtrsVFtrName`, 18 source fields).

| question | answers | caveat |
|---|---|---|
| `exception-paths` | which exception types this routine raises (and re-raises), which handlers in its body catch what, and where each type is caught or escapes up to N caller levels | no raise/handle fact exists: refs are CLASSIFIED by the source token before them, on sha256-fresh files only; bare `except` / `raise;` are `[inferred]`. A solid catch requires the call inside the handler's `try`. The walk follows resolved call edges only -- a call the resolver cannot bind (dispatch; parenless calls until engine D1 was fixed in resolver 1.7/1.8) thins it -- and a walk that ends is "no resolved caller", never "unhandled" |
| `consumers` | who reads and writes a table or column: routines (fact `[certain]`, literal `[inferred]`), `[by name]` mentions, triggers, procedures, indexes | `sql_reads` misses SQL passed through a variable (`SQL.Add(sTmp)`; the multi-line `SQL.Add` gap, engine D18, is fixed in extractor 1.19), so inferred readers are drawn beside certain ones and both counts are printed. Schema = SQL scripts, newest declaration wins; 5 live `PDF_*` tables absent |
| `feeds-from` | where a data-aware control's value comes from, hop by hop, to TABLE.COLUMN, plus code that re-points or re-binds it | stops rather than guess on a dangling module, an interface-typed view model or several candidate tables; per-control coverage printed (267 of 808 reach one table on CLIENT) |
| `lands-where` | where an ORM property (or DFM-bound field) lands: the server's write and read path, TABLE.COLUMN, the triggers touching it, and the client bindings | TABLE.COLUMN is a naming convention, `[inferred]`, with measured coverage printed (1,992 of 1,997); positional `Params[i]` / `Fields[i]` are not visible |
| `round-trip` | the full path of one edited field, both directions, with the guards that end it and the branch that reverts it | the index holds tokens, not branches: conditions are read from sha256-fresh source: an `if` condition is quoted verbatim, a `try` / `except` one is the statement text plus a generated ` raises` (` ... ` for statements left out), a `case` one is the `case X of` header with its else arm named in the note (grammar spec section 8); a stale file refuses; a hop the index cannot make is a numbered STOPS counted as unresolved; ALSO is owner-accepted 2026-09-28 (AC-10: all callers count; dataset scope; anchors only). Known limits beside the gate's "17/17 golden nodes matched, 3 golden facts disclosed, 12/12 guards" (`frmBlueprint4.dxDBGrid1OperationVName`): a guard sees only the INNERMOST enclosing `if` of its Exit (E1 retires it), and `OMITS` tests every enclosing `if` up to a loop or case arm; a direction that stops after the anchor (no wiring, no crossing, no server dispatch) notes each tier it did not reach as `not walked` and the title claims only the walked direction; golden READ facts [28]-[29] (transport helpers at `uPipeSessionBuilder.pas:533` / `:534` / `:538`) are disclosed, not matched; the texts of the statement for the posted row and of the SELECT live in FIB$ rows the clones do not hold (E4). A CALCULATED anchor field (an `OnCalcFields` handler writes it; the wiring is a same-line name match, E3) is a `STOPS` plus a `DERIVED` offer of its source fields: the TField variables (and locals set from ONE of them, one hop) and `DataSet.FieldByName('<lit>')` reads on the write statements are offered, plus the reads in a `case` selector that picks the formula (a case arm is not a guard) -- a routine called in the computation is named once, its body not walked; a source that is itself calculated is marked, not expanded; a value the walk cannot map is named, not guessed; the enclosing conditions are the if-forms only, read outwards past a case; a shape the reader cannot place is named in the STOPS note; constants are no values (by name shape: the charts read clones only); a field set only in another event's handler, or a lookup, is a named `STOPS` with no offer |

Column states (`consumers` column form, `feeds-from`, `lands-where` -- one
function, `Get-SqlColumnState`): **column** (extracted from the newest
declaration), **quoted** (a quoted identifier in the newest declaration that the
SQL index does not extract; found by source scan, `[inferred]` -- engine D19,
`INBOX-sql-index-drops-quoted-identifiers.md`, is fixed in extractor 1.19, so no
real column reaches it; kept as a guard), **older-only** (extracted only from an older declaration),
**server-sql** (not extracted, not quoted, but SQL in the Delphi index names it),
**[stale source]** (the script differs from the index: not scanned, NOT known --
never shown as an absence), **not-a-column** (named by none of it: lands-where says
computed or UI-only; consumers refuses, worded "not extracted as a column by the
SQL index").

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