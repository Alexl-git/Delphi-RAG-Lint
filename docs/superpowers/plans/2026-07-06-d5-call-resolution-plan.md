# D5 Call-Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve each Delphi call site to the specific target symbol (receiver-type resolution), store the result with a confidence in a new `call_edges` table, and switch AutoDocument Called-from (+ new query verbs) to precise resolved callers instead of name-matches -- fixing the common-name false-positive bug (`CLI.Run` listing callers of other `Run`s).

**Architecture:** A new whole-DB post-index pass `ResolveCallTargets` (mirroring `ResolveAncestry`) types the receiver at each call site and writes a `call_edges` row (target + confidence). The parser is extended to emit all local vars + params as typed symbols so receivers can be typed. Consumers read `call_edges`; AutoDocument switches first. A `purge-locals` verb sheds the local/param bulk (esp. on library DBs) while keeping the call graph precise. Schema bumps v13 -> v14 (forces reparse).

**Tech Stack:** Delphi 13 (RAD Studio 37), Object Pascal, tree-sitter (delphi13 grammar), SQLite (FireDAC), PowerShell test harnesses, the delphi-build skill.

**Spec:** `docs/superpowers/specs/2026-07-06-d5-call-resolution-design.md` (approved).

## Global Constraints

- **Encoding:** all `.pas` source + fixtures are strict 7-bit ASCII, CRLF, no BOM. Never Unicode/LF. **Never a literal `{` or `}` inside a Pascal `{ }` comment** (breaks the comment + compile; use `//`). The self-lint error-count in the PostToolUse hook is a canary; the delphi-build result is the authoritative gate.
- **Build (authoritative gate):** run `build\build_draglint_win64.bat` via PowerShell `Start-Process cmd.exe -ArgumentList "/c","<bat>" -RedirectStandardOutput <log> -NoNewWindow -Wait -PassThru`; require ExitCode 0, no `[dcc64 Error]`/`E2xxx`/`Fatal` in the log, and the `OK: staged` line. It stages `src\cli\Win64\Debug\drag-lint.exe` -> `third_party\dll-win64\drag-lint.exe`. Do NOT use the MCP build tool; do NOT `cmd /c build.bat` from the Bash tool.
- **Test the STAGED exe** `third_party\dll-win64\drag-lint.exe` (the raw `Win64\Debug` exe dies `0xC0000135` -- no tree-sitter DLLs beside it). Run PowerShell harnesses (pwsh 7) from a NEUTRAL CWD (`C:\TEMP`). Fixtures: ASCII/CRLF, unit name = filename.
- **Guardrail (green after every task):** lint 154/154 (`tests\lint\run_lint_tests.ps1`), store 16/16 (`tests\lint-store\run_store_tests.ps1`), autodoc 7/7 (`tests\autodoc\run_doc_*.ps1`), autofix 9/9 (`tests\autofix\*.ps1`). Plus the new `tests\callresolve\*.ps1` from Task 6 onward.
- **Schema:** `SCHEMA_VERSION` is at `src/storage/DRagLint.Storage.Schema.pas:6`. `SCHEMA_DDL` is a fixed-size `array[0..N] of string` (currently `[0..51]`) -- adding a table entry REQUIRES growing the array bound or the array literal is malformed (compile error). `TSymbolKind` (Model.pas:6) and `KindText: array[TSymbolKind] of string` (Model.pas:328) MUST stay in lockstep -- a new enum value needs a matching `KindText` entry at the same ordinal or every `ToText`/`FromText` shifts.
- **Cut order if trimming (from spec Risks):** (1) call-path/callgraph (Task 11), (2) Calls-facts upgrade (Task 10), (3) receiver kinds cast/with/return (fold into Task 5's optional steps). The core (Tasks 1-9, 12-14) delivers the bug fix + find-callers/callees/ambiguous.

**Key existing locations (verified 2026-07-06):**
- `SCHEMA_VERSION = 13`, `SCHEMA_DDL: array[0..51] of string` -- `src/storage/DRagLint.Storage.Schema.pas:6/22`.
- `TSymbolKind` enum + `KindText` array + `FromText` -- `src/core/DRagLint.Core.Model.pas:6/328/355`.
- `TSymbol` (Model.pas:40): `Id, FileId, ParentId, Kind, Name, QualifiedName, Signature, Modifiers, Section, Heritage, IsVirtual, StartLine..EndCol, ImplStartLine, ImplEndLine`. `TReference` (Model.pas:84): `Id, SymbolId, FileId, Kind, NameText, StartLine..EndCol, ContextText, EnclosingSymbolId`.
- Parser routine walk + body-span stamping -- `src/parser/DRagLint.Parser.Delphi13.pas` (routine emit ~695-747; `AState.Emit(kind, name, qname, parentIdx, node, signature, visibility, heritage)`; `TypeTextOf(node, source)` ~576; field/property emit at 918/938 as the type-carrying template).
- Insert queries `FQInsertSymbol` / `FQInsertRef` -- `src/storage/DRagLint.Storage.SQLite.pas:617/621`. `UpsertSymbol` :98, `UpsertReference`.
- Resolution-pass template `ResolveAncestry` -- `src/storage/DRagLint.Storage.SQLite.pas:2645` (pull-all -> resolve in memory using name-candidates + `unit_uses` file-scope -> batch-write `type_ancestors`). `ResolveUnitUseTargets` :2527. `ResolveTypeCategory(typeName, fileId)` :140 (depth-capped alias-chasing). `type_ancestors` table :556.
- Pass call sites in the index pipeline: `Store.ResolveUnitUseTargets; Store.ResolveAncestry;` at `src/cli/DRagLint.CLI.pas:929-930, 1361-1362, 1405-1406` -- `ResolveCallTargets` goes right after each.
- `ISymbolStore.FindReferencesTo(ASymbolId): TArray<TReference>` -- Interfaces.pas:76 (the resolved-caller primitive). `FindCallersByName` :77 (name-based, the noisy one).
- Verb dispatch chain -- `src/cli/DRagLint.CLI.pas:9074+` (`else if Args.Command = 'X' then Result:= DoX(Args)`). Verb template `DoDumpRefs` (:8854) / `DoFindUnit`.
- AutoDocument Called-from -- `src/doc/DRagLint.Doc.Facts.pas:244` (callers) + `:312` (used-in); render in `src/doc/DRagLint.Doc.Regions.pas` (`RenderFactsBlock`, `JoinRefs`).
- Library reindex -- `drag-lint index --scan-libraries-win` -> `library-Win32.sqlite`/`-Win64.sqlite`.

---

## Task 1: Schema v14 -- `call_edges` table + new symbol kinds (compile-only foundation)

**Files:**
- Modify: `src/storage/DRagLint.Storage.Schema.pas` (SCHEMA_VERSION 13->14; add `call_edges` DDL + indexes; grow the array bound)
- Modify: `src/core/DRagLint.Core.Model.pas` (add `skLocalVar`, `skParam` to `TSymbolKind` + matching `KindText` entries)

**Interfaces:**
- Produces: schema v14 with an (empty) `call_edges` table; `skLocalVar`/`skParam` kinds usable by Tasks 2-5. `KindText['local_var'|'param']` round-trips via `FromText`/`ToText`.

- [ ] **Step 1: Add the new symbol kinds**

In `src/core/DRagLint.Core.Model.pas`, in the `TSymbolKind` enum (line 6-9), append `skLocalVar, skParam` BEFORE the final SQL/section kinds is risky (shifts ordinals). SAFEST: append at the very END of the enum so no existing ordinal shifts:

```pascal
  TSymbolKind = (
    skUnit, skProgram, skPackage, skClass, skInterface, skRecord, skEnum, skEnumValue, skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skField, skVarDecl, skConstDecl, skTypeAlias, skForm, skComponent,
    skSqlTable, skSqlColumn, skSqlIndex, skSqlTrigger, skSqlGenerator, skSqlProcedure, skSqlView, skSqlException, skSqlDomain,
    skSqlConstraint, skInitialization, skFinalization,
    skLocalVar, skParam);   // v14 (D5): typed local vars + params
```

(Match the ACTUAL enum member list in the file -- copy it verbatim and append the two. Do NOT reorder.)

Then extend `KindText` (line 328) by appending the two matching strings AT THE SAME ORDINAL POSITIONS (end of the array literal, before the close paren):

```pascal
  KindText: array[TSymbolKind] of string = (
    'unit', 'program', 'package', 'class', 'interface', 'record', 'enum', 'enum_value', 'procedure', 'function', 'method', 'constructor', 'destructor', 'property', 'field', 'var',
    'const', 'type', 'form', 'component', 'sql_table', 'sql_column', 'sql_index', 'sql_trigger', 'sql_generator', 'sql_procedure', 'sql_view', 'sql_exception', 'sql_domain',
    'sql_constraint', 'initialization', 'finalization',
    'local_var', 'param');   // v14 (D5)
```

(The array is `array[TSymbolKind] of string` -- it MUST have exactly one entry per enum value in ORDER. Two new enum values => two new strings at the end.)

- [ ] **Step 2: Bump the schema version**

In `src/storage/DRagLint.Storage.Schema.pas:6`:

```pascal
  SCHEMA_VERSION = 14;
```

- [ ] **Step 3: Add the `call_edges` DDL + grow the array bound**

`SCHEMA_DDL` is `array[0..51] of string`. Change the bound to `array[0..53]` (two new entries: the table + we fold the two indexes into `CREATE`-adjacent statements, or add them as their own entries -- count precisely). Add these entries at the END of the array literal (before the closing `)`), each a separate string element:

```pascal
    'CREATE TABLE IF NOT EXISTS call_edges (' +
    '  ref_id                  INTEGER NOT NULL PRIMARY KEY REFERENCES refs(id) ON DELETE CASCADE,' +
    '  target_symbol_id        INTEGER NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,' +
    '  confidence              TEXT    NOT NULL,' +
    '  receiver_type_symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL' +
    ')',
    'CREATE INDEX IF NOT EXISTS idx_call_edges_target ON call_edges(target_symbol_id)',
    'CREATE INDEX IF NOT EXISTS idx_call_edges_ref    ON call_edges(ref_id)'
```

Count them: table + 2 indexes = 3 new entries -> the array bound grows from `[0..51]` to `[0..54]`. VERIFY the exact current highest index and adjust the bound so `high - low + 1 = element count`. A mismatch is a compile error (E2064-ish). Note: `call_edges` uses only base SQLite (no FTS5), so it can live before or after `SCHEMA_DDL_FTS5_FIRST`; place it at the end (after the last non-FTS entry is simplest -- but if the last entries are FTS5, put it just before them and bump indices accordingly, keeping `SCHEMA_DDL_FTS5_FIRST` pointing at the first FTS entry). Re-check `SCHEMA_DDL_FTS5_FIRST` (Schema.pas:10) is still correct after insertion.

- [ ] **Step 4: Build**

Build via delphi-build (`build\build_draglint_win64.bat`). Expected: ExitCode 0, `OK: staged`, no `[dcc64 Error]`. A bound mismatch shows as a compile error on the `SCHEMA_DDL` line -- fix the `[0..N]` bound to match the element count.

- [ ] **Step 5: Verify the table + version on a fresh index**

From `C:\TEMP`: index a tiny scratch and confirm schema v14 + call_edges exists:
```
third_party\dll-win64\drag-lint.exe index <a small dir> --db C:\TEMP\d5t1.sqlite
```
Then confirm no crash and the version bump took (any verb that prints schema, or just that indexing succeeds). `call_edges` is empty (populated in Task 6). Guardrail: lint 154/154, store 16/16, autodoc 7/7, autofix 9/9 (a schema bump must not break existing suites -- if store tests assert a version number, update that assertion).

- [ ] **Step 6: Commit**

```bash
git add src/storage/DRagLint.Storage.Schema.pas src/core/DRagLint.Core.Model.pas
git commit -m "feat(d5): schema v14 -- call_edges table + skLocalVar/skParam kinds"
```

---

## Task 2: Emit typed params as symbols (parser)

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (routine walk -- emit each formal parameter as an `skParam` symbol carrying its type)
- Create: `tests/callresolve/fixtures/params.pas`, `tests/callresolve/run_emit_params.ps1`

**Interfaces:**
- Consumes: `skParam` (Task 1); `AState.Emit`, `TypeTextOf` (existing parser helpers).
- Produces: for each routine, one `skParam` symbol per formal parameter, `ParentId` = the routine symbol, `Signature` = the param's declared type text, `Name` = the param name.

- [ ] **Step 1: Write the failing test + fixture**

`tests/callresolve/fixtures/params.pas` (ASCII/CRLF, unit name `params`):
```pascal
unit params;

interface

type
  TThing = class
    procedure Handle(const AItem: TThing; ACount: Integer);
  end;

implementation

procedure TThing.Handle(const AItem: TThing; ACount: Integer);
begin
end;

end.
```

`tests/callresolve/run_emit_params.ps1` -- index the fixture to a scratch db, then assert (via `query --name AItem` / `--name ACount`, or a `dump` verb) that BOTH params are emitted as symbols: `AItem` with kind `param` and type text containing `TThing`; `ACount` kind `param` type `Integer`, each parented to `params.TThing.Handle`. Model the harness shell on `tests/autodoc/run_doc_generate.ps1` (Check helper, Push-Location C:\TEMP, staged exe, exit 0/1). Use `drag-lint query --name AItem --db <scratch> --json` and assert the JSON has a symbol with kind=param.

- [ ] **Step 2: Run it to confirm it fails**

From C:\TEMP, run the harness against the CURRENT staged exe. Expected: FAIL -- `query --name AItem` returns 0 matches (params not emitted yet).

- [ ] **Step 3: Implement param emission**

In `src/parser/DRagLint.Parser.Delphi13.pas`, in the routine-walk (the `TryWalkRoutine`/routine emit path around 695-747, right after the routine symbol is emitted and its index known), iterate the routine header's `formal_parameters` node. For each parameter identifier, call:
```pascal
AState.Emit(skParam, ParamName, RoutineQName + '.' + ParamName, RoutineIdx, ParamNode, TypeTextOf(ParamTypeNode, AState.Source));
```
Handle grouped params (`A, B: TType` -> two symbols sharing the type) and the `const`/`var`/`out` prefixes (strip to the bare type; reuse the same tree-sitter node kinds the parser already recognizes for params -- inspect the grammar node names via a `tree-sitter parse` on the fixture if unsure, or reuse how `TypeTextOf` is applied to fields at line 918). If a param has no explicit type (rare -- e.g. untyped `var`), emit with empty Signature (still a symbol, type unknown).

- [ ] **Step 4: Run the test -> PASS.** Build first (delphi-build, ExitCode 0), then run `run_emit_params.ps1` from C:\TEMP -> PASS (both params present, correct kinds/types/parent).

- [ ] **Step 5: Guardrail + commit**

Run lint/store/autodoc/autofix suites -> all green (param symbols are additive; if any suite asserts a symbol COUNT it may need updating -- adjust the assertion, not the feature).
```bash
git add src/parser/DRagLint.Parser.Delphi13.pas tests/callresolve/fixtures/params.pas tests/callresolve/run_emit_params.ps1
git commit -m "feat(d5): parser emits typed params as skParam symbols"
```

---

## Task 3: Emit typed local vars as symbols (parser)

**Files:**
- Modify: `src/parser/DRagLint.Parser.Delphi13.pas` (routine walk -- emit each local `var`-section entry as `skLocalVar`)
- Create: `tests/callresolve/fixtures/locals.pas`, `tests/callresolve/run_emit_locals.ps1`

**Interfaces:**
- Consumes: `skLocalVar` (Task 1); `AState.Emit`, `TypeTextOf`.
- Produces: for each routine, one `skLocalVar` symbol per local var declaration, `ParentId` = the routine symbol, `Signature` = type text, `Name` = var name.

- [ ] **Step 1: Write the failing test + fixture**

`tests/callresolve/fixtures/locals.pas` (unit `locals`):
```pascal
unit locals;

interface

type
  TWorker = class
    procedure Go;
  end;

implementation

procedure TWorker.Go;
var
  L: TWorker;
  N: Integer;
begin
  L := Self;
  N := 0;
end;

end.
```

`tests/callresolve/run_emit_locals.ps1` -- assert `L` (kind `local_var`, type `TWorker`) and `N` (kind `local_var`, type `Integer`) are emitted, parented to `locals.TWorker.Go`. Same harness shape as Task 2.

- [ ] **Step 2: Run -> FAIL** (locals not emitted; `query --name L` = 0).

- [ ] **Step 3: Implement local-var emission**

In the routine walk, after emitting the routine + its params (Task 2), walk the routine body's local `var` section(s) (the `declaration_part`/`var_section` node inside the routine block). For each `var` entry:
```pascal
AState.Emit(skLocalVar, VarName, RoutineQName + '.' + VarName, RoutineIdx, VarNode, TypeTextOf(VarTypeNode, AState.Source));
```
Handle grouped `A, B: TType`. Handle inline vars (`var X: T` inside the statement block, Delphi 10.3+) if the grammar exposes them -- else defer (note it). Only emit locals of the routine being walked (guard against nested-proc locals leaking, consistent with the parser's existing nested-proc handling ~88-90).

- [ ] **Step 4: Build -> run `run_emit_locals.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + commit**

Suites green.
```bash
git add src/parser/DRagLint.Parser.Delphi13.pas tests/callresolve/fixtures/locals.pas tests/callresolve/run_emit_locals.ps1
git commit -m "feat(d5): parser emits typed local vars as skLocalVar symbols"
```

---

## Task 4: `call_edges` store write + read primitives

**Files:**
- Modify: `src/core/DRagLint.Core.Interfaces.pas` (add store methods)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (implement them + the insert query)
- Modify: `src/core/DRagLint.Core.Model.pas` (add a `TCallEdge` record + `TResolvedCaller` record)

**Interfaces:**
- Produces (used by Tasks 5-11):
  - `TCallEdge = record RefId, TargetSymbolId, ReceiverTypeSymbolId: Int64; Confidence: string; end;`
    -- stored `Confidence` is ALWAYS `'certain'` or `'ambiguous'` (the two `call_edges.confidence`
    values written by the resolver).
  - `TResolvedCaller = record EnclosingSymbolId: Int64; EnclosingQName, Location, Confidence: string; end;`
    -- a RENDERING value; `Confidence` is `'certain'` | `'ambiguous'` | `'unverified'` (the last
    for the no-`call_edges`-row `?` bucket from `FindUnresolvedNameCallers`). Renderer: `'certain'`
    -> plain; `'ambiguous'`/`'unverified'` -> append ` ?`.
  - `procedure UpsertCallEdge(const AToken: TFileTxToken; const AEdge: TCallEdge);` (INSERT OR REPLACE)
  - `procedure ClearCallEdges;` (whole-table wipe, for the rebuild-each-run pass)
  - `function FindResolvedCallers(ATargetSymbolId: Int64): TArray<TResolvedCaller>;` (the Called-from query: join call_edges->refs->symbols WHERE target = X)
  - `function GetCallEdgesFromSymbol(AEnclosingSymbolId: Int64): TArray<TCallEdge>;` (find-callees)
  - `function CountCallEdges: Int64;`

- [ ] **Step 1: Add the records**

In `src/core/DRagLint.Core.Model.pas` (near `TReference`), add `TCallEdge` and `TResolvedCaller` exactly as in Interfaces above.

- [ ] **Step 2: Declare the store methods**

In `src/core/DRagLint.Core.Interfaces.pas` `ISymbolStore`, add the six signatures above.

- [ ] **Step 3: Write the failing test**

`tests/callresolve/run_call_edges_store.ps1` -- since there's no Pascal test host, this task's behavioural lock is deferred to Task 6's resolver tests; FOR THIS TASK the gate is a clean build + a manual smoke: after implementing, index a fixture, manually INSERT a call_edges row via... (no direct SQL verb). SIMPLER: fold the store-method verification into Task 6 (the resolver populates call_edges; FindResolvedCallers reads it). So Task 4 is a COMPILE + wiring task -- no standalone .ps1. Note this in the commit.

- [ ] **Step 4: Implement the store methods**

In `src/storage/DRagLint.Storage.SQLite.pas`:
- Add `FQInsertCallEdge := NewQuery('INSERT OR REPLACE INTO call_edges(ref_id, target_symbol_id, confidence, receiver_type_symbol_id) VALUES (:rid, :tid, :conf, :rtid)');` (prepared in the same init block as `FQInsertRef` ~617, freed alongside it ~274).
- `UpsertCallEdge` binds + ExecSQL (NULL the receiver param when 0).
- `ClearCallEdges`: `FConn.ExecSQL('DELETE FROM call_edges')`.
- `FindResolvedCallers(X)`:
  ```sql
  SELECT r.enclosing_symbol_id, s.qualified_name AS encl_qname, f.path AS file_path, r.start_line, ce.confidence
  FROM call_edges ce
  JOIN refs r ON r.id = ce.ref_id
  LEFT JOIN symbols s ON s.id = r.enclosing_symbol_id
  JOIN files f ON f.id = r.file_id
  WHERE ce.target_symbol_id = :x
  ORDER BY ce.confidence DESC, s.qualified_name
  ```
  Map each row to `TResolvedCaller` (EnclosingQName may be '' when enclosing is 0 -> fall back like Doc.Facts does; Location = `ExtractFileName(file_path)`).
- `GetCallEdgesFromSymbol(X)`: `SELECT ce.* FROM call_edges ce JOIN refs r ON r.id=ce.ref_id WHERE r.enclosing_symbol_id = :x`.
- `CountCallEdges`: `SELECT COUNT(*) FROM call_edges`.

- [ ] **Step 5: Build -> ExitCode 0.** Guardrail suites green (no behaviour change yet; call_edges still empty).

- [ ] **Step 6: Commit**

```bash
git add src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas src/core/DRagLint.Core.Model.pas
git commit -m "feat(d5): call_edges store write/read primitives (UpsertCallEdge, FindResolvedCallers, ...)"
```

---

## Task 5: Receiver typing engine (the resolver core)

**Files:**
- Create: `src/index/DRagLint.Index.CallResolver.pas` (the receiver-typing + method-lookup logic, pure over the store)
- Modify: `src/cli/drag-lint.dproj` (DCCReference) + a CLI `uses` entry

**Interfaces:**
- Consumes: `ISymbolStore` (symbols/refs/type_ancestors reads), `skLocalVar`/`skParam` symbols (Tasks 2-3), `ResolveTypeCategory`/type resolution helpers, `TypeTextOf`-produced Signature text.
- Produces: `TCallResolver.ResolveOne(AStore, ACallRef): TCallEdge` returning `{TargetSymbolId, ReceiverTypeSymbolId, Confidence}` (TargetSymbolId=0 => NO edge, i.e. the `?`/no-row case). Confidence in `'certain'|'ambiguous'`.

- [ ] **Step 1: Create the unit skeleton + DCCReference**

`src/index/DRagLint.Index.CallResolver.pas` with `TCallResolver` class, `class function ResolveOne(const AStore: ISymbolStore; const ACallRef: TReference): TCallEdge;` returning a default (Target=0) stub. Add the DCCReference to `src/cli/drag-lint.dproj` (mirror how `..\doc\DRagLint.Doc.Facts.pas` was added -- `<DCCReference Include="..\index\DRagLint.Index.CallResolver.pas"/>` + the `..\index` search path if not present) and a CLI `uses` entry. Build -> links.

- [ ] **Step 2: Write the resolver test fixture (the bug-repro + each receiver kind)**

`tests/callresolve/fixtures/receivers.pas` (unit `receivers`) with, in ONE unit, distinct receiver kinds calling same-named methods on different types, so the resolver's correctness is checkable end-to-end via Task 7's `document`/verbs. Include: (a) two classes `TAlpha`/`TBeta` each with `procedure Run;`; (b) a caller class with a field `FAlpha: TAlpha`, a method with a typed local `B: TBeta`, a param `AAlpha: TAlpha`, and `Self`-dispatch; each invoking `.Run`. The behavioural assertions live in Task 7 (`document --qname receivers.TAlpha.Run` lists ONLY the TAlpha callers). FOR THIS TASK: build gate + the resolver is exercised in Task 6.

- [ ] **Step 3: Implement receiver typing (the 8 kinds)**

In `TCallResolver.ResolveOne`, given a call ref (name + `enclosing_symbol_id` + position):
1. **Bare / Self.M** -> enclosing routine's `ParentId` = the owning class symbol. `inherited M` -> the class's first `type_ancestors` parent.
2. **Field `FBar.M`** -> find an `skField` symbol whose `ParentId` = the enclosing class and `Name` = `FBar`; parse its `Signature` type text -> resolve that type name to a class/interface/record symbol (via a name+file-scope lookup mirroring `ResolveAncestry`'s `NameToCands`+`FileScope`).
3. **Property `Prop.M`** -> same as field, over `skProperty`.
4. **Typed local `L.M`** -> find an `skLocalVar` whose `ParentId` = the enclosing routine + `Name` = `L`; resolve its type.
5. **Param `AFoo.M`** -> same over `skParam`.
6. **Cast `(X as TBar).M` / `TBar(X).M`** -> the cast target type `TBar` directly (parse from the ref's surrounding source text; bounded). *(OPTIONAL -- cut item 3; if cutting, leave unresolved.)*
7. **`with TBar-expr do M`** -> the active `with` receiver type over the ref's line range. *(OPTIONAL -- cut item 3.)*
8. **Function-return `GetFoo.M`** -> resolve `GetFoo` (a routine symbol) and parse its return type from `Signature`. *(OPTIONAL -- cut item 3.)*

To know WHICH kind a call site is (`X.M` vs bare `M` vs `(cast).M`), the resolver needs the receiver token(s) before the `.M`. Refs today store `NameText` = `M` + position. Read the source line(s) at the ref's position (bounded, via `GetFilePath` + read) to extract the receiver expression left of `.M`. Keep this a small, well-tested text helper (`ExtractReceiverExpr(sourceLine, refCol): string`).

**Method lookup on the resolved type + confidence:** once the receiver type symbol is known, walk its own methods + `type_ancestors` chain for a method named `M`:
- exactly one -> `Confidence := 'certain'`, `TargetSymbolId := that`.
- >1 (overloads / interface multi-impl) -> `'ambiguous'`, Target = best-guess (first).
- receiver type UNKNOWN (kind not handled, type unresolvable, depth cap) -> return Target=0 (NO edge -> `?` bucket).
- method not found on the chain -> Target=0 (`?`).

- [ ] **Step 4: Build -> ExitCode 0.** (Behavioural verification is Task 6's harness.)

- [ ] **Step 5: Commit**

```bash
git add src/index/DRagLint.Index.CallResolver.pas src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas tests/callresolve/fixtures/receivers.pas
git commit -m "feat(d5): TCallResolver -- receiver typing (8 kinds) + method-chain lookup + confidence"
```

---

## Task 6: `ResolveCallTargets` pass + wire into the index pipeline

**Files:**
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (add `ResolveCallTargets` -- iterate call refs, call `TCallResolver.ResolveOne`, batch-write `call_edges`)
- Modify: `src/core/DRagLint.Core.Interfaces.pas` (declare `ResolveCallTargets`)
- Modify: `src/cli/DRagLint.CLI.pas` (call it after `ResolveAncestry` at the 3 sites: :930, :1362, :1406)
- Create: `tests/callresolve/run_resolve_targets.ps1`

**Interfaces:**
- Consumes: `TCallResolver.ResolveOne`, `ClearCallEdges`, `UpsertCallEdge`, `CountCallEdges`.
- Produces: a populated `call_edges` table after every index; `procedure ResolveCallTargets;`

- [ ] **Step 1: Write the failing test**

`tests/callresolve/run_resolve_targets.ps1` -- index `fixtures/receivers.pas`, then assert `call_edges` is populated: the `FAlpha.Run` site resolves `certain` to `TAlpha.Run`; the `B.Run` local resolves `certain` to `TBeta.Run`; a Self.Run resolves to the caller's own Run. Verify via a diagnostic -- add a tiny `dump-call-edges <file> --db` verb OR assert through Task 7's `find-callers --resolved`. SIMPLEST for this task: assert `CountCallEdges > 0` via a diagnostic verb; the precise per-site assertions live in Task 7. (If no diagnostic verb yet, add a minimal `dump-call-edges --db` that prints `ref_id|target_qname|confidence` -- 10 lines, reused by later tests.)

- [ ] **Step 2: Run -> FAIL** (call_edges empty; the pass doesn't exist).

- [ ] **Step 3: Implement `ResolveCallTargets`**

Mirror `ResolveAncestry` (SQLite.pas:2645): `ClearCallEdges` first (rebuild-each-run), then `SELECT id, name_text, file_id, start_line, start_col, enclosing_symbol_id FROM refs WHERE <ref names a routine>` (filter to call-shaped refs -- refs whose `name_text` matches a known routine/method symbol name, or all refs and let ResolveOne return Target=0 for non-calls). For each, build a `TReference`, call `TCallResolver.ResolveOne(Self, ref)`; if `Target > 0` -> `UpsertCallEdge`. Batch in a transaction for speed (thousands of refs). Add `ResolveCallTargets` to `ISymbolStore`.

- [ ] **Step 4: Wire into the pipeline**

In `src/cli/DRagLint.CLI.pas`, after EACH `Store.ResolveAncestry;` (lines ~930, ~1362, ~1406) add:
```pascal
    Store.ResolveCallTargets; { v14 (D5): resolve call sites to target symbols }
```

- [ ] **Step 5: Build -> run `run_resolve_targets.ps1` -> PASS.** (call_edges populated; counts/targets correct.)

- [ ] **Step 6: Guardrail + commit**

Suites green. Reindex is now slower (locals/params + the pass) -- acceptable.
```bash
git add src/storage/DRagLint.Storage.SQLite.pas src/core/DRagLint.Core.Interfaces.pas src/cli/DRagLint.CLI.pas tests/callresolve/run_resolve_targets.ps1
git commit -m "feat(d5): ResolveCallTargets pass populates call_edges after ResolveAncestry"
```

---

## Task 7: AutoDocument Called-from switches to resolved callers (THE BUG FIX)

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (`:244` callers, `:312` used-in -> resolved)
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (render `?` on ambiguous/unverified)
- Modify: `src/core/DRagLint.Core.Model.pas` (`TDocFactRef` gains a `Confidence`/`Verified` field if needed for the `?`)
- Create: `tests/callresolve/run_calledfrom_resolved.ps1`

**Interfaces:**
- Consumes: `FindResolvedCallers(targetSymbolId)`, the resolved `call_edges`.
- Produces: Called-from that excludes confirmed-different callers, marks `<100%` with `?`.
- **New store method to ADD here** (declare in `ISymbolStore` + implement in SQLite.pas):
  `function FindUnresolvedNameCallers(const AName: string): TArray<TResolvedCaller>;` -- the
  `?` bucket: refs whose `name_text = AName` AND whose `id` has NO row in `call_edges` (receiver
  untypable). SQL: `SELECT ... FROM refs r LEFT JOIN symbols s ON s.id=r.enclosing_symbol_id JOIN
  files f ON f.id=r.file_id WHERE r.name_text=:n AND r.id NOT IN (SELECT ref_id FROM call_edges)`.
  Each returned `TResolvedCaller` has `Confidence := 'unverified'` so the renderer marks it `?`.

- [ ] **Step 1: Write the failing test (the bug repro)**

`tests/callresolve/run_calledfrom_resolved.ps1` -- index a fixture with `TAlpha.Run` + `TBeta.Run`, where routine `CallsAlpha` calls `FAlpha.Run` (FAlpha: TAlpha) and routine `CallsBeta` calls `FBeta.Run` (FBeta: TBeta). Run `document --qname <unit>.TAlpha.Run --apply`. Assert the Called-from line:
- INCLUDES `CallsAlpha` (real caller, plain, no `?`).
- EXCLUDES `CallsBeta` (resolved certain to TBeta.Run -- the bug fix).
- A deliberately-untypable name-match (e.g. a `Run` call on an unresolvable receiver) appears with `?`.
This is the regression lock for the whole milestone.

- [ ] **Step 2: Run -> FAIL** (current name-based Called-from includes CallsBeta).

- [ ] **Step 3: Implement the switch + 3-way render**

In `src/doc/DRagLint.Doc.Facts.pas:244`, replace `FindCallersByName(LastSeg(qname))` with a resolved query: get the target symbol id (`ASym.Id`), call `AStore.FindResolvedCallers(ASym.Id)` for the plain/`?`-ambiguous rows, AND separately compute the "name-match with no call_edges row" set for the untyped-`?` bucket (a store method `FindUnresolvedNameCallers(name, targetSymbolId)` -- name-matching refs whose ref_id has NO call_edges row; add it to the store). Build `TDocFactRef`s with a `Confidence` marker. Per spec Design 2:
- certain + target=ASym -> plain.
- ambiguous (either direction) OR no-row name-match -> `?`.
- certain + target!=ASym -> excluded (simply not returned by FindResolvedCallers(ASym.Id)).
In `src/doc/DRagLint.Doc.Regions.pas` `JoinRefs`/`RenderFactsBlock`, append ` ?` to a ref whose Confidence indicates unverified; sort plain before `?`.
Repeat for used-in (`:312`) analogously (type receivers).

- [ ] **Step 4: Build -> run `run_calledfrom_resolved.ps1` -> PASS** (CallsAlpha in, CallsBeta out, untypable `?`).

- [ ] **Step 5: Guardrail + commit**

All autodoc suites (7) still green -- the existing run_doc_* fixtures may CHANGE their Called-from output (now resolved); UPDATE those fixtures' expected strings to the resolved output (this is correct -- the tests now assert precise callers). Verify each change is a genuine precision improvement, not a regression.
```bash
git add src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas src/core/DRagLint.Core.Model.pas src/core/DRagLint.Core.Interfaces.pas src/storage/DRagLint.Storage.SQLite.pas tests/callresolve/run_calledfrom_resolved.ps1 tests/autodoc/
git commit -m "fix(d5): AutoDocument Called-from uses resolved callers (excludes confirmed-different, ? for unverified)"
```

---

## Task 8: `find-callers --resolved` verb

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (extend the find-callers path with `--resolved`)
- Create: `tests/callresolve/run_find_callers_resolved.ps1`

**Interfaces:**
- Consumes: `FindResolvedCallers`.
- Produces: `drag-lint query find-callers --name X --resolved [--db]` (or the existing find-callers verb + a `--resolved` flag) emitting resolved callers with confidence; without `--resolved`, unchanged name-based behavior.

- [ ] **Step 1: Failing test** -- `run_find_callers_resolved.ps1`: index the receivers fixture, run `find-callers --name Run --resolved --json`, assert the output groups by target (TAlpha.Run's callers vs TBeta.Run's), each tagged certain/ambiguous; WITHOUT `--resolved`, the old name-based list (unchanged) is returned.
- [ ] **Step 2: Run -> FAIL** (`--resolved` unknown arg).
- [ ] **Step 3: Implement** -- add `Resolved: Boolean` to `TArgs` (parse `--resolved`); in the find-callers handler, when set, resolve the name to symbol id(s) and call `FindResolvedCallers` per matching symbol; emit `{caller_qname, file, line, confidence, target_qname}` JSON + text. Without it, the existing path is untouched.
- [ ] **Step 4: Build -> PASS.**
- [ ] **Step 5: Commit** -- `git commit -m "feat(d5): find-callers --resolved (precise callers via call_edges)"`

---

## Task 9: `find-callees --qname X` + `ambiguous-calls` verbs

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (two new verbs + dispatch + usage)
- Create: `tests/callresolve/run_find_callees.ps1`, `tests/callresolve/run_ambiguous_calls.ps1`

**Interfaces:**
- Consumes: `GetCallEdgesFromSymbol`.
- Produces: `drag-lint find-callees --qname X [--db]`; `drag-lint ambiguous-calls [--qname X|--file F] [--db]`.
- **New store method to ADD here** (declare in `ISymbolStore` + implement in SQLite.pas):
  `function GetAmbiguousCalls(const AQName, AFilePath: string): TArray<TResolvedCaller>;` -- the
  resolver-coverage diagnostic: refs that name a known routine/method AND have either
  `confidence='ambiguous'` in `call_edges` OR no `call_edges` row, optionally scoped by the
  enclosing symbol's qname (`AQName<>''`) or file (`AFilePath<>''`). Reuse the `TResolvedCaller`
  shape (Confidence carries `'ambiguous'`/`'unverified'`).

- [ ] **Step 1: Failing tests** -- `run_find_callees.ps1`: `find-callees --qname receivers.TCaller.CallsAlpha --json` lists its resolved outgoing calls incl. `TAlpha.Run` (certain). `run_ambiguous_calls.ps1`: a fixture with an untypable receiver -> `ambiguous-calls --file F` lists that site; a fully-resolved fixture lists nothing.
- [ ] **Step 2: Run -> FAIL** (verbs unknown).
- [ ] **Step 3: Implement** -- `DoFindCallees` (resolve qname->symbol id, `GetCallEdgesFromSymbol`, join to target qnames, emit). `DoAmbiguousCalls` (a store query: refs whose name matches a routine but have confidence='ambiguous' OR no call_edges row, scoped by `--qname`/`--file`). Add both to the dispatch chain (after `document` at CLI.pas:9075) + usage lines near :288.
- [ ] **Step 4: Build -> both PASS.**
- [ ] **Step 5: Commit** -- `git commit -m "feat(d5): find-callees + ambiguous-calls verbs"`

---

## Task 10: AutoDocument Calls facts use resolved callees (in scope, CUTTABLE #2)

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (the T3 body-scan Calls block -> resolved callees + fallback)
- Create: `tests/callresolve/run_calls_resolved.ps1`

**Interfaces:**
- Consumes: `GetCallEdgesFromSymbol`.
- Produces: Calls facts sourced from resolved callees where available, body-scan fallback for unresolved.

- [ ] **Step 1: Failing test** -- a fixture where a method calls a clearly-resolvable method; assert the Calls line shows the RESOLVED qualified callee (not the bare `Ident(` name).
- [ ] **Step 2: Run -> FAIL.**
- [ ] **Step 3: Implement** -- in `Doc.Facts.Build`'s Calls block, first pull `GetCallEdgesFromSymbol(ASym.Id)` for resolved outgoing calls (qualified names); union with the existing body-scan for sites without a call_edge (so nothing is lost). Dedupe, cap (reuse DocDisplayCount).
- [ ] **Step 4: Build -> PASS.** Update any run_doc_* fixture whose Calls line changes to the resolved form.
- [ ] **Step 5: Commit** -- `git commit -m "feat(d5): AutoDocument Calls facts prefer resolved callees"`

**CUT NOTE:** if trimming, skip Task 10 entirely -- the T3 body-scan Calls stays as-is (it's already shipped + fine).

---

## Task 11: `call-path` + `callgraph` verbs (CUTTABLE #1 -- heaviest)

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (two verbs + dispatch + usage)
- Create: `tests/callresolve/run_call_path.ps1`, `tests/callresolve/run_callgraph.ps1`

**Interfaces:**
- Consumes: `FindResolvedCallers` (callers direction) + `GetCallEdgesFromSymbol` (callees direction).
- Produces: `call-path --from A --to B [--max-depth N]`; `callgraph --qname X [--direction callers|callees] [--depth N]`.

- [ ] **Step 1: Failing tests** -- `run_call_path.ps1`: a fixture chain A->B->C; `call-path --from <A> --to <C>` prints `A -> B -> C`; no path -> "no path". `run_callgraph.ps1`: `callgraph --qname <A> --direction callees --depth 2` prints the 2-deep tree.
- [ ] **Step 2: Run -> FAIL.**
- [ ] **Step 3: Implement** -- a recursive traversal over call_edges with a visited-set (cycle guard) + depth cap. `DoCallPath` (BFS from A over callees, stop at B, reconstruct path). `DoCallGraph` (DFS to depth N in the chosen direction, text tree + JSON). Dispatch + usage.
- [ ] **Step 4: Build -> both PASS** (incl. a cycle fixture -- assert no infinite loop).
- [ ] **Step 5: Commit** -- `git commit -m "feat(d5): call-path + callgraph traversal verbs"`

**CUT NOTE:** this is the first cut item. If skipped, the milestone still delivers the bug fix + find-callers/callees/ambiguous.

---

## Task 12: `purge-locals` verb

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (new verb + dispatch + usage)
- Modify: `src/storage/DRagLint.Storage.SQLite.pas` (a `PurgeLocals: Int64` store method + VACUUM)
- Modify: `src/core/DRagLint.Core.Interfaces.pas`
- Create: `tests/callresolve/run_purge_locals.ps1`

**Interfaces:**
- Consumes: the populated call_edges.
- Produces: `drag-lint purge-locals --db X [--json]` -> deletes skLocalVar/skParam symbols, VACUUM, reports rows removed + before/after size.

- [ ] **Step 1: Failing test** -- index the receivers fixture; assert local/param symbols present + call_edges built + `document`/`find-callers --resolved` return the resolved results. Run `purge-locals --db`. Assert: skLocalVar/skParam symbols GONE (`query --name L` = 0), `call_edges` UNCHANGED (CountCallEdges identical), and Called-from/find-callers/find-callees return the SAME resolved results (call graph precise post-purge). Second run removes nothing (idempotent).
- [ ] **Step 2: Run -> FAIL** (verb unknown).
- [ ] **Step 3: Implement** -- `PurgeLocals`: `DELETE FROM symbols WHERE kind IN ('local_var','param')` (call_edges references callee/receiver-type symbols, NOT locals, so it's untouched; ON DELETE cascade won't hit call_edges targets). Then `VACUUM`. Return rows deleted. `DoPurgeLocals`: open store (read-write), call PurgeLocals, report before/after DB file size + rows. Dispatch + usage.
- [ ] **Step 4: Build -> PASS** (the CRITICAL assertion: call graph identical before/after purge).
- [ ] **Step 5: Commit** -- `git commit -m "feat(d5): purge-locals verb -- shed local/param symbols, keep the call graph precise"`

---

## Task 13: Migration test (v13 -> v14) + full battery

**Files:**
- Create: `tests/callresolve/run_migrate_v13_to_v14.ps1`

- [ ] **Step 1:** Build a v13 DB fixture (index with a PRE-D5 exe is unavailable, so: index a fixture with the current exe, then hand-set `schema_meta.schema_version=13` + DROP `call_edges` to simulate a v13 DB -- OR keep a checked-in tiny v13 .sqlite). Open it with the D5 exe. Assert: schema becomes 14, `call_edges` table created, a reindex populates it, no crash. (Mirror `tests/autotest/run_migrate_v12.ps1` if it exists.)
- [ ] **Step 2: Run -> PASS.**
- [ ] **Step 3: Full battery** -- lint 154/154, store 16/16, autodoc 7/7, autofix 9/9, callresolve (all `run_*` from Tasks 2-12) -> all green on the staged exe.
- [ ] **Step 4: Commit** -- `git commit -m "test(d5): v13->v14 migration + full callresolve battery"`

---

## Task 14: Publish v0.91.0-alpha + background library reindex

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:6` (VERSION), `CHANGELOG.md`, `docs/lint/BACKLOG.md`

- [ ] **Step 1: Final whole-branch review** (superpowers:requesting-code-review) over the diff since the spec commit; fix Critical/Important. Focus: the resolver's conservative discipline (no wrong `certain`), the Called-from 3-way render, purge safety (call_edges intact), encoding, schema-array bound correctness.
- [ ] **Step 2: Bump** `DRagLint.CLI.pas:6` VERSION -> `0.91.0-alpha`; CHANGELOG entry (call_edges, ResolveCallTargets, typed locals/params, Called-from fix, find-callers --resolved/find-callees/ambiguous-calls[/call-path/callgraph], purge-locals, schema v14); BACKLOG resume (D5 shipped; NEXT = opt-in find-callers-default/impact/graph/forms-csv to resolved edges).
- [ ] **Step 3: Rebuild CLI, pack** win64+win32 CLI-only zips (`build\pack-lint-release.ps1 -Version 0.91.0-alpha`). Kill orphaned drag-lint.exe/drag_lint_graph.exe first.
- [ ] **Step 4: Release commit** (CLI.pas + CHANGELOG + BACKLOG only) -> `git tag v0.91.0-alpha` -> push main + tag -> `gh release create v0.91.0-alpha ... --latest` (isPrerelease=false) with the two zips.
- [ ] **Step 5: BACKGROUND LIBRARY REINDEX (the user requirement).** After the release exe is staged, launch the library reindex as a DETACHED background process (v14 forces a full reparse; ~1hr+, heavier with locals/params):
  - Kill any orphaned `drag-lint.exe`/`drag_lint_graph.exe`.
  - `Start-Process` (no `-Wait`) `third_party\dll-win64\drag-lint.exe index --scan-libraries-win` with stdout/stderr redirected to `C:\TEMP\d5-library-reindex.log`, so it runs unattended.
  - Optionally chain `purge-locals` on `library-Win32.sqlite`/`library-Win64.sqlite` after each finishes (slim-by-default per Design 7) -- confirm the auto-purge default here.
  - Tell the user it's running + the log path; it does NOT block anything else.
- [ ] **Step 6:** Reindex the self-index (changed dirs) incrementally. Update auto-memory RESUME + MEMORY.md.

---

## Self-review notes (author)

- **Spec coverage:** call_edges schema (T1) + typed params/locals emission (T2/T3) + store primitives (T4) + receiver-typing engine 8 kinds (T5) + ResolveCallTargets pass (T6) + Called-from bug fix 3-way render (T7) + find-callers --resolved (T8) + find-callees/ambiguous-calls (T9) + Calls-facts upgrade (T10, cuttable) + call-path/callgraph (T11, cuttable) + purge-locals (T12) + migration/battery (T13) + publish + background library reindex (T14). All spec sections mapped.
- **Type consistency:** `TCallEdge`/`TResolvedCaller` (T4) used by T5-T12. `skLocalVar`/`skParam` (T1) emitted T2/T3, consumed T5, purged T12. `ResolveOne` signature (T5) called by `ResolveCallTargets` (T6). `FindResolvedCallers` (T4) used by T7/T8/T11. Confidence strings `'certain'|'ambiguous'` consistent T5->T7.
- **Flagged soft spots:** (1) T1 SCHEMA_DDL array bound -- COUNT the entries; a mismatch is a compile error (encoded in the step). (2) T5 receiver-expr extraction reads source text -- keep `ExtractReceiverExpr` small + tested; cast/with/return kinds are the cut-3 items. (3) T7 updates existing autodoc fixtures' expected Called-from -- verify each is a precision gain. (4) T12 purge relies on call_edges NOT referencing locals -- true by schema (targets are callees/types); the test locks call-graph-identical-post-purge. (5) index-size/reindex-time growth measured in T6/T13; purge (T12) is the escape hatch.
- **Build gotchas encoded:** schema array bound; KindText lockstep; new-unit dproj+uses (T5); no literal braces in `{ }` comments; delphi-build recipe; neutral test CWD; staged exe; background (non-blocking) library reindex.
