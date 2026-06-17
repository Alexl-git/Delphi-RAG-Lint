# Framework-Aware Edges (Spring4D DI + DFM wiring) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Spring4D DI wiring (`I -> T` + lifetime, resolve-sites) and DFM event wiring (`component.event -> handler`) first-class, queryable edges in drag-lint, exposed via a `wiring` CLI command, a `get_wiring` MCP tool, and context-bundle enrichment.

**Architecture:** New edge data lives in a `di_bindings` table (schema v8) plus two new `refs.kind` values (`di-resolve`, `di-unresolved`); DFM handlers reuse the existing `event-binding` refs. A new `DRagLint.Parser.SpringDI` unit recognizes the fluent registration/resolution idiom from the tree-sitter chain; the parser captures generic member-call names + type args (closing a real gap). The `wiring` query surface is built FIRST so the parser work is observable through it.

**Tech Stack:** Delphi 13 (Object Pascal), tree-sitter (delphi13 + dfm grammars), SQLite via FireDAC, PowerShell smoke tests (no DUnitX in this repo). Build via the mcpbuild MCP (`mcp__mcpbuild__delphi_build`) or the documented msbuild incantation.

**Spec:** `docs/superpowers/specs/2026-06-17-framework-aware-edges-design.md`. This plan REORDERS the spec's phasing (DFM/observation surface first) for testability; the scope is unchanged.

**Encoding:** all `.pas` edits are strict 7-bit ASCII, CRLF. DocInsight `///` spec-comments are REQUIRED on every new public type/method (CDD); never strip them.

---

## Key real-world facts (from ORM3 + code inspection)

Registration idiom (centralized in `uClientContainer`, `SERVER\uContainerConfig`, `uInterfacesRegistration`):
```pascal
GlobalContainer.RegisterType<TmcSTATIONS>.Implements<ImcSTATIONS>.AsSingleton;          // singleton
GlobalContainer.RegisterType<TDataService_CAUSFAIL_SERVER>
  .Implements<IDataService<ImcCAUSFAIL>>.AsSingletonPerThread;                          // nested generics
GlobalContainer.RegisterType<TmcCAUSFAIL>.Implements<ImcCAUSFAIL>;                       // transient
GlobalContainer.RegisterType<TSetupDefaults>.As<ISetupDefaults>.AsSingleton;            // legacy .As<>
```
Resolution idiom (scattered): `GlobalContainer.Resolve<ImcSTATIONS>` (note: NO parens -> parsed as a generic member access, NOT a `call` node; that is why `find-callers Resolve` = 0 today).

Hook points (verified):
- `TWalkState.EmitRef(const AKind, ANameText: string; const ARangeNode: TTSNode)` -- `DRagLint.Parser.Delphi13.pas:136`.
- `EmitCallReference` -- `:218`; only fires for `call` (invocation) nodes whose `entity` is `identifier` or `exprDot`.
- `EmitTypeUseReference` -- `:189`; shows how generic/qualified type nodes are shaped (`typeref`, `genericDot` with `rhs` field, `declTypeArgs`).
- Schema: `DRagLint.Storage.Schema.pas` -- `SCHEMA_VERSION = 7` (line 6), `SCHEMA_DDL: array[0..39] of string` (line 10). Tables are `CREATE TABLE IF NOT EXISTS` so older DBs auto-upgrade.
- Storage prepared statements: `DRagLint.Storage.SQLite.pas:331+` (`FQInsertRef` :363, `FQDeleteFileRefs` :368, `FQFindByName` :369).
- CLI dispatch: `DRagLint.CLI.pas:7969+`; query subcommands `:2097+`; `DoImpact` pattern `:3622`; `DoBenchContext` `:4206`.
- MCP tools: `DRagLint.MCP.Server.pas:179+` (descriptors), `:629+` (handlers).
- DFM event bindings already emitted: `DRagLint.Parser.DFM.pas:152` (`EmitRef('event-binding', HandlerName, ValueNode)`).

---

## File Structure

