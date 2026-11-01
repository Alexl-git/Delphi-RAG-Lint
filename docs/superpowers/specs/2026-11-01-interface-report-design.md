# Interface report (`implementors`) -- design

Status: APPROVED 2026-11-01 (owner rulings in section 10). Lane `ifrpt` (1.40, branch `lane/x129-ifrpt`).
Sibling lane: `call` (`lane/x129-call`: METHRES-DISPATCH, RB5-IFACE, GAP-CALLERS).
No code in this lane until the owner rules on section 9.

Owner request (2026-11-01): "a tool to deal with interfaces and implementors: a report
(charts and/or text) on who (which implementers, which objects) implements this interface
method and where, or who uses this interface property, etc."

## 1. Questions answered

| # | Target | Question | Answer rows |
|---|---|---|---|
| Q1 | interface `IJob` | which classes implement it (directly, through a derived interface, through an ancestor class, through `implements` delegation)? | class, how (`lists` / `via IJobEx` / `inherited from TBase` / `delegated by property P`), file:line |
| Q2 | interface method `IJob.Execute` | which methods answer it, in which class, where? | implementing class, answering method (incl. a method-resolution clause `procedure IJob.Execute = RunJob` -> `RunJob`), declared-in class when inherited, file:line of decl + body, confidence |
| Q3 | interface method / property | who calls / reads / writes it? | call and use sites attributed to the INTERFACE member (RB-5 ruling 2026-09-16), with enclosing routine, mode (call/read/write), file:line |
| Q4 | implementing method `TJob.RunJob` | which interface methods does it answer, and which sites reach it only through the interface? | interface member(s), the "via IJob.Execute dispatch" site group (same shape as `find-callers`) |
| Q5 | class `TJob` | which interfaces does it implement, incl. inherited and delegated, and which method answers each member? | interface, how, per member: answering method or `NOT ANSWERED` (a compile error or an index gap) |

Q3 never fans an interface call out to implementors (RB-5). Q4 is the only place sites are
shown against an implementor, and they are labelled `via` -- exactly what `find-callers`,
`context` and `impact` already do.

## 2. What the index answers TODAY (measured, read-only, 2026-11-01)

DBs: `src\cli\_D-RAG\drag-lint.sqlite` (1.39.2-alpha, extractor 1.28.0; 1 file stale) and a
scratch fixture `C:\TEMP\claude\lanes\140\agent-ifrpt\fx\IfFix.pas` indexed into a scratch DB
(plain impl, resolution clause, inherited impl, derived interface, delegation, interface
property, three call shapes). Library-Win64 counts are from the deployed library DB.

| Fact | Table | src\cli | Fixture verdict |
|---|---|---|---|
| interfaces / their methods | `symbols` kind `interface`, children `method`/`property` | 11 / 199 methods, 0 properties | OK |
| class lists interface | `type_ancestors` (ancestor_kind `interface`, resolved id) | 15 rows, all resolved | OK; `query ancestors` is transitive (TInheritedJob -> TBaseJob, IJobEx, IJob) |
| interface method -> implementor | `dispatch_edges` kind `implements` | 222 certain, 0 ambiguous (lib: 36,146) | OK for plain and inherited impl |
| inherited impl: WHICH class | -- | -- | edge is `IJob.Execute -> TBaseJob.Execute`; TInheritedJob (the class that LISTS IJob) is NOT on the edge, and N inheriting classes collapse to one row. Recoverable at query time from `type_ancestors` + the class chain |
| method-resolution clause | `symbols`, `dispatch_edges` | n/a | WRONG: a phantom `TRenamedJob.Execute` method (impl_start_line 0) is emitted and the edge points at it; `RunJob` appears only as an unresolved `read` ref on the clause line (find-callers: 1 name-only). = METHRES-DISPATCH |
| `implements` delegation | -- | -- | MISSING: property `Inner` stored as `ro`, no implements fact; only a `type_use` ref to IJob on the property line; no dispatch edge (resolver counts NoImpl) |
| interface call `pJob.Execute` | `call_edges` | 1,203 edges with an interface receiver, all to the interface method, certain | OK -- RB-5 attribution already holds for typed receivers |
| interface property read `pJob.Name` | `member_accesses` (mode read, accessor GetName) | 0 props in src\cli | OK |
| interface methods with no implementor | anti-join | 7 (IQueryEngine.*: no class implements it) | OK -- a true answer, not a gap |

Already shipped consumers of these facts (RB-5 read side): `query find-callers` ("via IFoo.Bar
dispatch" group), `impact` (implementors list + via_dispatch), `context` ("Callers via interface
dispatch"), `call-path` / callgraph hops through implements edges, `hover`, `wiring` (Spring4D DI
only), MCP `get_wiring`. LSP `textDocument/implementation`
(`src\lsp\DRagLint.LSP.Feature.ImplDecl.pas`) uses the own body + same-named methods of the
owner type's DESCENDANTS, not `dispatch_edges` -- so on an interface method it is expected to
miss the implementors (to confirm in T6).

Conclusion: Q1 (minus delegation), Q2 (minus resolution clauses), Q3, Q4 and Q5 (minus
delegation) are answerable today with query-time joins only. Two answers need the extractor.

