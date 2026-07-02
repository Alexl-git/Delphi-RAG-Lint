# CK Class-Metrics Suite (v0.78) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five store-backed Chidamber & Kemerer class metrics as lint rules -- `deep-inheritance` (DIT), `too-many-children` (NOC), `high-coupling` (CBO), `high-response` (RFC), `low-cohesion` (LCOM4) -- shipped as one bundle in v0.78.

**Architecture:** One new unit `DRagLint.Lint.ClassMetrics` with a single public `TClassMetrics.Run(store, cfg)` that (1) builds a per-class inventory from the symbol store, then (2) computes all five metrics per class and emits an `info` finding at the class declaration when a configured threshold is exceeded. Runs project-wide in the CLI `lint-all` / `lint-project` paths only (not the per-file LSP). NOC/DIT use resolved heritage; CBO/RFC use stored `type_use`/`call` references; LCOM4 re-walks each method body's AST (via the parse cache) for complete field-access coverage.

**Tech Stack:** Delphi 13 (RAD Studio 37, Win64), tree-sitter, SQLite symbol store, DUnit-free console fixture harness (`tests/lint-store`).

## Global Constraints

- Source files are strict **7-bit ASCII, CRLF**. No UTF-8, no BOM, no Unicode chars in `.pas`. (`.md`/`.json`/`.txt` fixtures: keep ASCII too.)
- DocInsight `///` XML doc-comments required on the public type + method (`TClassMetrics`, `Run`).
- Build ONLY via `build\build_draglint_win64.bat` through PowerShell `Start-Process -Wait`; **kill every `drag-lint.exe` first** (the edit hook spawns it; a locked exe makes the bat's copy silently keep a STALE exe). Verify the freshly-built `third_party\dll-win64\drag-lint.exe` `LastWriteTime` after each build. Do NOT use the MCP build tool or `cmd.exe /c build.bat` from Bash.
- All 5 rules ship **ON by default**, severity **`info`**, category **`metrics`** (new).
- A rule's threshold default in `RuleCatalog.pas` (`MkParam('threshold','int','<n>')`) MUST equal its `ACfg.ThresholdFor('<id>', <n>)` default integer in `ClassMetrics.pas`.
- Metric rules fire strictly **greater-than** the threshold (`value > threshold`).
- Provisional thresholds: DIT 6, NOC 10, CBO 20, RFC 50, LCOM4 3. **Final values are set in Task 6** after FP-sanity over `src/`; Tasks 1-5 use these provisional values and their store-test cases pass regardless (cases lower the threshold via `config.json`).
- Never raise out of `Run`; a nil store yields no findings.
- Spec: `docs/superpowers/specs/2026-07-02-ck-class-metrics-design.md`.

---

### Task 1: New unit + inventory infrastructure + NOC (`too-many-children`)

Creates the whole unit skeleton (inventory build, direct-parent resolution, shared
helpers) and the first, simplest metric (NOC = direct subclass count), wired end to
end: dproj/dpr registration, the `DoLintAll` call, and the catalog entry.

**Files:**
- Create: `src/lint/DRagLint.Lint.ClassMetrics.pas`
- Modify: `src/cli/drag-lint.dpr` (after line 31)
- Modify: `src/cli/drag-lint.dproj` (after line 121)
- Modify: `src/cli/DRagLint.CLI.pas` (after line 5836, in `DoLintAll`)
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (new `metrics` block after line ~190)
- Test: `tests/lint-store/too-many-children/` (`base.pas`, `case.json`, `config.json`, `expected.txt`)

**Interfaces:**
- Consumes (from the store, all existing): `ISymbolStore.GetAllFileIds`, `.GetFilePath`, `.FindSymbolsByFile`, `.FindAllChildSymbols`, `.ResolveTypeCategory`, `.GetReferencesFromFile`, `.GetTransitiveAncestors`; `TLintConfig.ThresholdFor`.
- Produces (used by Tasks 2-5): the unit `DRagLint.Lint.ClassMetrics` with
  `class function TClassMetrics.Run(const AStore: ISymbolStore; const ACfg: TLintConfig; const ARuleId: string = ''): TArray<TLintFinding>;` and, inside `Run`, the nested infra `WantRule`, `Emit`, `GetRefs`, `InAnyMethodBody`, `InDeclSpan`, and the collections `Inv: TDictionary<Int64, TClassInfo>`, `ParentOf: TDictionary<Int64,Int64>`, `HasExtParent: TDictionary<Int64,Boolean>`, `NocCount: TDictionary<Int64,Integer>`. Unit-level helpers `IsMethodKind`, `NodeText`. Record `TClassInfo` (fields: `Id, Name, FileId, Path: ...; DeclLine, DeclCol, DeclEndLine: Integer; Heritage: string; Methods, Fields: TArray<TSymbol>`).

- [ ] **Step 1: Write the failing store-test case**

Create `tests/lint-store/too-many-children/base.pas` (a base class with 3 direct subclasses):

```pascal
unit base;

interface

type
  TAnimal = class
  public
    procedure Speak; virtual;
  end;

  TDog = class(TAnimal)
  end;

  TCat = class(TAnimal)
  end;

  TCow = class(TAnimal)
  end;

implementation

procedure TAnimal.Speak;
begin
end;

end.
```

Create `tests/lint-store/too-many-children/case.json`:

```json
{ "mode": "lint-all" }
```

Create `tests/lint-store/too-many-children/config.json` (lower the threshold so 3 children trips it):

```json
{ "thresholds": { "too-many-children": 2 } }
```

Create `tests/lint-store/too-many-children/expected.txt` (TAnimal is declared on line 6; negative on a leaf):

```
too-many-children base.pas:6
!too-many-children base.pas:11
```

- [ ] **Step 2: Run the harness to verify it fails**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter too-many-children
```
Expected: `FAIL too-many-children` -- `missing expected 'too-many-children' at base.pas:6` (rule not implemented yet).

- [ ] **Step 3: Create the unit with inventory + NOC**

Create `src/lint/DRagLint.Lint.ClassMetrics.pas`:

```pascal
unit DRagLint.Lint.ClassMetrics;

{ v0.78 CK class metrics (#6): DIT, NOC, CBO, RFC, LCOM4. Store-backed,
  project-wide -- runs only in lint-all / lint-project (not the per-file LSP).
  Complements the coarse god-class rule with individually-tunable metrics.
  Stateless; reads an open store; never raises. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , TreeSitter
  , TreeSitterLib
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  , DRagLint.Diagnostics.ParseCache
  ;

type
  TClassMetrics = class
  public
    /// <summary>Computes the five CK class metrics (DIT/NOC/CBO/RFC/LCOM4) over
    /// AStore and returns findings for classes exceeding each rule's configured
    /// threshold. A nil store yields no findings. ARuleId, when non-empty,
    /// restricts evaluation to that one rule id.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil -> empty result.</param>
    /// <param name="ACfg">Active lint config (supplies per-rule thresholds).</param>
    /// <param name="ARuleId">Single-rule filter for --rule; '' evaluates all five.</param>
    /// <returns>'info' findings anchored at each offending class declaration.</returns>
    /// <remarks>Project-wide; call from lint-all / lint-project only. Never raises.</remarks>
    class function Run(const AStore: ISymbolStore; const ACfg: TLintConfig;
      const ARuleId: string = ''): TArray<TLintFinding>;
  end;

implementation

type
  TClassInfo = record
    Id         : Int64          ;
    Name       : string         ;
    FileId     : Int64          ;
    Path       : string         ;
    DeclLine   : Integer        ;
    DeclCol    : Integer        ;
    DeclEndLine: Integer        ;
    Heritage   : string         ;
    Methods    : TArray<TSymbol>; { method-kind children }
    Fields     : TArray<TSymbol>; { skField children }
  end;

function IsMethodKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skMethod, skFunction, skProcedure, skConstructor, skDestructor];
end;

{ Raw source text of a tree-sitter node (empty on a null/out-of-range node). }
function NodeText(const N: TTSNode; const Src: TBytes): string;
var
  S, E, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
  if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
  Result:= TEncoding.UTF8.GetString(Src, S, L);
end;

{ Split a heritage list ('TBar, IBaz') into trimmed names. }
function SplitHeritage(const AHeritage: string): TArray<string>;
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  Result:= nil;
  if Trim(AHeritage) = '' then Exit;
  Parts:= AHeritage.Split([',']);
  for I:= 0 to High(Parts) do
    if Trim(Parts[I]) <> '' then Result:= Result + [Trim(Parts[I])];
end;

class function TClassMetrics.Run(const AStore: ISymbolStore; const ACfg: TLintConfig;
  const ARuleId: string): TArray<TLintFinding>;
var
  Inv         : TDictionary<Int64, TClassInfo>   ;
  ByName      : TDictionary<string, TList<Int64>>;
  ParentOf    : TDictionary<Int64, Int64>        ;
  HasExtParent: TDictionary<Int64, Boolean>      ;
  NocCount    : TDictionary<Int64, Integer>      ;
  RefsCache   : TDictionary<Int64, TArray<TReference>>;
  Findings    : TList<TLintFinding>              ;
  TNOC        : Integer                          ;
  CI          : TClassInfo                       ;

  function WantRule(const AId: string): Boolean;
  begin
    Result:= (ARuleId = '') or (ARuleId = AId);
  end;

  procedure Emit(const AId, AMsg: string; const AInfo: TClassInfo);
  var
    F: TLintFinding;
  begin
    F:= Default(TLintFinding);
    F.RuleId  := AId;
    F.Severity:= 'info';
    F.Message := AMsg;
    F.FilePath:= AInfo.Path;
    F.StartLine:= AInfo.DeclLine;
    F.StartCol := AInfo.DeclCol;
    F.EndLine  := AInfo.DeclLine;
    F.EndCol   := AInfo.DeclCol + Length(AInfo.Name);
    Findings.Add(F);
  end;

  function GetRefs(AFileId: Int64): TArray<TReference>;
  begin
    if not RefsCache.TryGetValue(AFileId, Result) then
    begin
      Result:= AStore.GetReferencesFromFile(AFileId);
      RefsCache.Add(AFileId, Result);
    end;
  end;

  function InAnyMethodBody(const AInfo: TClassInfo; ALine: Integer): Boolean;
  var
    M: TSymbol;
  begin
    for M in AInfo.Methods do
      if (M.ImplStartLine > 0) and (ALine >= M.ImplStartLine) and (ALine <= M.ImplEndLine) then
        Exit(True);
    Result:= False;
  end;

  function InDeclSpan(const AInfo: TClassInfo; ALine: Integer): Boolean;
  begin
    Result:= (ALine >= AInfo.DeclLine) and (ALine <= AInfo.DeclEndLine);
  end;

  procedure BuildInventory;
  var
    Fid : Int64          ;
    Path: string         ;
    Syms: TArray<TSymbol>;
    Kids: TArray<TSymbol>;
    S, K: TSymbol        ;
    Info: TClassInfo     ;
    Low : string         ;
    Lst : TList<Int64>   ;
  begin
    for Fid in AStore.GetAllFileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      Syms:= AStore.FindSymbolsByFile(Path);
      for S in Syms do
        if S.Kind = skClass then
        begin
          Info:= Default(TClassInfo);
          Info.Id         := S.Id;
          Info.Name       := S.Name;
          Info.FileId     := Fid;
          Info.Path       := Path;
          Info.DeclLine   := S.StartLine;
          Info.DeclCol    := S.StartCol;
          Info.DeclEndLine:= S.EndLine;
          Info.Heritage   := S.Heritage;
          Kids:= AStore.FindAllChildSymbols(S.Id);
          for K in Kids do
            if IsMethodKind(K.Kind) then Info.Methods:= Info.Methods + [K]
            else if K.Kind = skField then Info.Fields:= Info.Fields + [K];
          if not Inv.ContainsKey(Info.Id) then
          begin
            Inv.Add(Info.Id, Info);
            Low:= LowerCase(Info.Name);
            if not ByName.TryGetValue(Low, Lst) then
            begin
              Lst:= TList<Int64>.Create;
              ByName.Add(Low, Lst);
            end;
            Lst.Add(Info.Id);
          end;
        end;
    end;
  end;

  { Resolve each class's direct class-parent (first heritage entry that resolves
    to a class). Internal parent -> ParentOf; external (RTL) parent -> HasExtParent. }
  procedure ResolveParents;
  var
    Info : TClassInfo    ;
    Names: TArray<string>;
    Nm   : string        ;
    Lst  : TList<Int64>  ;
  begin
    for Info in Inv.Values do
    begin
      Names:= SplitHeritage(Info.Heritage);
      for Nm in Names do
      begin
        if AStore.ResolveTypeCategory(Nm, Info.FileId) <> tcClass then Continue;
        { first class-kind heritage entry is the parent }
        if ByName.TryGetValue(LowerCase(Nm), Lst) and (Lst.Count > 0) then
          ParentOf.AddOrSetValue(Info.Id, Lst[0])
        else
          HasExtParent.AddOrSetValue(Info.Id, True);
        Break;
      end;
    end;
  end;

  procedure ComputeNOC;
  var
    Pair: TPair<Int64, Int64>;
    Cur : Integer            ;
  begin
    for Pair in ParentOf do
    begin
      Cur:= 0;
      NocCount.TryGetValue(Pair.Value, Cur);
      NocCount.AddOrSetValue(Pair.Value, Cur + 1);
    end;
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;

  Inv         := TDictionary<Int64, TClassInfo>.Create;
  ByName      := TDictionary<string, TList<Int64>>.Create;
  ParentOf    := TDictionary<Int64, Int64>.Create;
  HasExtParent:= TDictionary<Int64, Boolean>.Create;
  NocCount    := TDictionary<Int64, Integer>.Create;
  RefsCache   := TDictionary<Int64, TArray<TReference>>.Create;
  Findings    := TList<TLintFinding>.Create;
  try
    TNOC:= ACfg.ThresholdFor('too-many-children', 10);

    BuildInventory;
    ResolveParents;
    ComputeNOC;

    for CI in Inv.Values do
    begin
      if WantRule('too-many-children') then
      begin
        var N: Integer:= 0;
        NocCount.TryGetValue(CI.Id, N);
        if N > TNOC then
          Emit('too-many-children',
            Format('High NOC: %s has %d direct subclasses (>%d) -- a wide, fragile base class', [CI.Name, N, TNOC]),
            CI);
      end;
    end;

    Result:= Findings.ToArray;
  finally
    for var L in ByName.Values do L.Free;
    ByName.Free;
    Inv.Free;
    ParentOf.Free;
    HasExtParent.Free;
    NocCount.Free;
    RefsCache.Free;
    Findings.Free;
    TAstParseCache.Clear;
  end;
end;

end.
```

- [ ] **Step 4: Register the unit in the CLI project (.dpr)**

In `src/cli/drag-lint.dpr`, add after line 31 (`DRagLint.Lint.ProjectRules in ...`):

```pascal
  DRagLint.Lint.ClassMetrics in '..\lint\DRagLint.Lint.ClassMetrics.pas',
```

- [ ] **Step 5: Register the unit in the CLI project (.dproj)**

In `src/cli/drag-lint.dproj`, add after line 121 (`<DCCReference Include="..\lint\DRagLint.Lint.ProjectRules.pas"/>`):

```xml
        <DCCReference Include="..\lint\DRagLint.Lint.ClassMetrics.pas"/>
```

- [ ] **Step 6: Invoke the metrics in DoLintAll**

In `src/cli/DRagLint.CLI.pas`, immediately after line 5836 (the `TProjectLintRules.Run(Store, '')` addition), insert:

```pascal
  { v0.78: CK class metrics (DIT/NOC/CBO/RFC/LCOM4). Project-wide; runs only here. }
  Findings:= Findings +
    DRagLint.Lint.ClassMetrics.TClassMetrics.Run(Store, Cfg, '');
```

(The `DRagLint.Lint.ClassMetrics` unit is reachable because it is in the .dpr `uses`; reference it fully-qualified like `TProjectLintRules`. `Cfg` is the `TLintConfig` already declared at line 5749.)

- [ ] **Step 7: Add the catalog entry**

In `src/lint/DRagLint.Lint.RuleCatalog.pas`, after the `god-class` block (the `project-wide` group ending near line 190), add a new category block:

```pascal
    { --- metrics (CK class metrics; v0.78) --- }
    B('too-many-children', 'metrics', 'info', 'Class has too many direct subclasses (NOC)', True, [MkParam('threshold','int','10')]);
```

- [ ] **Step 8: Build the CLI (Win64)**

Run (PowerShell):
```
Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue
Start-Process -FilePath "$PWD\build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\ckbuild1.log"
Get-Content "$env:TEMP\ckbuild1.log" -Tail 20
(Get-Item third_party\dll-win64\drag-lint.exe).LastWriteTime
```
Expected: log ends with `BUILD_EXITCODE=0`, no `[dcc] Error`; the exe `LastWriteTime` is the current time.

- [ ] **Step 9: Run the harness to verify it passes**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter too-many-children
```
Expected: `PASS too-many-children` and `store-tests: 1 pass / 0 fail / 1 total`.

- [ ] **Step 10: Regression -- full store harness still green**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1
```
Expected: all existing cases (`abstract-method`, `circular-uses`, `duplicate-code`, `smoke-objleak`) plus `too-many-children` PASS; `0 fail`.

- [ ] **Step 11: Commit**

```
git add src/lint/DRagLint.Lint.ClassMetrics.pas src/cli/drag-lint.dpr src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas src/lint/DRagLint.Lint.RuleCatalog.pas tests/lint-store/too-many-children/
git commit -m "feat(lint): CK metrics unit + NOC (too-many-children) #6"
```

---

### Task 2: DIT (`deep-inheritance`)

Adds the inheritance-depth walk over the `ParentOf` chain built in Task 1.

**Files:**
- Modify: `src/lint/DRagLint.Lint.ClassMetrics.pas`
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (metrics block)
- Test: `tests/lint-store/deep-inheritance/` (`chain.pas`, `case.json`, `config.json`, `expected.txt`)

**Interfaces:**
- Consumes: `ParentOf`, `HasExtParent`, `Inv` (Task 1); adds nested `ComputeDIT(AId): Integer`.
- Produces: rule `deep-inheritance` firing when DIT > threshold.

- [ ] **Step 1: Write the failing store-test case**

Create `tests/lint-store/deep-inheritance/chain.pas` (a 4-deep chain: TA<-TB<-TC<-TD):

```pascal
unit chain;

interface

type
  TA = class
  end;

  TB = class(TA)
  end;

  TC = class(TB)
  end;

  TD = class(TC)
  end;

implementation

end.
```

Create `tests/lint-store/deep-inheritance/case.json`:

```json
{ "mode": "lint-all" }
```

Create `tests/lint-store/deep-inheritance/config.json` (threshold 2 -> TD at depth 3 fires; TB at depth 1 does not):

```json
{ "thresholds": { "deep-inheritance": 2 } }
```

Create `tests/lint-store/deep-inheritance/expected.txt` (TD is on line 15; TB on line 9):

```
deep-inheritance chain.pas:15
!deep-inheritance chain.pas:9
```

- [ ] **Step 2: Run the harness to verify it fails**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter deep-inheritance
```
Expected: `FAIL deep-inheritance` -- `missing expected 'deep-inheritance' at chain.pas:15`.

- [ ] **Step 3: Add the DIT computation**

In `src/lint/DRagLint.Lint.ClassMetrics.pas`, add a nested function BEFORE the `begin` of `Run` (place it right after `ComputeNOC`):

```pascal
  { Depth of inheritance: hops up the internal parent chain; a known-but-unindexed
    (external/RTL) parent adds one final hop. Cycle-guarded, hard-capped at 32. }
  function ComputeDIT(AId: Int64): Integer;
  var
    Cur    : Int64            ;
    Depth  : Integer          ;
    Visited: TDictionary<Int64, Boolean>;
    P      : Int64            ;
  begin
    Depth:= 0;
    Cur:= AId;
    Visited:= TDictionary<Int64, Boolean>.Create;
    try
      while True do
      begin
        if Visited.ContainsKey(Cur) then Break;
        Visited.Add(Cur, True);
        if ParentOf.TryGetValue(Cur, P) then
        begin
          Inc(Depth);
          Cur:= P;
          if Depth >= 32 then Break;
        end
        else
        begin
          if HasExtParent.ContainsKey(Cur) then Inc(Depth);
          Break;
        end;
      end;
    finally
      Visited.Free;
    end;
    Result:= Depth;
  end;
```

Add the threshold var. Change the `var` block line `TNOC : Integer;` to:

```pascal
  TNOC        : Integer                          ;
  TDIT        : Integer                          ;
```

Read it -- after `TNOC:= ACfg.ThresholdFor('too-many-children', 10);` add:

```pascal
    TDIT:= ACfg.ThresholdFor('deep-inheritance', 6);
```

In the per-class loop, after the `too-many-children` block, add:

```pascal
      if WantRule('deep-inheritance') then
      begin
        var D: Integer:= ComputeDIT(CI.Id);
        if D > TDIT then
          Emit('deep-inheritance',
            Format('Deep inheritance: %s is %d levels deep (>%d) -- deep hierarchies are hard to follow', [CI.Name, D, TDIT]),
            CI);
      end;
```

- [ ] **Step 4: Add the catalog entry**

In `src/lint/DRagLint.Lint.RuleCatalog.pas`, in the metrics block, after `too-many-children`:

```pascal
    B('deep-inheritance', 'metrics', 'info', 'Class inheritance is too deep (DIT)', True, [MkParam('threshold','int','6')]);
```

- [ ] **Step 5: Build the CLI (Win64)**

Run:
```
Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue
Start-Process -FilePath "$PWD\build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\ckbuild2.log"
Get-Content "$env:TEMP\ckbuild2.log" -Tail 20
```
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 6: Run the harness (new case + regression)**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter deep-inheritance
pwsh -File tests\lint-store\run_store_tests.ps1
```
Expected: `PASS deep-inheritance`; full run `0 fail`.

- [ ] **Step 7: Commit**

```
git add src/lint/DRagLint.Lint.ClassMetrics.pas src/lint/DRagLint.Lint.RuleCatalog.pas tests/lint-store/deep-inheritance/
git commit -m "feat(lint): DIT (deep-inheritance) CK metric #6"
```

---

### Task 3: RFC (`high-response`)

Adds the response-for-a-class count: own methods + distinct call names in method bodies.

**Files:**
- Modify: `src/lint/DRagLint.Lint.ClassMetrics.pas`
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (metrics block)
- Test: `tests/lint-store/high-response/` (`svc.pas`, `case.json`, `config.json`, `expected.txt`)

**Interfaces:**
- Consumes: `GetRefs`, `InAnyMethodBody`, `Inv` (Task 1); adds nested `ComputeRFC(const AInfo): Integer`.
- Produces: rule `high-response` firing when RFC > threshold.

- [ ] **Step 1: Write the failing store-test case**

Create `tests/lint-store/high-response/svc.pas` (2 methods calling several distinct routines):

```pascal
unit svc;

interface

type
  TService = class
  public
    procedure DoWork;
    procedure DoMore;
  end;

implementation

uses
  System.SysUtils;

procedure TService.DoWork;
begin
  Alpha;
  Beta;
  Gamma;
end;

procedure TService.DoMore;
begin
  Delta;
  Epsilon;
end;

procedure Alpha; begin end;
procedure Beta; begin end;
procedure Gamma; begin end;
procedure Delta; begin end;
procedure Epsilon; begin end;

end.
```

(`Alpha..Epsilon` are declared after use; tree-sitter parses them regardless. RFC = 2 methods + 5 distinct calls = 7.)

Create `tests/lint-store/high-response/case.json`:

```json
{ "mode": "lint-all" }
```

Create `tests/lint-store/high-response/config.json` (threshold 5 -> RFC 7 fires):

```json
{ "thresholds": { "high-response": 5 } }
```

Create `tests/lint-store/high-response/expected.txt` (TService on line 6):

```
high-response svc.pas:6
```

- [ ] **Step 2: Run the harness to verify it fails**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter high-response
```
Expected: `FAIL high-response` -- `missing expected 'high-response' at svc.pas:6`.

- [ ] **Step 3: Add the RFC computation**

In `src/lint/DRagLint.Lint.ClassMetrics.pas`, add a nested function after `ComputeDIT`:

```pascal
  { Response for a class: own method count + distinct callee names invoked from
    within the class's method bodies (case-insensitive). }
  function ComputeRFC(const AInfo: TClassInfo): Integer;
  var
    Refs  : TArray<TReference>       ;
    R     : TReference              ;
    Called: TDictionary<string, Boolean>;
  begin
    Called:= TDictionary<string, Boolean>.Create;
    try
      Refs:= GetRefs(AInfo.FileId);
      for R in Refs do
        if SameText(R.Kind, 'call') and (R.NameText <> '') and InAnyMethodBody(AInfo, R.StartLine) then
          Called.AddOrSetValue(LowerCase(R.NameText), True);
      Result:= Length(AInfo.Methods) + Called.Count;
    finally
      Called.Free;
    end;
  end;
```

Add the threshold var to the `var` block:

```pascal
  TRFC        : Integer                          ;
```

Read it after the `TDIT` assignment:

```pascal
    TRFC:= ACfg.ThresholdFor('high-response', 50);
```

In the per-class loop, after the `deep-inheritance` block, add:

```pascal
      if WantRule('high-response') then
      begin
        var Rfc: Integer:= ComputeRFC(CI);
        if Rfc > TRFC then
          Emit('high-response',
            Format('High RFC: %s has a response set of %d (>%d) -- many methods and calls to test/understand', [CI.Name, Rfc, TRFC]),
            CI);
      end;
```

- [ ] **Step 4: Add the catalog entry**

In `src/lint/DRagLint.Lint.RuleCatalog.pas`, metrics block, after `deep-inheritance`:

```pascal
    B('high-response', 'metrics', 'info', 'Class response set is too large (RFC)', True, [MkParam('threshold','int','50')]);
```

- [ ] **Step 5: Build the CLI (Win64)**

Run:
```
Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue
Start-Process -FilePath "$PWD\build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\ckbuild3.log"
Get-Content "$env:TEMP\ckbuild3.log" -Tail 20
```
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 6: Run the harness (new case + regression)**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter high-response
pwsh -File tests\lint-store\run_store_tests.ps1
```
Expected: `PASS high-response`; full run `0 fail`.

- [ ] **Step 7: Commit**

```
git add src/lint/DRagLint.Lint.ClassMetrics.pas src/lint/DRagLint.Lint.RuleCatalog.pas tests/lint-store/high-response/
git commit -m "feat(lint): RFC (high-response) CK metric #6"
```

---

### Task 4: CBO (`high-coupling`)

Adds efferent coupling: distinct other classes referenced (via `type_use`) from the class's declaration and method bodies, excluding self and ancestors.

**Files:**
- Modify: `src/lint/DRagLint.Lint.ClassMetrics.pas`
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (metrics block)
- Test: `tests/lint-store/high-coupling/` (`coupled.pas`, `case.json`, `config.json`, `expected.txt`)

**Interfaces:**
- Consumes: `GetRefs`, `InDeclSpan`, `InAnyMethodBody`, `Inv`, `AStore.ResolveTypeCategory`, `AStore.GetTransitiveAncestors` (Task 1); adds nested `ComputeCBO(const AInfo): Integer`.
- Produces: rule `high-coupling` firing when CBO > threshold.

- [ ] **Step 1: Write the failing store-test case**

Create `tests/lint-store/high-coupling/coupled.pas` (`THub` uses three other classes as field types; `TLone` uses none):

```pascal
unit coupled;

interface

type
  TAlpha = class
  end;

  TBeta = class
  end;

  TGamma = class
  end;

  THub = class
  private
    FA: TAlpha;
    FB: TBeta;
    FC: TGamma;
  end;

  TLone = class
  private
    FN: Integer;
  end;

implementation

end.
```

Create `tests/lint-store/high-coupling/case.json`:

```json
{ "mode": "lint-all" }
```

Create `tests/lint-store/high-coupling/config.json` (threshold 2 -> THub with CBO 3 fires; TLone does not):

```json
{ "thresholds": { "high-coupling": 2 } }
```

Create `tests/lint-store/high-coupling/expected.txt` (THub on line 15; TLone on line 22):

```
high-coupling coupled.pas:15
!high-coupling coupled.pas:22
```

- [ ] **Step 2: Run the harness to verify it fails**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter high-coupling
```
Expected: `FAIL high-coupling` -- `missing expected 'high-coupling' at coupled.pas:15`.

- [ ] **Step 3: Add the CBO computation**

In `src/lint/DRagLint.Lint.ClassMetrics.pas`, add a nested function after `ComputeRFC`:

```pascal
  { Efferent coupling: distinct OTHER classes named (type_use) in the class's decl
    span or method bodies. Excludes self and the class's transitive ancestors. }
  function ComputeCBO(const AInfo: TClassInfo): Integer;
  var
    Coupled: TDictionary<string, Boolean>;
    Exclude: TDictionary<string, Boolean>;
    Anc    : TArray<TTypeAncestor>       ;
    A      : TTypeAncestor               ;
    Refs   : TArray<TReference>          ;
    R      : TReference                  ;
    Nm     : string                      ;
  begin
    Coupled:= TDictionary<string, Boolean>.Create;
    Exclude:= TDictionary<string, Boolean>.Create;
    try
      Exclude.AddOrSetValue(LowerCase(AInfo.Name), True);
      Anc:= AStore.GetTransitiveAncestors(AInfo.Id);
      for A in Anc do
        if A.Name <> '' then Exclude.AddOrSetValue(LowerCase(A.Name), True);
      Refs:= GetRefs(AInfo.FileId);
      for R in Refs do
      begin
        if not SameText(R.Kind, 'type_use') then Continue;
        if R.NameText = '' then Continue;
        if not (InDeclSpan(AInfo, R.StartLine) or InAnyMethodBody(AInfo, R.StartLine)) then Continue;
        Nm:= LowerCase(R.NameText);
        if Exclude.ContainsKey(Nm) then Continue;
        if AStore.ResolveTypeCategory(R.NameText, AInfo.FileId) = tcClass then
          Coupled.AddOrSetValue(Nm, True);
      end;
      Result:= Coupled.Count;
    finally
      Exclude.Free;
      Coupled.Free;
    end;
  end;
```

Add the threshold var to the `var` block:

```pascal
  TCBO        : Integer                          ;
```

Read it after the `TRFC` assignment:

```pascal
    TCBO:= ACfg.ThresholdFor('high-coupling', 20);
```

In the per-class loop, after the `high-response` block, add:

```pascal
      if WantRule('high-coupling') then
      begin
        var Cbo: Integer:= ComputeCBO(CI);
        if Cbo > TCBO then
          Emit('high-coupling',
            Format('High CBO: %s is coupled to %d other classes (>%d) -- consider reducing dependencies', [CI.Name, Cbo, TCBO]),
            CI);
      end;
```

- [ ] **Step 4: Add the catalog entry**

In `src/lint/DRagLint.Lint.RuleCatalog.pas`, metrics block, after `high-response`:

```pascal
    B('high-coupling', 'metrics', 'info', 'Class is coupled to too many other classes (CBO)', True, [MkParam('threshold','int','20')]);
```

- [ ] **Step 5: Build the CLI (Win64)**

Run:
```
Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue
Start-Process -FilePath "$PWD\build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\ckbuild4.log"
Get-Content "$env:TEMP\ckbuild4.log" -Tail 20
```
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 6: Run the harness (new case + regression)**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter high-coupling
pwsh -File tests\lint-store\run_store_tests.ps1
```
Expected: `PASS high-coupling`; full run `0 fail`.

- [ ] **Step 7: Commit**

```
git add src/lint/DRagLint.Lint.ClassMetrics.pas src/lint/DRagLint.Lint.RuleCatalog.pas tests/lint-store/high-coupling/
git commit -m "feat(lint): CBO (high-coupling) CK metric #6"
```

---

### Task 5: LCOM4 (`low-cohesion`)

Adds the connected-components cohesion metric via a per-method AST re-walk (complete field-access coverage) + union-find.

**Files:**
- Modify: `src/lint/DRagLint.Lint.ClassMetrics.pas`
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (metrics block)
- Test: `tests/lint-store/low-cohesion/` (`split.pas`, `cohesive.pas`, `case.json`, `config.json`, `expected.txt`)

**Interfaces:**
- Consumes: `Inv`, `TAstParseCache.Get`, `NodeText`, `IsMethodKind` (Task 1); adds nested `ComputeLCOM4(const AInfo): Integer` and, inside it, `CollectDefProcNodes` and `CollectIdentifiers`.
- Produces: rule `low-cohesion` firing when LCOM4 > threshold.

- [ ] **Step 1: Write the failing store-test case**

Create `tests/lint-store/low-cohesion/split.pas` (`TSplit` has two field-disjoint, non-calling method clusters -> LCOM4 = 2):

```pascal
unit split;

interface

type
  TSplit = class
  private
    FA: Integer;
    FB: Integer;
  public
    procedure UseA;
    procedure UseAgainA;
    procedure UseB;
    procedure UseAgainB;
  end;

implementation

procedure TSplit.UseA;
begin
  FA:= 1;
end;

procedure TSplit.UseAgainA;
begin
  FA:= FA + 1;
end;

procedure TSplit.UseB;
begin
  FB:= 2;
end;

procedure TSplit.UseAgainB;
begin
  FB:= FB + 1;
end;

end.
```

Create `tests/lint-store/low-cohesion/cohesive.pas` (`TCohesive` -- every method touches the shared field -> LCOM4 = 1):

```pascal
unit cohesive;

interface

type
  TCohesive = class
  private
    FShared: Integer;
  public
    procedure First;
    procedure Second;
  end;

implementation

procedure TCohesive.First;
begin
  FShared:= 1;
end;

procedure TCohesive.Second;
begin
  FShared:= FShared + 1;
end;

end.
```

Create `tests/lint-store/low-cohesion/case.json`:

```json
{ "mode": "lint-all" }
```

Create `tests/lint-store/low-cohesion/config.json` (threshold 1 -> LCOM4 2 fires; LCOM4 1 does not):

```json
{ "thresholds": { "low-cohesion": 1 } }
```

Create `tests/lint-store/low-cohesion/expected.txt` (TSplit on line 6 of split.pas; TCohesive on line 6 of cohesive.pas):

```
low-cohesion split.pas:6
!low-cohesion cohesive.pas
```

- [ ] **Step 2: Run the harness to verify it fails**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter low-cohesion
```
Expected: `FAIL low-cohesion` -- `missing expected 'low-cohesion' at split.pas:6`.

- [ ] **Step 3: Add the LCOM4 computation**

In `src/lint/DRagLint.Lint.ClassMetrics.pas`, add a nested function after `ComputeCBO`:

```pascal
  { LCOM4: connected components of the method graph. Nodes = body-bearing methods.
    Edge when two methods share an accessed field OR one calls the other. Field/
    call access is read from a complete AST re-walk of each method body. }
  function ComputeLCOM4(const AInfo: TClassInfo): Integer;
  var
    PF        : TParsedFile               ;
    BodyM     : TArray<TSymbol>           ;
    M         : TSymbol                   ;
    FieldNames: TDictionary<string, Boolean>;
    MethNames : TDictionary<string, Boolean>;
    ProcByLine: TDictionary<Integer, TTSNode>;
    IdSets    : TArray<TDictionary<string, Boolean>>;
    N, I, J   : Integer                   ;
    UF        : TArray<Integer>           ;
    Roots     : TDictionary<Integer, Boolean>;

    procedure CollectDefProcNodes(const ANode: TTSNode);
    var
      C  : Integer;
      Ln : Integer;
    begin
      if ANode.IsNull then Exit;
      if ANode.NodeType = 'defProc' then
      begin
        Ln:= Integer(ANode.StartPoint.row) + 1;
        if not ProcByLine.ContainsKey(Ln) then ProcByLine.Add(Ln, ANode);
      end;
      for C:= 0 to ANode.NamedChildCount - 1 do CollectDefProcNodes(ANode.NamedChild(C));
    end;

    procedure CollectIdentifiers(const ANode: TTSNode; ADst: TDictionary<string, Boolean>);
    var
      C: Integer;
      T: string ;
    begin
      if ANode.IsNull then Exit;
      if ANode.NodeType = 'identifier' then
      begin
        T:= LowerCase(NodeText(ANode, PF.Src));
        if T <> '' then ADst.AddOrSetValue(T, True);
      end;
      for C:= 0 to ANode.NamedChildCount - 1 do CollectIdentifiers(ANode.NamedChild(C), ADst);
    end;

    function Find(X: Integer): Integer;
    begin
      while UF[X] <> X do
      begin
        UF[X]:= UF[UF[X]];
        X:= UF[X];
      end;
      Result:= X;
    end;

    procedure Union(X, Y: Integer);
    var
      Rx, Ry: Integer;
    begin
      Rx:= Find(X); Ry:= Find(Y);
      if Rx <> Ry then UF[Rx]:= Ry;
    end;

    function Connected(A, B: Integer): Boolean;
    var
      K: string;
    begin
      Result:= False;
      { shared field access }
      for K in IdSets[A].Keys do
        if FieldNames.ContainsKey(K) and IdSets[B].ContainsKey(K) then Exit(True);
      { A calls B or B calls A (by method name) }
      if IdSets[A].ContainsKey(LowerCase(BodyM[B].Name)) then Exit(True);
      if IdSets[B].ContainsKey(LowerCase(BodyM[A].Name)) then Exit(True);
    end;

  begin
    BodyM:= nil;
    for M in AInfo.Methods do
      if M.ImplStartLine > 0 then BodyM:= BodyM + [M];
    N:= Length(BodyM);
    if N <= 1 then Exit(N); { 0 or 1 body-method -> 0 or 1 component }

    PF:= TAstParseCache.Get(AInfo.Path);
    if PF.Tree = nil then Exit(1); { unparseable -> treat as cohesive }

    FieldNames:= TDictionary<string, Boolean>.Create;
    MethNames := TDictionary<string, Boolean>.Create;
    ProcByLine:= TDictionary<Integer, TTSNode>.Create;
    SetLength(IdSets, N);
    SetLength(UF, N);
    try
      for M in AInfo.Fields do FieldNames.AddOrSetValue(LowerCase(M.Name), True);
      for I:= 0 to N - 1 do MethNames.AddOrSetValue(LowerCase(BodyM[I].Name), True);
      CollectDefProcNodes(PF.Tree.RootNode);

      for I:= 0 to N - 1 do
      begin
        IdSets[I]:= TDictionary<string, Boolean>.Create;
        UF[I]:= I;
        var Node: TTSNode;
        if ProcByLine.TryGetValue(BodyM[I].ImplStartLine, Node) then
          CollectIdentifiers(Node, IdSets[I]);
      end;

      for I:= 0 to N - 2 do
        for J:= I + 1 to N - 1 do
          if Connected(I, J) then Union(I, J);

      Roots:= TDictionary<Integer, Boolean>.Create;
      try
        for I:= 0 to N - 1 do Roots.AddOrSetValue(Find(I), True);
        Result:= Roots.Count;
      finally
        Roots.Free;
      end;
    finally
      for I:= 0 to N - 1 do
        if IdSets[I] <> nil then IdSets[I].Free;
      ProcByLine.Free;
      MethNames.Free;
      FieldNames.Free;
    end;
  end;
```

Add the threshold var to the `var` block:

```pascal
  TLCOM       : Integer                          ;
```

Read it after the `TCBO` assignment:

```pascal
    TLCOM:= ACfg.ThresholdFor('low-cohesion', 3);
```

In the per-class loop, after the `high-coupling` block, add:

```pascal
      if WantRule('low-cohesion') then
      begin
        var Lc: Integer:= ComputeLCOM4(CI);
        if Lc > TLCOM then
          Emit('low-cohesion',
            Format('Low cohesion: %s has LCOM4=%d (>%d) -- the class may combine unrelated responsibilities; consider splitting', [CI.Name, Lc, TLCOM]),
            CI);
      end;
```

- [ ] **Step 4: Add the catalog entry**

In `src/lint/DRagLint.Lint.RuleCatalog.pas`, metrics block, after `high-coupling`:

```pascal
    B('low-cohesion', 'metrics', 'info', 'Class methods lack cohesion (LCOM4)', True, [MkParam('threshold','int','3')]);
```

- [ ] **Step 5: Build the CLI (Win64)**

Run:
```
Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue
Start-Process -FilePath "$PWD\build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\ckbuild5.log"
Get-Content "$env:TEMP\ckbuild5.log" -Tail 20
```
Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 6: Run the harness (new case + regression)**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1 -Filter low-cohesion
pwsh -File tests\lint-store\run_store_tests.ps1
```
Expected: `PASS low-cohesion`; full run `0 fail`.

- [ ] **Step 7: Commit**

```
git add src/lint/DRagLint.Lint.ClassMetrics.pas src/lint/DRagLint.Lint.RuleCatalog.pas tests/lint-store/low-cohesion/
git commit -m "feat(lint): LCOM4 (low-cohesion) CK metric #6"
```

---

### Task 6: Calibrate thresholds over src/, catalog test, docs

Runs each rule over the project's own `src/` at its shipped default, tunes defaults so clean code yields ~0 findings, and updates the catalog test + docs.

**Files:**
- Modify: `src/lint/DRagLint.Lint.ClassMetrics.pas` (final `ThresholdFor` defaults, if tuned)
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (final `MkParam` defaults, kept in lockstep)
- Modify: `CHANGELOG.md`
- Modify: `docs/lint/MISSING-FEATURES.md`

**Interfaces:**
- Consumes: the built `drag-lint.exe` from Task 5.
- Produces: final calibrated defaults; updated docs; green catalog test.

- [ ] **Step 1: Index src/ and run the metrics at defaults**

Build a throwaway index of the project and run lint-all (metrics only) to count findings per rule:

```
$db = "$env:TEMP\ck_src.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }
third_party\dll-win64\drag-lint.exe index src --db $db 2>$null | Out-Null
third_party\dll-win64\drag-lint.exe lint-all --db $db --json 2>$null > "$env:TEMP\ck_src.json"
$all = Get-Content "$env:TEMP\ck_src.json" -Raw
$j = $all.Substring($all.IndexOf('[')) | ConvertFrom-Json
$j | Where-Object { $_.rule -in @('too-many-children','deep-inheritance','high-coupling','high-response','low-cohesion') } | Group-Object rule | Select-Object Name,Count
```
Expected: a small count per rule. Record the numbers.

- [ ] **Step 2: Tune defaults for ~0 clean-code noise**

For any rule firing more than a handful of times on `src/`, raise its default until clean code is quiet (mirror the `cognitive-complexity` calibration that shipped at 25). Change BOTH:
- `src/lint/DRagLint.Lint.ClassMetrics.pas`: the `ACfg.ThresholdFor('<id>', <n>)` default integer.
- `src/lint/DRagLint.Lint.RuleCatalog.pas`: the matching `MkParam('threshold','int','<n>')`.

They MUST stay equal. Inspect a few actual findings per rule to confirm they are genuine (a truly deep hierarchy / wide base / god-ish coupling), not artifacts. If a rule fires only on genuinely-smelly classes, its default is good as-is.

- [ ] **Step 3: Rebuild if defaults changed**

If Step 2 changed any default, rebuild:
```
Stop-Process -Name drag-lint -Force -ErrorAction SilentlyContinue
Start-Process -FilePath "$PWD\build\build_draglint_win64.bat" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\ckbuild6.log"
Get-Content "$env:TEMP\ckbuild6.log" -Tail 20
```
Expected: `BUILD_EXITCODE=0`.

- [ ] **Step 4: Run the rule-catalog test**

Run:
```
pwsh -File tests\rules-catalog\run_rulecatalog_tests.ps1
```
Expected: PASS (catalog counts are relative/self-checked; the new `metrics` category adds 5 rules without breaking the naming=9 assertion). If the runner script name differs, list `tests\rules-catalog\` and run the `.ps1` there.

- [ ] **Step 5: Full harness regression**

Run:
```
pwsh -File tests\lint-store\run_store_tests.ps1
pwsh -File tests\lint\run_lint_tests.ps1
```
Expected: both `0 fail` (file harness unaffected; store harness includes the 5 new cases).

- [ ] **Step 6: Update CHANGELOG + MISSING-FEATURES**

In `CHANGELOG.md`, under the "Unreleased" section, add an entry:

```
### Added
- CK class metrics (#6): `deep-inheritance` (DIT), `too-many-children` (NOC),
  `high-coupling` (CBO), `high-response` (RFC), `low-cohesion` (LCOM4). Store-backed,
  project-wide (lint-all / lint-project), ON by default, category `metrics`,
  configurable `threshold` per rule. LCOM shipped as LCOM4 (connected components).
  Known limits: DIT undercounts without the RTL/library index (external parents
  count as one hop); resolution is name-based; CBO is efferent (type-use) only.
```

In `docs/lint/MISSING-FEATURES.md`, mark the CK-suite items (NOC/DIT/CBO/RFC/LCOM under #6) as `[x]` done.

- [ ] **Step 7: Commit**

```
git add src/lint/DRagLint.Lint.ClassMetrics.pas src/lint/DRagLint.Lint.RuleCatalog.pas CHANGELOG.md docs/lint/MISSING-FEATURES.md
git commit -m "chore(lint): calibrate CK metric thresholds over src/ + docs #6"
```

---

### Task 7: Release v0.78.0-alpha (USER-GATED)

Standard release per `PLAN-v076-close-sections.md`. This is the final, user-gated step -- do not run it until Tasks 1-6 are merged and the user approves the release.

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:6` (VERSION const)
- Modify: `CHANGELOG.md` (move "Unreleased" -> `## v0.78.0-alpha`)

- [ ] **Step 1: Bump VERSION**

In `src/cli/DRagLint.CLI.pas`, set the VERSION const on line 6 to `0.78.0-alpha`.

- [ ] **Step 2: Roll the CHANGELOG**

In `CHANGELOG.md`, rename the "Unreleased" heading to `## v0.78.0-alpha` (dated 2026-07-02) and start a fresh empty "Unreleased".

- [ ] **Step 3: Pack both platforms**

Run:
```
pwsh -File build\pack-lint-release.ps1 -Version 0.78.0-alpha
third_party\dll-win64\drag-lint.exe --version
```
Expected: win64 + win32 zips built; the canonical exe reports `0.78.0-alpha`. (Note: `pack-lint-release.ps1` copies only win64 into `third_party\`, so `third_party\dll-win32\drag-lint.exe` stays stale -- verify the ZIP's exe, not that path.)

- [ ] **Step 4: Commit, tag, push, release**

```
git add src/cli/DRagLint.CLI.pas CHANGELOG.md
git commit -m "release: v0.78.0-alpha -- CK class metrics (NOC/DIT/CBO/RFC/LCOM4) #6"
git tag v0.78.0-alpha
git push origin main
git push origin v0.78.0-alpha
gh release create v0.78.0-alpha <win64.zip> <win32.zip> --prerelease --title "v0.78.0-alpha -- CK class metrics" --notes "DIT/NOC/CBO/RFC/LCOM4 class metrics (#6). See CHANGELOG."
```
Expected: GitHub prerelease created with both assets.

- [ ] **Step 5: Update BACKLOG + memory + wiki**

Update `docs/lint/BACKLOG.md` (new RESUME block: v0.78 shipped; NEXT = M2-flow nullability #4 + double-free #5), the auto-memory `MEMORY.md` pointer + `project_lint_rules_v062.md`, and the Obsidian wiki hot cache / entity note. Use the `handoff` skill for a clean boundary.

---

## Self-Review

**1. Spec coverage:**
- 5 metrics (DIT/NOC/CBO/RFC/LCOM4) -> Tasks 1-5. Covered.
- New unit `DRagLint.Lint.ClassMetrics`, two-phase, shared per-class gather -> Task 1 (inventory) + Tasks 2-5 (metrics read it). Covered.
- LCOM4 via AST re-walk + union-find -> Task 5. Covered.
- ON by default, `info`, category `metrics`, per-rule `threshold` -> catalog entries in each task; calibration Task 6. Covered.
- CLI lint-all path only (not LSP) -> Task 1 Step 6 wires only `DoLintAll`; no LSP change. Covered.
- Thresholds via `ThresholdFor` -> each task reads it; Task 6 finalizes. Covered.
- tests/lint-store cases per metric -> one per task. Covered.
- FP-sanity over src/ + docs (CHANGELOG, MISSING-FEATURES) -> Task 6. Covered.
- Release bundle -> Task 7. Covered.
- Documented limits (DIT/RTL, name-based, CBO efferent) -> CHANGELOG entry Task 6 Step 6. Covered.

**2. Placeholder scan:** No TBD/TODO. Every code step shows complete code; every command shows expected output. The single deliberate deferral (final threshold numbers) is an explicit calibration step (Task 6) with a measurement procedure, not a placeholder -- Tasks 1-5 use concrete provisional values that make their tests pass.

**3. Type consistency:**
- `TClassMetrics.Run(const AStore: ISymbolStore; const ACfg: TLintConfig; const ARuleId: string = '')` -- identical in unit decl (Task 1) and the `DoLintAll` call `TClassMetrics.Run(Store, Cfg, '')` (Task 1 Step 6). Consistent.
- Nested helpers referenced by later tasks (`GetRefs`, `InAnyMethodBody`, `InDeclSpan`, `Emit`, `WantRule`) are all defined in Task 1's unit body. Consistent.
- `TClassInfo` fields used by metrics (`Id, Name, FileId, Path, DeclLine, DeclCol, DeclEndLine, Heritage, Methods, Fields`) all defined in the Task 1 record. Consistent.
- Rule ids are stable across catalog entry, `ThresholdFor` key, `WantRule`, and `Emit`: `too-many-children`, `deep-inheritance`, `high-response`, `high-coupling`, `low-cohesion`. Consistent.
- Threshold default pairs (code `ThresholdFor` default == catalog `MkParam` default): 10/6/50/20/3 in Tasks 1-5, kept in lockstep in Task 6. Consistent.