- Create: `src/parser/DRagLint.Parser.SpringDI.pas` -- Spring4D idiom recognizer (pure function over a captured method-chain; no tree-sitter dependency beyond the node text already extracted).
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` -- capture generic member-call names + type args; feed SpringDI; emit `di-resolve`/`di-unresolved` refs + `TDiBinding`s.
- Modify: `src/storage/DRagLint.Storage.Schema.pas` -- schema v8: `di_bindings` table + indexes.
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` -- insert/delete/query for `di_bindings`; wire into per-file reindex delete.
- Modify: the `ISymbolStore` interface unit + the indexer flush site -- add `InsertDiBinding` and flush `TWalkState.DiBindings` (mirror how `References` -> `UpsertReference` flows; confirm by reading).
- Modify: `src/cli/DRagLint.CLI.pas` -- `DoWiring` command + dispatch + flags + help.
- Modify: `src/mcp/DRagLint.MCP.Server.pas` -- `get_wiring` tool; enrich `get_context_bundle`.
- Modify: context-bundle builder (the unit `DoContext`/`get_context_bundle` calls) -- wiring enrichment.
- Create: `tests/fixtures/di_edges.pas`, `tests/fixtures/dfm_wiring.pas`, `tests/fixtures/dfm_wiring.dfm`.
- Create: `tests/autotest/run_wiring.ps1`; wire it into the existing smoke runner.

## Shared types (defined once, used across tasks)

Add to the unit that declares `TReference` (same unit as `TSymbol`/`TReference`; confirm by reading `DRagLint.Parser.Delphi13.pas` interface or the core types unit it uses):

```pascal
/// <summary>One resolved Spring4D DI registration: interface IName implemented by
/// ImplName with the given lifetime. Endpoints are stored verbatim, including
/// nested generics (e.g. 'IDataService<ImcCAUSFAIL>').</summary>
/// <remarks>Emitted by the Delphi parser; persisted into the di_bindings table.</remarks>
TDiBinding = record
  InterfaceName: string;
  ImplName:      string;
  Lifetime:      string;   // 'singleton' | 'singleton-per-thread' | 'transient'
  StartLine, StartCol, EndLine, EndCol: Integer;
end;
```

`refs.kind` string constants used here: `'di-resolve'`, `'di-unresolved'`, and existing `'call'`, `'event-binding'`.

---

## Task 0: Worktree, build baseline, green smoke

**Files:** none modified (environment setup).

- [ ] **Step 1: Create an isolated worktree (active WIP on feat/index-manifest)**

REQUIRED SUB-SKILL: superpowers:using-git-worktrees. Create a worktree off `feat/framework-aware-edges`. Work there for all subsequent tasks.

- [ ] **Step 2: Establish the exact build command**

Build the drag-lint console exe. Preferred: mcpbuild MCP tool `mcp__mcpbuild__delphi_build` against the drag-lint console `.dproj` (locate it: `Glob src/**/*.dproj` or repo root `*.dproj`). Fallback msbuild:
```
cmd.exe /c "call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 /v:normal <draglint-console>.dproj"
```
Record the built exe path as `$EXE` for later steps. Expected: build succeeds in < 30 s.

- [ ] **Step 3: Run the existing smoke suite to confirm a green baseline**

Run: `pwsh tests/autotest/run_smoke.ps1`
Expected: existing smoke passes (no regressions before we start). If it fails pre-change, STOP and report.

- [ ] **Step 4: Commit nothing (setup only).** Proceed.

---

## Task 1: Schema v8 -- di_bindings table

**Files:**
- Modify: `src/storage/DRagLint.Storage.Schema.pas:6` (version) and the `SCHEMA_DDL` array (line 10, bound `array[0..39]`).

- [ ] **Step 1: Write the failing test (schema presence)**

Create `tests/autotest/run_wiring.ps1` with this first assertion:
```powershell
$ErrorActionPreference = 'Stop'
$EXE = $env:DRAGLINT_EXE   # set by Task 0 Step 2
$tmp = Join-Path $env:TEMP ("wiring_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$db = Join-Path $tmp 'w.sqlite'
& $EXE index tests/fixtures/di_edges.pas --db $db | Out-Null
# Schema check: di_bindings table must exist (query via the exe's own surface in later tasks;
# for now assert the table is created by indexing without error and schema_meta version = 8).
$ver = & $EXE query find --db $db 2>$null; # any command opens+migrates the DB
if (-not (Test-Path $db)) { throw 'FAIL: db not created' }
Write-Host 'OK: db created/migrated'
```
(The fixture `tests/fixtures/di_edges.pas` is created in Task 4; for now create a 1-line stub `unit di_edges; interface implementation end.` so indexing succeeds.)