## 3. What needs the sibling lane `call` (or a new extractor item)

| Gap | Owner of the fix | Report behaviour until it lands |
|---|---|---|
| G1 resolution clause: edge must target `RunJob`; the phantom `TRenamedJob.Execute` must not look like a real method | `call` (METHRES-DISPATCH) | row shows `RunJob?` with confidence `clause-unresolved`, read from the clause line's `read` ref; never silently the phantom |
| G2 `implements` delegation: store `property P: IJob read F implements IJob[, IOther]` as a fact (new `dispatch_edges` kind `delegates` base=interface, impl=property; or a `symbol_facts` row) | NOT in `call`'s scope today -> decision D2 | Q1/Q5 list the class (it lists IJob in `type_ancestors`) with how=`delegated?` and members `NOT ANSWERED (delegation not indexed)` |
| G3 RB5-IFACE resolver rest (untyped / undecidable receivers) | `call` (RB5-IFACE, owner Q1) | sites the resolver could not type stay out of Q3; the report prints the `ambiguous-calls` count for the member as "N unattributed site(s)" |

Both G1 and G2 change emitted rows -> extractor bump (the x129 integrator bumps once).
This lane does not touch the extractor.

## 4. CLI verb

```
drag-lint implementors --target <IJob | IJob.Execute | IJob.Name | TJob | TJob.RunJob>
        --db <project.sqlite> [--db <library.sqlite> | --library-db <lib>]
        [--uses] [--max-sites N] [--include-library] [--depth N]
        [--format text|json|dot|mermaid] [--json] [--output <file>]
```

* `--target`: bare or qualified; dispatched on the resolved kind (interface, interface
  method/property, class, class method). An ambiguous bare name is exit 2 listing candidates
  (same as `context`). Interface PROPERTY targets answer Q3 through `member_accesses` plus the
  getter/setter's call edges.
* `--uses`: add Q3/Q4 sites (default off for interface/class targets, on for member targets).
* `--max-sites N` (default 50 per member; the total is always printed).
* `--include-library`: also list implementors found in the library DB (default: the project
  DB's classes only; library interfaces such as IInterface are otherwise answered as
  "declared in library, N project implementors").
* `--depth N`: for Q1, how many derived-interface levels to follow (default unlimited).
* Exit: 0 answered (also "0 implementors"), 1 target not found, 2 usage / ambiguous, 3 stale.

`--json` (schema `implementors/1`):

```json
{"schema":"implementors/1","target":{"qname":"IfFix.IJob.Execute","kind":"interface-method",
  "file":"...","line":8},
 "implementors":[
  {"class":"IfFix.TRenamedJob","how":"lists","method":"IfFix.TRenamedJob.RunJob",
   "declared_in":"IfFix.TRenamedJob","via_clause":true,"file":"...","line":27,"body_line":55,
   "confidence":"certain"},
  {"class":"IfFix.TInheritedJob","how":"inherited","via_interface":"IfFix.IJobEx",
   "method":"IfFix.TBaseJob.Execute","declared_in":"IfFix.TBaseJob","confidence":"certain"}],
 "unanswered":[{"class":"IfFix.TDelegatingJob","how":"delegated","reason":"delegation-not-indexed"}],
 "sites":[{"mode":"call","file":"...","line":65,"col":8,"enclosing":"IfFix.UseIt"}],
 "sites_total":1,"unattributed_sites":0,
 "notes":[]}
```

For a class target the top level is `interfaces[]` of `{interface,how,members[{member,method,
declared_in,confidence}]}`. Arrays are always present (empty, never omitted) so a consumer
cannot mistake absence for "none" (feedback: guards incapable of failing).

## 5. Text and chart output

Text (default):

```
IfFix.IJob.Execute  (interface method, IfFix.pas:8)
  implementors (3 classes):
    TPlainJob      TPlainJob.Execute             IfFix.pas:20  body :54
    TRenamedJob    TRenamedJob.RunJob  (= clause) IfFix.pas:27  body :55
    TInheritedJob  TBaseJob.Execute  (inherited; via IJobEx) IfFix.pas:33
  not answered (1): TDelegatingJob -- delegated by property Inner (delegation not indexed)
  sites (1, attributed to IJob.Execute per RB-5):
    IfFix.pas:65:8  call  in UseIt
```

Charts: a new `ask` question **`implementors`** (the 27th id) in `src\charts`, a
`DRagLint.Charts.Q.Implementors.pas` modelled on `Q.Hierarchy` / `Q.WhoCalls`: one engine
(shared with the verb, section 7), DOT render through the existing `Charts.Dot` / `Render`
path. Layout: interface (and its derived interfaces) on the left, implementing classes in the
middle (edge label = how), answering methods on the right; with `--uses`, call/use sites as a
fourth column grouped by unit. `graph`'s `--format dot|mermaid` is reused for the verb's
`--format dot|mermaid` so the CLI chart and the `ask` chart are the same picture.

## 6. IDE / LSP surfaces

