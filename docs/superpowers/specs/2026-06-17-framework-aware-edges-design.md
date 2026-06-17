# Framework-Aware Edges (Spring4D DI + DFM wiring) - Design

Date: 2026-06-17
Status: Approved design, pre-plan
Source: CodeGraph review (2026-06-17) idea #1 + live ORM3 inspection.
Related: `docs/BACKLOG-codegraph-parity.md`, `docs/BACKLOG-graphify-parity.md`.

## 1. Goal & success criteria

Make Spring4D dependency-injection wiring and DFM event wiring first-class,
queryable edges so an AI agent can answer, in ONE call:

- "What implements `ImcSTATIONS`, with what lifetime, and where is it resolved?"
- "What handler runs for this form's button OnClick?" / "What wires to
  `TfrmX.ButtonClick`?"

These are invisible to a plain call graph today: DI resolution is dynamic (the
container holds the I->T mapping) and DFM event bindings live in the .dfm.

**Done when:**
1. Smoke tests prove correct extraction on fixtures (correctness gate).
2. An agent-task benchmark shows fewer tool-calls AND fewer tokens vs a no-edges
   baseline on these question types (value gate - idea #4).

## 2. Evidence from the live codebase (why this shape)

Inspected ORM3 (`C:\Projects\DB\ORM3\drag-lint.sqlite` + source) on 2026-06-17:

- `GlobalContainer` has **823** call refs, but `Resolve` / `RegisterType` /
  `RegisterInstance` have **0** - the parser captures the container access but
  NOT the chained generic method call or its type arguments. This is the parser
  gap the feature must close.
- Real registration idiom (`CLIENT\uClientContainer.pas`, `SERVER\uContainerConfig.pas`,
  `PACKAGE\uInterfacesRegistration.pas`):
  ```pascal
  GlobalContainer.RegisterType<TmcSTATIONS>.Implements<ImcSTATIONS>.AsSingleton;
  GlobalContainer.RegisterType<TDataService_CAUSFAIL_SERVER>
    .Implements<IDataService<ImcCAUSFAIL>>.AsSingletonPerThread;   // nested generics
  GlobalContainer.RegisterType<TmcCAUSFAIL>.Implements<ImcCAUSFAIL>;  // transient
  ```
  Legacy form uses `.As<IIntf>` instead of `.Implements<IIntf>`.
- Real resolution idiom (`CLIENT\uAutoTest.pas`):
  ```pascal
  GlobalContainer.Resolve<ImcSTATIONS>.ID;
  var pSt: ImcSTATIONS := GlobalContainer.Resolve<ImcSTATIONS>;
  ```

Architecture hooks (from code map):
- Call-ref emission: `DRagLint.Parser.Delphi13.pas:239` (`EmitCallReference`) via
  `TWalkState.EmitRef` (`:136`).
- DFM event bindings already emitted as `'event-binding'` refs:
  `DRagLint.Parser.DFM.pas:152`.
- Refs insert: `DRagLint.Storage.SQLite.pas:364`; schema (v7):
  `DRagLint.Storage.Schema.pas` (`refs` table lines 46-56, `kind TEXT` is free-form).
- CLI dispatch: `DRagLint.CLI.pas:7969+`; query subcommands `:2097+`.
- MCP tools: `DRagLint.MCP.Server.pas:179+` (list) / `:629+` (call).
- `bench-context`: `DRagLint.CLI.pas:4206-4304` (token-only today).
- Tests: PowerShell smoke (`tests/autotest/*.ps1`) + fixture `.sqlite`; NO DUnitX.

## 3. Chosen approach

**Approach A** - dedicated `di_bindings` table for the two-endpoint I->T binding;
resolve-sites as `di-resolve` refs in the existing `refs` table; DFM handlers
reuse the existing `event-binding` refs (resolved at query time). New `wiring`
CLI + `get_wiring` MCP + context-bundle enrichment.

Rejected: B (everything in `refs`, pair by co-location - fragile, no home for
lifetime); C (resolve-sites + DFM only - drops "who implements IFoo", the point).

## 4. Components (units created / touched)

- NEW `src/parser/DRagLint.Parser.SpringDI.pas` - recognizes the Spring4D fluent
  idiom from the AST call-chain; returns structured DI facts. Isolates this from
  the ~900-line `Delphi13.pas`.
- `DRagLint.Parser.Delphi13.pas` - (a) capture chained generic method-call name +
  type-args (the prerequisite, handling nested generics); (b) at the call-emission
  site, consult SpringDI and emit DI facts.
- `DRagLint.Storage.Schema.pas` - schema v8: `di_bindings` table + v7->v8 migration.
- `DRagLint.Storage.SQLite.pas` - `InsertDiBinding`, `FindImplementationsOf(intf)`,
  `FindResolveSitesOf(intf)`, `FindEventHandlers(formOrComponent)`,
  `FindWiringInto(method)`.
- `DRagLint.Parser.DFM.pas` - unchanged emission; query-time handler resolution
  helper lives in storage/query.
- `DRagLint.CLI.pas` - `DoWiring` + dispatch + flag parse + help.
- `DRagLint.MCP.Server.pas` - `get_wiring` tool (descriptor + handler); enrich
  `get_context_bundle`.
- context-bundle builder - wiring enrichment for interface/class/form bundles.
- bench - agent-task harness (`DoBenchWiring` or extend bench-context).
- tests - `tests/fixtures/di_edges.pas`, `tests/fixtures/dfm_wiring.{pas,dfm}`,
  `tests/autotest/run_wiring.ps1` wired into the smoke runner.

## 5. Data model

`di_bindings` (schema v8):
```sql
CREATE TABLE IF NOT EXISTS di_bindings (
  id             INTEGER PRIMARY KEY,
  file_id        INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  interface_name TEXT NOT NULL,   -- verbatim, incl. nested generics: IDataService<ImcCAUSFAIL>
  impl_name      TEXT NOT NULL,   -- e.g. TmcSTATIONS
  lifetime       TEXT NOT NULL,   -- 'singleton' | 'singleton-per-thread' | 'transient'
  start_line INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line   INTEGER NOT NULL, end_col   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_di_interface ON di_bindings(interface_name);
CREATE INDEX IF NOT EXISTS idx_di_impl      ON di_bindings(impl_name);
```
Per-file cascade-delete matches the existing per-file reindex path (consistent
with `symbols`/`refs`).

New `refs.kind` values (no schema change - column is free-form):
- `di-resolve` - `symbol_id` = enclosing routine; `name_text` = interface resolved.
- `di-unresolved` - a DI registration call detected but NOT resolved into an I->T
  binding (named/instance/delegate/bare-Register); `name_text` = method name.
  Captures coverage gaps so deferred-form usage is measurable, not silently lost.

DFM `event-binding` refs (existing): `symbol_id` = component symbol,
`name_text` = handler method name. Reused as-is.

## 6. Parser prerequisite (shared foundation)

At the member-access call walker, for `recv.Method<TypeArgs>(...)`:
- Capture `Method` as a normal `'call'` ref (side-benefit: `find-callers Resolve`
  and `find-callers RegisterType` start working).
- Capture the generic type-argument list, preserving nesting verbatim.
- Expose (method name, receiver text, type-arg list, position in chain) to SpringDI.

## 7. DI detection rules (v1), keyed on method names (receiver-agnostic)

Receiver-agnostic so `GlobalContainer`, a local `TContainer`, and
`GlobalContainer.Registry` all work.

- Registration: `RegisterType<TImpl>` + same-chain `.Implements<IIntf>`
  (or legacy `.As<IIntf>`); lifetime `.AsSingleton` -> 'singleton',
  `.AsSingletonPerThread` -> 'singleton-per-thread', else 'transient'. Emit one
  `di_bindings` row (IIntf, TImpl, lifetime, location).
- Resolution: `Resolve<IIntf>` / `TryResolve<IIntf>` -> emit `di-resolve` ref
  (enclosing routine, IIntf).
- Nested generic type-args preserved verbatim.

**Deferred resolution, but DETECTED and FLAGGED (not silently dropped):**
`.Named('x')`, `RegisterInstance`, delegate/factory (`DelegateTo`), bare
`Register<T>` without `.Implements`. v1 does not resolve these into I->T bindings,
but emits a `di-unresolved` ref (method name + location) for each, so a coverage
query reveals whether/where these forms are actually used across the indexed apps.
ORM3's dominant idiom is `RegisterType.Implements[.AsSingleton]`; usage of the
deferred forms is currently UNCERTAIN, so v1 measures it rather than guessing. If
the flag shows a deferred form is common in another app, v2 resolution is a small
follow-up keyed on the same SpringDI recognizer.

## 8. DFM wiring (surface existing data)

No new extraction. v1 adds query-time resolution: given a form, resolve each
`event-binding` handler name to the method symbol in the form class; expose as
edges (component.event -> handler). No schema change.

## 9. CLI / MCP / context surface

CLI:
```
drag-lint wiring --qname <IIntf|TImpl|TForm[.Method]> [--db ...] [--format text|json]
```
- interface -> implementations (+lifetime) + resolve-sites.
- class -> DI interfaces it implements + resolve-sites of those.
- form/method -> event bindings into/out of it.
- `--coverage` (no qname) -> summary of `di-unresolved` registrations grouped by
  method + unit, so deferred-form usage is visible at a glance.
Output mirrors `impact` text/json conventions.

MCP: `get_wiring` tool { qname, [kind], [format] } alongside `get_impact`.
Highest-leverage integration: enrich `get_context_bundle` so a bundle for an
interface/class/form auto-includes its wiring facts (no extra call).

## 10. Testing & benchmark gate

- Smoke (correctness, TDD inner loop): `di_edges.pas` asserts `di_bindings` rows
  (intf/impl/lifetime incl. nested-generic + per-thread) and `di-resolve` refs;
  `dfm_wiring.{pas,dfm}` asserts event->handler resolution. New `run_wiring.ps1`
  wired into the existing smoke runner.
- Benchmark gate (value, idea #4): agent-task harness over a fixed task set
  ("who implements ImcSTATIONS / where resolved", "what handles TfrmX button")
  measuring tool-calls + tokens with vs without wiring edges/bundle enrichment.
  Done when both drop. Extends `bench-context` methodology.

## 11. Phasing (one spec, phased plan)

- P1 Engine: parser prerequisite + SpringDI + `di_bindings` schema/migration +
  storage queries + `di-resolve` refs. Smoke tests.
- P2 Surface: `wiring` CLI + `get_wiring` MCP + context-bundle enrichment.
  Smoke tests.
- P3 Gate: agent-task benchmark; confirm `docs/BACKLOG-codegraph-parity.md`
  (#2/#3 future ideas) is in place.

## 12. Out of scope

- Ideas #2 (one-command install/auto-wire MCP) and #3 (MCP initialize self-guidance)
  - saved to `docs/BACKLOG-codegraph-parity.md`, not built.
- Deferred DI forms per section 7.
- Multi-language / universal RAG - explicitly declined (Delphi-deep moat).

## 13. Open points carried as defaults (flag to change)

- Context-bundle enrichment (section 9) is IN for P2 (not deferred).
- New CLI command name is `wiring` (single command covering interface/class/form),
  not separate `di` + `handlers` commands.
- `di-resolve` is a `refs.kind`; only the I->T binding gets its own table.