- [ ] **Step 2: Run it to verify it fails**

Run: `pwsh tests/autotest/run_wiring.ps1`
Expected: FAIL (fixture stub missing or table assertions in later steps fail). Create the stub fixture so this step's only failure is the absence of `di_bindings`, then continue.

- [ ] **Step 3: Add the di_bindings DDL + bump version**

In `DRagLint.Storage.Schema.pas`: change `SCHEMA_VERSION = 7;` to `SCHEMA_VERSION = 8;`. Change the array bound `array[0..39]` to the new count (current 40 entries + 3 new = `array[0..42]`). Append before the closing `)`:
```pascal
    ,
    // v8 (2026-06-17): Spring4D DI bindings. One row per resolved
    // RegisterType<TImpl>.Implements<IIntf> registration. interface_name and
    // impl_name are stored verbatim incl. nested generics. Per-file cascade
    // matches the symbols/refs reindex path.
    'CREATE TABLE IF NOT EXISTS di_bindings (' +
    '  id             INTEGER PRIMARY KEY,' +
    '  file_id        INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,' +
    '  interface_name TEXT NOT NULL,' +
    '  impl_name      TEXT NOT NULL,' +
    '  lifetime       TEXT NOT NULL,' +
    '  start_line     INTEGER NOT NULL,' +
    '  start_col      INTEGER NOT NULL,' +
    '  end_line       INTEGER NOT NULL,' +
    '  end_col        INTEGER NOT NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_di_interface ON di_bindings(interface_name)',
    'CREATE INDEX IF NOT EXISTS idx_di_impl      ON di_bindings(impl_name)'
```
(Count the actual existing entries when editing; set the array upper bound to existing+3. The trailing `,` joins to the previous element -- verify comma placement.)

- [ ] **Step 4: Build + run test to verify pass**

Build (`mcp__mcpbuild__delphi_build`), then `pwsh tests/autotest/run_wiring.ps1`.
Expected: PASS ('OK: db created/migrated'); no SQLite error on `CREATE TABLE`.

- [ ] **Step 5: Commit**

```
git add src/storage/DRagLint.Storage.Schema.pas tests/autotest/run_wiring.ps1 tests/fixtures/di_edges.pas
git commit -m "feat(schema): v8 di_bindings table for Spring4D DI edges"
```

---

## Task 2: Storage -- insert/delete/query di_bindings

**Files:**
- Modify: the `ISymbolStore` interface unit (add methods).
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (prepared queries `:331+`, per-file delete near `FQDeleteFileRefs` `:368`, implement methods).

- [ ] **Step 1: Add interface methods (with DocInsight)**

In `ISymbolStore` add:
```pascal
/// <summary>Persists one Spring4D DI binding row. Caller owns ABinding.</summary>
procedure InsertDiBinding(AFileId: Integer; const ABinding: TDiBinding);
/// <summary>Implementations registered for an interface name (verbatim match).</summary>
/// <returns>List of (impl_name, lifetime, file path, line). Empty if none.</returns>
function FindImplementationsOf(const AInterfaceName: string): TArray<TDiBindingRow>;
/// <summary>Resolve-site refs (kind='di-resolve') naming the interface.</summary>
function FindResolveSitesOf(const AInterfaceName: string): TArray<TRefRow>;
/// <summary>Unresolved DI registrations (kind='di-unresolved') grouped for coverage.</summary>
function FindDiUnresolved: TArray<TRefRow>;
```
Define `TDiBindingRow` / `TRefRow` records next to the existing row-record types in that unit (mirror the existing `TSymbolRow`/result record convention; confirm names by reading). Each carries the columns the CLI prints (names, lifetime, file path, line).

- [ ] **Step 2: Add the failing storage smoke (deferred to Task 5)**

Storage is observable only through the `wiring` CLI (Task 3). Mark Step: assertion added in Task 5. For now, add prepared statements + impl so the build stays green.

- [ ] **Step 3: Add prepared statements + per-file delete**

