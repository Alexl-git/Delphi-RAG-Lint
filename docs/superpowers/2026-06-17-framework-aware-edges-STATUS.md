# Framework-Aware Edges - Autonomous Session STATUS (2026-06-17)

Branch: `feat/framework-aware-edges` (off `feat/index-manifest`). All work below is
committed and VERIFIED; the branch is in a clean, non-broken state. Remaining tasks
are well-specified with exact anchors so resuming is mechanical.

## Delivered + verified this session

| Commit  | What | Verification |
|---------|------|--------------|
| c22301d | spec + CodeGraph backlog (#2/#3) | n/a (docs) |
| ed0453b | spec: flag deferred DI via di-unresolved | n/a (docs) |
| 7734496 | phased implementation plan | n/a (docs) |
| 80e5a3e | **Task 1**: schema v8 `di_bindings` table | builds clean; fresh index runs clean (DDL applies via `for Stmt in SCHEMA_DDL`) |
| c86fd82 | **Task 6 core**: `DRagLint.Parser.SpringDI` pure recognizer | **13/13** behavior cases pass standalone (see below) |

Recognizer cases proven: register singleton / per-thread / transient, nested
generics (`IDataService<ImcCAUSFAIL>`), legacy `.As<>`, `Resolve`, unresolved-flag
(`RegisterInstance`, bare `RegisterType`), and none.

## Build / test recipe (use to resume)

- **Build console exe** (via mcpbuild `shell_run`, `use_delphi_env=true`):
  ```
  call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild "C:\Projects\Delphi-RAG-lint\src\cli\drag-lint.dproj" /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal /clp:ErrorsOnly
  ```
  Output exe: `src\cli\Win32\Debug\drag-lint.exe` (currently **v0.46.0-alpha**).
- **Standalone pure-unit compile** (no dproj): `dcc32 -Q -NSSystem;Winapi;System.Win <file>.dpr`
  (the `-NS` namespaces are REQUIRED or RTL units like `SysUtils` aren't found).
- **No `sqlite3.exe` / managed SQLite** on this box: verify DB contents through
  drag-lint queries, not external SQL.

## Key findings (de-risking)

- **Real ORM3 idiom**: `GlobalContainer.RegisterType<TImpl>.Implements<IIntf>[.AsSingleton|.AsSingletonPerThread]`
  (legacy `.As<IIntf>`); resolution `GlobalContainer.Resolve<IIntf>` (**no parens**).
  Registration is centralized: `CLIENT\uClientContainer.pas`,
  `SERVER\uContainerConfig.pas`, `PACKAGE\uInterfacesRegistration.pas`.
- **Parser gap (measured on `tests/fixtures/di_edges.pas`)**: method names
  `RegisterType`/`Implements`/`Resolve` = **0** refs (dropped); but the type args
  ARE captured as `type_use` (`TmcSTATIONS`=1, `ImcSTATIONS`=3). Nested-generic
  OUTER name `IDataService` = 0 (must be handled). `GlobalContainer`=5, `AsSingleton`=1.
  => The edge ENDPOINTS already reach the tree; only the method-name + association
  is missing. This is the Task 5 work.
- **Parser node vocabulary** (from `DRagLint.Parser.Delphi13.pas`): `exprCall`
  (field `entity` = identifier | `exprDot`.rhs), `exprDot`(lhs,rhs),
  `genericDot`(lhs,operator,rhs), `declTypeArgs`, `typeref`, and paren-less calls
  handled at `:839` (`statement`). The ONE shape still to confirm is the no-parens
  generic member access (`X.Resolve<T>`): discover by a temporary
  `WriteLn(ANode.NodeType)` in `Walk` (default recurse, ~`:924`) then index
  `di_edges.pas`. (A standalone s-expr dumper via `TreeSitter.pas` +
  `tree_sitter_delphi13` compiled but crashed at runtime - DLL dep resolution;
  not worth chasing, the in-parser print is simpler.)
- **`run_smoke.ps1` pre-existing fragility**: the global `C:\Projects\.drag-lint.json`
  "loaded defaults from ..." banner breaks a `Write-Check -Ok` (array vs bool).
  NOT caused by this work. Write `run_wiring.ps1` to strip the
  `(loaded defaults ...)` line before parsing.

## Next steps (ordered; resume here)

- **P-A. Wire recognizer into parser (Task 5 + 6 remainder).**
  In `DRagLint.Parser.Delphi13.pas`: capture the method-access chain
  (per link: method-name identifier + `declTypeArgs` inner text), emit each method
  name as a `'call'` ref (closes the gap; `find-callers Resolve` then works), then
  call `SpringDI.ClassifyDiChain`. Add `TWalkState.DiBindings: TList<TDiBinding>`
  and emit `di_bindings` / `EmitRef('di-resolve'|'di-unresolved', ...)`. Add a
  `DiBindings` field to the parse result and flush at `DRagLint.Core.Indexer.pas:269`
  (next to `UpsertReference`) via a new `Store.InsertDiBinding`.
- **P-B. Storage (Task 2).** `ISymbolStore` at `DRagLint.Core.Interfaces.pas:51`
  (`UpsertReference` :62). SQLite impl: prepared-stmt pattern at
  `DRagLint.Storage.SQLite.pas:363` (`FQInsertRef`); per-file delete next to
  `FQDeleteFileRefs` :368; `UpsertReference` body :678. Add `InsertDiBinding`,
  `FindImplementationsOf`, `FindResolveSitesOf`, `FindDiUnresolved`,
  `FindEventHandlers`, and `DELETE FROM di_bindings WHERE file_id` in the reindex path.
- **P-C. CLI `wiring` (Task 3).** `DoWiring` modeled on `DoImpact`
  (`DRagLint.CLI.pas:3622`); dispatch ~`:7969`; flags ~`:336`; help ~`:176`.
  DFM branch reuses existing `event-binding` refs (`DRagLint.Parser.DFM.pas:152`).
  NOTE: event-binding ref stores handler name + location but `symbol_id=0` and
  carries NO component/event-property name - minimal v1 = list handlers resolved
  to the form's methods.
- **P-D. MCP + context (Task 7).** `get_wiring` in `DRagLint.MCP.Server.pas`
  (descriptors :179, handlers :629); enrich `get_context_bundle`.
- **P-E. Smoke + bench (Tasks 8/9).** `tests/autotest/run_wiring.ps1` (banner-robust),
  wired into the suite; `bench-wiring` modeled on `DoBenchContext` (`CLI.pas:4206`).

## Caveats / non-blocking notes

- `docs/reviews/` appeared untracked during the session (not created by this work).
- The active `feat/index-manifest` WIP (rebuilt BPLs/DLLs + `drag-lint.json`) is
  uncommitted and was left untouched throughout.