* Delphi plugin: one more Reports entry ("Interface implementors...") that runs
  `drag-lint ask implementors --target <symbol at caret> --plain --open` through the existing
  `DragLint.Plugin.Reports` runner (no new process plumbing). Full menu path goes in the
  featuregen entry.
* LSP: (a) `textDocument/implementation` on an interface method/interface answers from the
  same engine (implementors' answering methods / classes) instead of the descendant walk;
  (b) a code lens "N implementors" above interface methods next to the existing "N callers"
  lens. (b) is optional -- decision D5.
* MCP: a `get_implementors` tool wrapping the JSON (the `get_wiring` description already
  claims "who implements IFoo", but it only knows Spring4D registrations).

## 7. Implementation shape (for the plan, not this lane)

* `src\query\DRagLint.Query.Implementors.pas`: `TImplementorsQuery` over `ISymbolStore` --
  pure SQL joins on `symbols`, `type_ancestors`, `dispatch_edges`, `call_edges`,
  `member_accesses`, `refs`. Inherited-implementation attribution (which LISTING class) is
  computed here, per class, by walking the class chain to the edge's impl -- no schema change.
* Verb in `DRagLint.CLI.pas` + `HelpText`, README, AI-USAGE, featuregen entry (docs-sync).
* Charts question uses the query unit; LSP ImplDecl calls it through `ILspServerContext`.
* No extractor change in this work; G1/G2 rows appear when the x129 bump lands, and the
  report's interim labels (section 3) disappear by themselves.

## 8. Test plan

Fixture `tests\fixtures\ifrpt\IfFix.pas` (the measured scratch fixture, plus: a generic
interface `IStore<T>`, two same-arity overloads to provoke `ambiguous`, an interface property
with a setter written once, a class implementing two interfaces with a same-named method).
Guard `tests\autotest\run_implementors_guard.ps1` (indexes a scratch copy, never a real DB):

| T | Assertion | Positive control |
|---|---|---|
| T1 | Q1 on IJob lists TPlainJob, TRenamedJob, TInheritedJob (how=inherited, via IJobEx), TDelegatingJob | a class that does NOT list IJob is absent; count is exact, not ">0" |
| T2 | Q2 on IJob.Execute: TInheritedJob's answer is TBaseJob.Execute with declared_in TBaseJob | TBaseJob itself is NOT listed as an implementor (it does not list IJob) |
| T3 | Q2 resolution clause: interim = `clause-unresolved` + RunJob; after x129 = `RunJob` certain, and the phantom never appears | the phantom `TRenamedJob.Execute` string is asserted absent from both outputs |
| T4 | Q3 sites: IJob.Execute 1 call; IJob.Name 1 read; setter write counted as write | an implementor target without `--uses` has 0 sites; with `--uses` the site carries `via` |
| T5 | Q5 on TInheritedJob: IJobEx.Cancel -> TInheritedJob.Cancel, IJob.* -> TBaseJob.* | TDelegatingJob members read `NOT ANSWERED` (interim) |
| T6 | LSP implementation on IJob.Execute returns the three answering methods | RED on the base build (expected: descendant walk misses them) |
| T7 | `--json` shape: every array key present on an empty answer; `implementors/1` | parse with `ConvertFrom-Json`, field names read from the RAW bytes first |
| T8 | src\cli DB: IParser.Parse -> 3 implementors (TDFMParser, TDelphi13Parser, TFirebirdSqlParser), matching `impact` | `impact`'s implementors list is the oracle; a mismatch fails |

Plus run_docs_sync_guard, run_feature_registry_guard, encoding guard, lint on new units.
RED first: T1-T8 against the base build (the verb does not exist -> exit 2).

## 9. Owner decisions

D1 Surface: new top-level verb `implementors` + `ask implementors` sharing one engine
   (recommended), or only `query implementors` / only the `ask` chart?
D2 `implements` delegation (G2): add a delegation fact to the x129 extractor batch now (one
   bump, already paid for by `call`), or ship 1.40 with the interim "delegation not indexed"
   label and defer?
D3 Resolution-clause phantom (G1): should the phantom `TRenamedJob.Execute` symbol be dropped,
   or kept as a declaration-only row marked `resolution clause` (so hover/outline still find
   the clause line)? This is the `call` lane's choice but the report depends on it.
D4 Library scope: default to project-declared implementors only, interfaces from the library
   (IInterface, IUnknown, COM) answered as counts unless `--include-library`?
D5 IDE scope for 1.40: plugin Reports entry + LSP `textDocument/implementation` fix only, or
   also the "N implementors" code lens and the MCP tool?

## 10. Owner rulings (2026-11-01)

* D1: verb `implementors` + `ask implementors` chart, one engine.
* D2: delegation goes into the x129 batch; lane `call` indexes it. This lane labels it until then.
* D3: the fake resolution-clause method is dropped (lane `call`). This lane labels the clause until then.
* D4: project implementors by default; library implementors as counts unless `--include-library`.
* D5: ALL surfaces: plugin Reports entry, LSP go-to-implementation reads the implements rows (T6),
  an "N implementors" code lens, an MCP `get_implementors` tool, and the `get_wiring` description fixed.