In `PrepareStatements` (after `FQInsertRef`, `:366`):
```pascal
FQInsertDiBinding := NewQuery(
  'INSERT INTO di_bindings(file_id, interface_name, impl_name, lifetime, ' +
  '  start_line, start_col, end_line, end_col) ' +
  'VALUES (:fid, :intf, :impl, :life, :sl, :sc, :el, :ec)');
FQDeleteFileDiBindings := NewQuery('DELETE FROM di_bindings WHERE file_id = :fid');
FQFindImplOf := NewQuery(
  'SELECT b.impl_name, b.lifetime, f.path, b.start_line ' +
  'FROM di_bindings b JOIN files f ON f.id = b.file_id ' +
  'WHERE b.interface_name = :intf ORDER BY f.path, b.start_line');
FQFindResolveOf := NewQuery(
  'SELECT r.name_text, f.path, r.start_line FROM refs r ' +
  'JOIN files f ON f.id = r.file_id ' +
  'WHERE r.kind = ''di-resolve'' AND r.name_text = :intf ORDER BY f.path, r.start_line');
FQFindDiUnresolved := NewQuery(
  'SELECT r.name_text, f.path, r.start_line FROM refs r ' +
  'JOIN files f ON f.id = r.file_id ' +
  'WHERE r.kind = ''di-unresolved'' ORDER BY r.name_text, f.path');
```
Declare the four `TFDQuery` fields alongside the existing `FQ*` fields. In the per-file reindex path, next to `FQDeleteFileRefs.ParamByName('fid')...ExecSQL`, add the same call for `FQDeleteFileDiBindings` (find the routine that uses `FQDeleteFileRefs`; mirror it exactly).

- [ ] **Step 4: Implement the four methods**

Mirror an existing `FindByName`-style method (open query, iterate `while not Eof`, build result array, `Close`). `InsertDiBinding` mirrors how `UpsertReference` sets params + `ExecSQL`. Set param `DataType`s up front if any can be NULL (none here -- all NOT NULL).

- [ ] **Step 5: Build to verify green**

Build (`mcp__mcpbuild__delphi_build`). Expected: compiles; no behavior change yet (no inserts emitted). Run `pwsh tests/autotest/run_smoke.ps1` -- existing smoke still green.

- [ ] **Step 6: Commit**

```
git add src/storage/DRagLint.Storage.SQLite.pas <ISymbolStore unit>
git commit -m "feat(storage): di_bindings insert/delete/query + reindex cascade"
```

---

## Task 3: `wiring` CLI command (the observation surface) + DFM wiring

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (new `DoWiring` near `DoImpact` `:3622`; dispatch `:7969+`; flag parse `:336+`; help `:176+`).

DFM `event-binding` refs already exist, so `wiring` for a form returns data immediately -- this is the first end-to-end slice.

- [ ] **Step 1: Write the failing test (DFM wiring)**

Append to `run_wiring.ps1`:
```powershell
& $EXE index tests/fixtures/dfm_wiring.pas tests/fixtures/dfm_wiring.dfm --db $db | Out-Null
$out = & $EXE wiring --qname TfrmWire --db $db --format json | Out-String
if ($out -notmatch '"handler"\s*:\s*"Button1Click"') { throw "FAIL: DFM handler edge missing: $out" }
Write-Host 'OK: DFM wiring edge present'
```
(Fixtures created in Task 4; create them now if executing Task 3 first.)

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh tests/autotest/run_wiring.ps1`
Expected: FAIL with "Unknown command 'wiring'" (command not wired yet).

- [ ] **Step 3: Implement DoWiring (DFM branch first)**

Add `function DoWiring(const AArgs: TArgs): Integer;` mirroring `DoImpact` (`:3622`): open store from `--db`, read `--qname`/`--format`. Branch on the qname's symbol kind:
- Form/component/method -> call a store query that returns `event-binding` refs whose owning component belongs to the form, each resolved to its handler method symbol (resolution = match handler `name_text` to a method symbol whose parent is the form class). Emit JSON objects `{ "component": ..., "event": ..., "handler": ... }` and a text table.
- Interface/class -> DI branch (Task 6 fills it; for now returns empty set cleanly).
Wire `'wiring'` into the dispatch chain at `:7969+`:
```pascal
else if Args.Command = 'wiring' then
  Result := DoWiring(Args)
```
Add `--qname`, `--format`, `--coverage` to the arg parser; add a usage line in `PrintUsage`.

- [ ] **Step 4: Build + run to verify pass**

Build; `pwsh tests/autotest/run_wiring.ps1`.
Expected: PASS ('OK: DFM wiring edge present').

- [ ] **Step 5: Commit**

```
git add src/cli/DRagLint.CLI.pas
git commit -m "feat(cli): wiring command + DFM event-binding edges (component.event -> handler)"
```

---

## Task 4: Test fixtures (DI + DFM)

**Files:**
- Create: `tests/fixtures/di_edges.pas`, `tests/fixtures/dfm_wiring.pas`, `tests/fixtures/dfm_wiring.dfm`.

- [ ] **Step 1: Write `tests/fixtures/di_edges.pas`** (real ORM3-shaped idioms, ASCII/CRLF)

```pascal
unit di_edges;

interface

type
  ImcSTATIONS = interface ['{00000000-0000-0000-0000-000000000001}']
    function ID: Integer;
  end;

  IDataService<T> = interface ['{00000000-0000-0000-0000-000000000002}']
    procedure Run;
  end;

  ImcCAUSFAIL = interface ['{00000000-0000-0000-0000-000000000003}']
  end;

  TmcSTATIONS = class(TInterfacedObject, ImcSTATIONS)
    function ID: Integer;
  end;

  TDataService_CAUSFAIL_SERVER = class(TInterfacedObject, IDataService<ImcCAUSFAIL>)
    procedure Run;
  end;

implementation

uses Spring.Container;

function TmcSTATIONS.ID: Integer; begin Result := 0; end;
procedure TDataService_CAUSFAIL_SERVER.Run; begin end;

procedure RegisterAll;
begin
  GlobalContainer.RegisterType<TmcSTATIONS>.Implements<ImcSTATIONS>.AsSingleton;
  GlobalContainer.RegisterType<TDataService_CAUSFAIL_SERVER>
    .Implements<IDataService<ImcCAUSFAIL>>.AsSingletonPerThread;
  GlobalContainer.RegisterInstance<ImcCAUSFAIL>(nil);  // deferred form -> di-unresolved
end;

procedure UseIt;
var S: ImcSTATIONS;
begin
  S := GlobalContainer.Resolve<ImcSTATIONS>;
  S.ID;
end;

end.
```

- [ ] **Step 2: Write `tests/fixtures/dfm_wiring.pas`**

```pascal
unit dfm_wiring;

interface

uses Vcl.Forms, Vcl.StdCtrls;

type
  TfrmWire = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TfrmWire.Button1Click(Sender: TObject);
begin
end;

end.
```

- [ ] **Step 3: Write `tests/fixtures/dfm_wiring.dfm`**

```
object frmWire: TfrmWire
  Caption = 'Wire'
  object Button1: TButton
    Caption = 'Go'
    OnClick = Button1Click
  end
end
```

- [ ] **Step 4: Verify fixtures index cleanly**

Run: `& $EXE index tests/fixtures/di_edges.pas tests/fixtures/dfm_wiring.pas tests/fixtures/dfm_wiring.dfm --db $env:TEMP\fix.sqlite`
Expected: no parse/index errors.

- [ ] **Step 5: Commit**

```
git add tests/fixtures/di_edges.pas tests/fixtures/dfm_wiring.pas tests/fixtures/dfm_wiring.dfm
git commit -m "test(fixtures): DI + DFM wiring fixtures (ORM3-shaped idioms)"
```

---

## Task 5: Parser prerequisite -- capture generic member-call names + type args

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (walk; near `EmitCallReference` `:218`).

- [ ] **Step 1: Write the failing test (the gap: Resolve becomes findable)**

Append to `run_wiring.ps1`:
```powershell
$callers = & $EXE query find-callers --name Resolve --db $db 2>&1 | Out-String
if ($callers -match '0 caller') { throw "FAIL: generic member-call 'Resolve' still not captured" }
Write-Host 'OK: generic member-call names captured'
```

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh tests/autotest/run_wiring.ps1`
Expected: FAIL ('0 caller(s)' for Resolve), because `Resolve<T>` (no parens) is not a `call` node.

- [ ] **Step 3: Capture generic member access**

In the `Walk` dispatch, handle the generic member-access node shape used by `recv.Method<TypeArgs>` (inspect grammar: likely `genericDot` / `exprDot` carrying a `declTypeArgs` child; reuse the `rhs`-field logic from `EmitTypeUseReference` `:202-210`). Add `EmitGenericMemberCallReference(ANode, AState)` that:
- extracts the method-name identifier (the `rhs`),
- emits `AState.EmitRef('call', MethodName, RhsNode)` (closes the gap; `find-callers Resolve` works),
- extracts the `declTypeArgs` child's verbatim text (the full `<...>`, nesting preserved) and stashes `(MethodName, TypeArgsText, RhsNode)` onto a per-chain list on `AState` for Task 6.
Call it from `Walk` for the generic-member node type(s). Do NOT double-emit for ordinary `call` nodes already handled by `EmitCallReference`.

- [ ] **Step 4: Build + run to verify pass**

Build; `pwsh tests/autotest/run_wiring.ps1`.
Expected: PASS ('OK: generic member-call names captured'); re-run `run_smoke.ps1` -- still green (new refs are additive).

- [ ] **Step 5: Commit**

```
git add src/parser/DRagLint.Parser.Delphi13.pas tests/autotest/run_wiring.ps1
git commit -m "feat(parser): capture generic member-call names + type args (fixes find-callers Resolve)"
```

---

## Task 6: SpringDI recognizer -> di_bindings + di-resolve + di-unresolved

**Files:**
- Create: `src/parser/DRagLint.Parser.SpringDI.pas`.
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (consume the per-chain list from Task 5; emit facts). Add `TWalkState.DiBindings: TList<TDiBinding>` + flush at the indexer (mirror `References`).

- [ ] **Step 1: Write the failing test (DI edges)**

Append to `run_wiring.ps1`:
```powershell
$impl = & $EXE wiring --qname ImcSTATIONS --db $db --format json | Out-String
if ($impl -notmatch '"impl"\s*:\s*"TmcSTATIONS"')        { throw "FAIL: I->T binding missing: $impl" }
if ($impl -notmatch '"lifetime"\s*:\s*"singleton"')      { throw "FAIL: lifetime missing: $impl" }
if ($impl -notmatch '"resolved_at"')                      { throw "FAIL: resolve-site missing: $impl" }
$nested = & $EXE wiring --qname 'IDataService<ImcCAUSFAIL>' --db $db --format json | Out-String
if ($nested -notmatch 'TDataService_CAUSFAIL_SERVER')     { throw "FAIL: nested-generic binding missing" }
if ($nested -notmatch 'singleton-per-thread')             { throw "FAIL: per-thread lifetime missing" }
$cov = & $EXE wiring --coverage --db $db --format json | Out-String
if ($cov -notmatch 'RegisterInstance')                    { throw "FAIL: di-unresolved coverage missing" }
Write-Host 'OK: DI edges (binding+lifetime+resolve+nested+coverage)'
```

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh tests/autotest/run_wiring.ps1`
Expected: FAIL (`wiring ImcSTATIONS` returns empty -- no bindings emitted yet).

- [ ] **Step 3: Write SpringDI recognizer (pure, DocInsight'd)**

`DRagLint.Parser.SpringDI.pas` exposes:
```pascal
/// <summary>Classifies a captured method-chain (one (method,typeArgs) tuple per
/// link, in source order) as a Spring4D DI registration, resolution, or an
/// unresolved DI call. Pure: no tree-sitter or DB dependency.</summary>
/// <param name="AChain">Method links in order, e.g. [('RegisterType','<TFoo>'),
///   ('Implements','<IFoo>'), ('AsSingleton','')].</param>
/// <param name="ABinding">Filled when Outcome=dioRegister.</param>
/// <param name="AResolveIntf">Filled (interface name) when Outcome=dioResolve.</param>
/// <param name="AUnresolvedMethod">Filled when Outcome=dioUnresolved.</param>
/// <returns>The classification outcome.</returns>
function ClassifyDiChain(const AChain: TArray<TDiChainLink>;
  out ABinding: TDiBinding; out AResolveIntf: string;
  out AUnresolvedMethod: string): TDiOutcome;
```
Rules (strip the surrounding `<>` from typeArgs; keep inner text verbatim):
- chain contains `RegisterType<TImpl>` AND (`Implements<IIntf>` OR `As<IIntf>`): `dioRegister`; lifetime = `AsSingleton`->'singleton', `AsSingletonPerThread`->'singleton-per-thread', else 'transient'. Span = first link's node range.
- chain head is `Resolve<IIntf>` or `TryResolve<IIntf>`: `dioResolve`, AResolveIntf = inner.
- chain head is a DI registration method we don't resolve (`RegisterInstance`, `RegisterFactory`, `DelegateTo`, `Register` without `Implements`, `Named`): `dioUnresolved`, AUnresolvedMethod = method name.
- otherwise `dioNone`.

- [ ] **Step 4: Wire it into the parser**

In Delphi13's chain handler (from Task 5), once a full member-chain is collected, call `ClassifyDiChain`:
- `dioRegister` -> `AState.DiBindings.Add(ABinding)`.
- `dioResolve` -> `AState.EmitRef('di-resolve', AResolveIntf, HeadNode)`.
- `dioUnresolved` -> `AState.EmitRef('di-unresolved', AUnresolvedMethod, HeadNode)`.
Add `DiBindings: TList<TDiBinding>` to `TWalkState` (init/free with the other lists). At the indexer flush (where `References` are written via `UpsertReference`), iterate `DiBindings` and call `Store.InsertDiBinding(FileId, B)`.

- [ ] **Step 5: Fill DoWiring DI branch + --coverage**

In `DoWiring` (Task 3), implement the interface/class branch using `FindImplementationsOf` + `FindResolveSitesOf`, and `--coverage` using `FindDiUnresolved`. JSON keys: `impl`, `lifetime`, `resolved_at` (array of {path,line}); coverage: `{method, path, line}`.

- [ ] **Step 6: Build + run to verify pass**

Build; `pwsh tests/autotest/run_wiring.ps1`.
Expected: PASS ('OK: DI edges ...'). Re-run `run_smoke.ps1` -- green.

- [ ] **Step 7: Commit**

```
git add src/parser/DRagLint.Parser.SpringDI.pas src/parser/DRagLint.Parser.Delphi13.pas src/cli/DRagLint.CLI.pas <ISymbolStore unit> src/storage/DRagLint.Storage.SQLite.pas tests/autotest/run_wiring.ps1
git commit -m "feat(parser): Spring4D DI edges (register I->T+lifetime, resolve, di-unresolved coverage)"
```

---

## Task 7: MCP `get_wiring` tool + context-bundle enrichment

**Files:**
- Modify: `src/mcp/DRagLint.MCP.Server.pas` (descriptor `:179+`, handler `:629+`).
- Modify: the context-bundle builder used by `get_context_bundle` / `DoContext`.

- [ ] **Step 1: Write the failing test (MCP tool listed + returns data)**

Append to `run_wiring.ps1` an MCP stdio round-trip (mirror how `run_smoke.ps1` drives `drag-lint serve`): send `tools/list`, assert `get_wiring` present; send `tools/call get_wiring {qname:'ImcSTATIONS'}`, assert `TmcSTATIONS` in the result.

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL ('get_wiring' not in tools list).

- [ ] **Step 3: Register + handle get_wiring**

Add a `ToolDescriptor('get_wiring', ...)` (mirror `get_impact` `:239`) with input schema `{ qname: string, kind?: string, format?: string }`. In `HandleToolsCall`, add `else if ToolName = 'get_wiring'` that calls the same store queries as `DoWiring` and returns JSON (mirror `find_callers` handler `:682-708`).

- [ ] **Step 4: Enrich get_context_bundle**

In the context-bundle builder, when the target symbol is an interface, class, or form, append a "Wiring" section: implementations+lifetime, resolve-site count, and (for forms) event handlers -- reusing the Task 2/6 store queries. Add a `run_wiring.ps1` assertion: a context bundle for `ImcSTATIONS` contains `TmcSTATIONS`.

- [ ] **Step 5: Build + run to verify pass**

Build; `pwsh tests/autotest/run_wiring.ps1` and `run_smoke.ps1`.
Expected: both PASS.

- [ ] **Step 6: Commit**

```
git add src/mcp/DRagLint.MCP.Server.pas <context-bundle unit> tests/autotest/run_wiring.ps1
git commit -m "feat(mcp): get_wiring tool + wiring in context bundles"
```

---

## Task 8: Wire run_wiring.ps1 into the smoke suite

**Files:**
- Modify: `tests/autotest/run_smoke.ps1` (or the suite aggregator) to invoke `run_wiring.ps1`.

- [ ] **Step 1:** Add a call to `run_wiring.ps1` in the smoke aggregator, failing the suite on its non-zero exit. Mirror how `run_formsmap.ps1` is invoked (if it is) or add a direct `& pwsh run_wiring.ps1; if ($LASTEXITCODE) { throw }`.
- [ ] **Step 2:** Run `pwsh tests/autotest/run_smoke.ps1`. Expected: full suite green incl. wiring.
- [ ] **Step 3: Commit** `test(smoke): include run_wiring.ps1 in the suite`.

---

## Task 9 (P3): Agent-task benchmark gate (#4)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` -- new `DoBenchWiring` near `DoBenchContext` `:4206`; dispatch `bench-wiring`.

- [ ] **Step 1: Write the failing test (benchmark emits the two metrics)**

Append a `run_wiring.ps1` assertion: `& $EXE bench-wiring --db $db --format json` returns JSON containing `tool_calls_saved` and `tokens_saved` numeric fields > 0 on the fixture task set.

- [ ] **Step 2: Run to verify it fails** (`Unknown command 'bench-wiring'`).

- [ ] **Step 3: Implement DoBenchWiring**

Mirror `DoBenchContext` (`:4206-4304`). Fixed task set (3 tasks): "implementations of ImcSTATIONS", "resolve-sites of ImcSTATIONS", "handlers of TfrmWire". For each, compute the BASELINE (tool-calls + token estimate an agent needs WITHOUT wiring: grep across files for `Implements<ImcSTATIONS>` / `Resolve<ImcSTATIONS>` / DFM scan -- estimate via the existing `chars/3.7` formula over the candidate files) vs WITH wiring (1 `wiring` call returning the curated bundle; tokens = bundle estimate, tool_calls = 1). Report per-task and totals `tool_calls_saved`, `tokens_saved`, and a reduction ratio. Wire `bench-wiring` into dispatch.

- [ ] **Step 4: Build + run to verify pass**

Build; `pwsh tests/autotest/run_wiring.ps1`.
Expected: PASS; both metrics > 0 (the feature's value gate).

- [ ] **Step 5: Commit** `feat(bench): bench-wiring agent-task gate (tool-calls + tokens saved)`.

---

## Task 10: Backlog confirmation (#2/#3) + finish

- [ ] **Step 1:** Confirm `docs/BACKLOG-codegraph-parity.md` exists (created during design) capturing future ideas #2 (one-command install/auto-wire MCP) and #3 (MCP initialize self-guidance). If missing in this worktree, re-create from the spec's section 12.
- [ ] **Step 2:** Update `docs/ROADMAP.md` / `CHANGELOG` with the `wiring` command, `get_wiring`, `di_bindings` (schema v8), `bench-wiring`. Commit `docs: wiring feature in roadmap/changelog`.
- [ ] **Step 3:** Run the full smoke suite once more (`run_smoke.ps1`). Expected: green. Then finish via superpowers:finishing-a-development-branch.

---

## Self-Review (completed by plan author)

**1. Spec coverage:** sec.4 components -> Tasks 1-7,9; sec.5 data model (di_bindings + di-resolve + di-unresolved) -> Tasks 1,2,6; sec.6 parser prerequisite -> Task 5; sec.7 DI rules incl. deferred-flagging -> Task 6 (ClassifyDiChain dioUnresolved) + Task 6 Step 1 coverage assert; sec.8 DFM -> Tasks 3,4; sec.9 CLI/MCP/context -> Tasks 3,7; sec.10 testing+benchmark -> Tasks 4,8,9; sec.11 phasing -> reordered (DFM/surface first) but all phases present; sec.12 out-of-scope #2/#3 -> Task 10. No gaps.

**2. Placeholder scan:** no TBD/"handle edge cases". Two integration points say "confirm by reading" (ISymbolStore unit name; indexer flush site) -- these are real-location lookups, not missing logic; the code to add is given. Acceptable.

**3. Type consistency:** `TDiBinding` fields (InterfaceName/ImplName/Lifetime/span) identical in Shared-types, Task 2 (InsertDiBinding), Task 6 (DiBindings list). `refs.kind` strings `'di-resolve'`/`'di-unresolved'` consistent across Tasks 2,6. CLI command `wiring`, MCP tool `get_wiring`, bench `bench-wiring`, recognizer `ClassifyDiChain`/`TDiOutcome` (`dioRegister`/`dioResolve`/`dioUnresolved`/`dioNone`) consistent across Tasks 3,6,7,9. JSON keys `impl`/`lifetime`/`resolved_at`/`handler` consistent across Task 3/6 asserts and DoWiring.
