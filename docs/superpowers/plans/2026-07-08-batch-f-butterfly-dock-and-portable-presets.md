# Batch F -- Butterfly call-graph dock tab + portable naming presets -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a native in-IDE butterfly call-graph dock tab (callers + callees for the symbol under the cursor or selected in the Structure tab) and a save-your-own naming-preset feature persisted portably in `drag-lint.json`, released as v0.99.0-alpha.

**Architecture:** Reuse shipped engine primitives. F1 adds one thin engine builder (`BuildForwardCallTree`, mirroring the shipped `BuildReverseCallTree`) and a `--direction callers|callees` flag on the existing `reverse-calltree` CLI verb so ONE verb emits the same `reverse-calltree/1` JSON (with `file`+`line` per node) for both directions; the dock tab shells that verb twice and renders both halves in one read-only `TTreeView`. F2 extends the existing naming-preset combo with Save-as/Delete backed by a new `naming.presets` manifest key, reusing the existing direct-`System.JSON` read-modify-write path already used for `docs.max_return_cases`.

**Tech Stack:** Delphi 13 (RAD Studio 37), VCL, Open Tools API (OTA), `System.JSON`, PowerShell autotests, the drag-lint SQLite index + `ISymbolStore`.

## Global Constraints

- **Encoding:** all `.pas` / `.dfm` files strict 7-bit ASCII, no BOM, CRLF line endings. DocInsight `///` comments in ASCII too.
- **DocInsight (CDD):** every new public type/method/interface gets a `///` `<summary>`/`<param>`/`<returns>`/`<remarks>` spec-comment; the comment and the test must agree.
- **TDD:** for every engine/logic unit of work, write the failing test first, run it red, implement to green.
- **No new analysis engine:** F1 reuses `FindResolvedCallers` (callers) + `GetCallEdgesFromSymbol` (callees). The only new engine code is `BuildForwardCallTree`.
- **BPL build rule:** Win32 BPL rebuild via the delphi-build recipe (rsvars -> cd -> msbuild, PowerShell `Start-Process -Wait`, log redirect; check `BUILD_EXITCODE=0` + no `[dcc` `Error`). **RAD Studio MUST be closed** (BPL lock).
- **PROCESS RULE (carried from Batch E incident):** a subagent MUST NEVER close the user's RAD Studio. If the BPL is locked (`bds.exe` running / F2039 "Could not create output file"), STOP and report BLOCKED. Do not call `CloseMainWindow`, `taskkill`, or any IDE-terminating action.
- **CLI build:** Win64 Debug via the same rsvars+msbuild recipe (`src/cli/drag-lint.dproj`, `/p:Platform=Win64`); deploy to `src/cli/Win64/Debug/drag-lint.exe` AND `third_party/dll-win64/drag-lint.exe`.
- **Subagent report length:** append "Report in under 200 words." to research/lookup prompts (not to structured-data-returning ones).
- **YAGNI:** no CLI *reading* of `naming.presets` this batch; no editor right-click submenu (no OTA API in RAD 37); no static chart export (that is Track 5.3).

---

## File Structure

**F1 (butterfly):**
- `src/report/DRagLint.Report.RCallTree.pas` -- add `BuildForwardCallTree` (callees tree, same `TRCallNode`/`TRCallTree` shape).
- `src/cli/DRagLint.CLI.pas` -- add `--direction callers|callees` to the `reverse-calltree` verb (`DoReverseCallTree` + arg parse + usage line); default `callers` (back-compat). Callees branch calls `BuildForwardCallTree`.
- `src/delphi-plugin/DragLint.Plugin.DockForm.pas` -- new `FTabButterfly` tab + `TTreeView` + `PopulateButterfly(const AQName: string)` + double-click navigation.
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` -- `InvokeButterfly(Sender: TObject)` (shells the CLI twice, marshals to the tab).
- `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` -- Ctrl+Alt+B binding.
- `src/delphi-plugin/DragLint.Plugin.StructureForm.pas` -- selection -> `PopulateButterfly` hook.
- menu wiring for "Call Graph (Butterfly)..." (in Editor.pas menu build).
- `tests/autotest/run_forward_calltree.ps1` -- headless engine/CLI test.

**F2 (presets):**
- `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` -- combo growth + Save-as/Delete buttons + `naming.presets` RMW + preset-source merge + `DetectAndSetPreset`.
- `tests/autotest/run_naming_presets_roundtrip.ps1` -- headless manifest RMW test.

**Docs:** README, CHANGELOG, AI-USAGE / AI-INDEX-FIRST, INDEX-SCHEMA / manifest doc (naming.presets key).

---

## PHASE 1 -- F1 engine + CLI (headless, TDD)

### Task 1: `BuildForwardCallTree` engine

**Files:**
- Modify: `src/report/DRagLint.Report.RCallTree.pas`
- Test: `tests/autotest/run_forward_calltree.ps1` (added in Task 2; this task is engine + a compile-only check)

**Interfaces:**
- Consumes: `ISymbolStore.GetCallEdgesFromSymbol(AEnclosingSymbolId): TArray<TCallEdge>` (edge has `TargetSymbolId`, NO call-site line); `ISymbolStore.GetSymbolById(AId): TSymbol` (has `QualifiedName`, `FileId`, and a decl `Line`); `ISymbolStore.GetFilePath(AFileId): string`.
- Produces: `function BuildForwardCallTree(const AStore: ISymbolStore; ARootId: Int64; const AOpts: TRCallOptions): TRCallTree;` -- returns the SAME `TRCallTree`/`TRCallNode` record as `BuildReverseCallTree`. For a forward node, `Callers` holds the CALLEES (field name unchanged to avoid record churn; the direction is known by the caller). `Site`/`SiteFile`/`SiteLine` for a callee node point at the callee's OWN declaration (its file + decl line) since `TCallEdge` carries no call-site line.

- [ ] **Step 1: Add the DocInsight declaration to the interface section**

In `DRagLint.Report.RCallTree.pas`, directly after the existing `BuildReverseCallTree` declaration, add:

```pascal
/// <summary>Builds the N-deep FORWARD call tree rooted at ARootId: what the root
/// calls, what those call, ... The mirror of BuildReverseCallTree over
/// ISymbolStore.GetCallEdgesFromSymbol (outgoing edges). Same TRCallTree shape,
/// same global-visited cycle policy, same depth cap. For a callee node, Site is
/// '' , SiteFile is the callee's own declaring file (full path) and SiteLine is
/// the callee's declaration line (TCallEdge carries no call-site line, so
/// navigation targets the callee's definition). The record's Callers field holds
/// the CALLEES here (field name kept for record reuse). Borrows AStore; no I/O.</summary>
/// <param name="AStore">Open store (ids are per-DB).</param>
/// <param name="ARootId">Symbol id of the tree root.</param>
/// <param name="AOpts">Depth cap.</param>
/// <returns>The tree + summary. Root.Site is ''.</returns>
function BuildForwardCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;
```

- [ ] **Step 2: Implement `BuildForwardCallTree` in the implementation section**

Add after the existing `BuildReverseCallTree` implementation (before `end.`):

```pascal
function BuildForwardCallTree(const AStore: ISymbolStore; ARootId: Int64;
  const AOpts: TRCallOptions): TRCallTree;
var
  Visited: TDictionary<Int64, Boolean>;
  Sum    : TRCallSummary;

  function Expand(AId: Int64; ADepth, ALevel: Integer): TRCallNode;
  var
    Edges : TArray<TCallEdge>;
    E     : TCallEdge;
    Kids  : TList<TRCallNode>;
    Sym    : TSymbol;
    SeenChild: TDictionary<Int64, Boolean>;
  begin
    Result := Default(TRCallNode);
    Sym := AStore.GetSymbolById(AId);
    Result.QName    := Sym.QualifiedName;
    Result.Site     := '';
    { Callee node navigates to the callee's OWN declaration (no call-site line on
      the edge). SiteFile = declaring file; SiteLine = decl line. }
    Result.SiteFile := AStore.GetFilePath(Sym.FileId);
    Result.SiteLine := Sym.Line;
    Inc(Sum.NodeCount);
    if ALevel > Sum.MaxDepthReached then Sum.MaxDepthReached := ALevel;
    if Visited.ContainsKey(AId) then
    begin
      Result.Cycle := True;
      Inc(Sum.CycleCount);
      Exit;
    end;
    Visited.Add(AId, True);
    if ADepth <= 0 then Exit;
    Edges := AStore.GetCallEdgesFromSymbol(AId);
    if Length(Edges) = 0 then Exit;
    Kids := TList<TRCallNode>.Create;
    SeenChild := TDictionary<Int64, Boolean>.Create;
    try
      if ADepth = 1 then Sum.Truncated := True;
      for E in Edges do
      begin
        if E.TargetSymbolId <= 0 then Continue;
        if SeenChild.ContainsKey(E.TargetSymbolId) then Continue; { dedup sibling edges }
        SeenChild.Add(E.TargetSymbolId, True);
        Kids.Add(Expand(E.TargetSymbolId, ADepth - 1, ALevel + 1));
      end;
      Result.Callers := Kids.ToArray;
    finally
      SeenChild.Free;
      Kids.Free;
    end;
  end;

begin
  Sum := Default(TRCallSummary);
  Visited := TDictionary<Int64, Boolean>.Create;
  try
    Result.Root := Expand(ARootId, AOpts.Depth, 0);
    Result.Summary := Sum;
  finally
    Visited.Free;
  end;
end;
```

Note: `Sum.Truncated := True` when `ADepth = 1` matches the reverse builder's "children reached but their children cut" convention; refine to only set when a child actually has edges is NOT required (reverse builder is equally coarse). Add `DRagLint.Core.Model` to the uses if `TCallEdge`/`TSymbol` are not already visible (they are used by `BuildReverseCallTree` already -> uses is fine; verify no new unit needed).

- [ ] **Step 3: Compile the CLI to confirm the engine unit builds**

Run the CLI Win64 Debug build (delphi-build recipe). Expected: `BUILD_EXITCODE=0`, no `[dcc` `Error`. (The engine has no standalone test harness; Task 2's CLI test exercises it.)

- [ ] **Step 4: Commit**

```bash
git add src/report/DRagLint.Report.RCallTree.pas
git commit -m "feat(engine): BuildForwardCallTree -- forward (callee) call tree mirroring the reverse builder"
```

---

### Task 2: `reverse-calltree --direction callers|callees` CLI flag + forward-tree JSON

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (arg parse for `--direction` already exists for `callgraph` -- REUSE `TArgs.Direction`; `DoReverseCallTree`; the `reverse-calltree` usage line)
- Test: `tests/autotest/run_forward_calltree.ps1`

**Interfaces:**
- Consumes: `BuildForwardCallTree` (Task 1); the existing `TArgs.Direction` field (default `'callees'` for callgraph, but the `reverse-calltree` verb must default to `'callers'` for back-compat) ; the existing `BuildNodeJson`/`BuildTreeJson`/`BuildSummaryJson` local functions in `DoReverseCallTree` (schema `reverse-calltree/1`).
- Produces: `drag-lint reverse-calltree --qname X [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] --db PATH` -- with `--direction callees` it builds via `BuildForwardCallTree`; JSON is the SAME `reverse-calltree/1` object (root/callers/summary + per-node qname/site/file/line/cycle). Default direction = `callers` (unchanged output for existing callers).

- [ ] **Step 1: Write the failing test `tests/autotest/run_forward_calltree.ps1`**

```powershell
# run_forward_calltree.ps1 -- reverse-calltree --direction callees emits reverse-calltree/1 JSON with file+line per node
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'
$db  = Join-Path $PSScriptRoot 'fixtures\forward_calltree\forward.sqlite'  # built in Step 3
$fail = 0

function Check($cond, $msg) { if (-not $cond) { Write-Host "FAIL: $msg"; $script:fail++ } else { Write-Host "PASS: $msg" } }

# A root that calls at least one other routine in the fixture.
$json = & $exe reverse-calltree --qname 'Forward.TRoot.Drive' --direction callees --depth 3 --format json --db $db
$obj = $json | ConvertFrom-Json
Check ($obj.schema -eq 'reverse-calltree/1') 'schema is reverse-calltree/1'
Check ($null -ne $obj.root) 'has root'
Check ($obj.root.callers.Count -ge 1) 'root has >=1 callee node'
$first = $obj.root.callers[0]
Check ($first.qname -ne '') 'callee node has qname'
Check ($first.file -ne '') 'callee node has file (navigable)'
Check ($first.line -ge 1) 'callee node has line >=1'

# Back-compat: default direction (callers) still works and differs from callees.
$jc = & $exe reverse-calltree --qname 'Forward.TRoot.Drive' --depth 2 --format json --db $db | ConvertFrom-Json
Check ($jc.schema -eq 'reverse-calltree/1') 'default (callers) still reverse-calltree/1'

if ($fail -gt 0) { Write-Host "RESULT: FAIL ($fail)"; exit 1 } else { Write-Host 'RESULT: PASS'; exit 0 }
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `powershell -File tests/autotest/run_forward_calltree.ps1`
Expected: FAIL (either the fixture DB is missing, or `--direction callees` is ignored and returns callers). This proves the test has teeth.

- [ ] **Step 3: Create the fixture + index it**

Create `tests/autotest/fixtures/forward_calltree/forward.pas` (ASCII/CRLF):

```pascal
unit Forward;

interface

type
  TRoot = class
    procedure Drive;
    procedure StepA;
    procedure StepB;
  end;

implementation

procedure TRoot.StepA;
begin
end;

procedure TRoot.StepB;
begin
  StepA;
end;

procedure TRoot.Drive;
begin
  StepA;
  StepB;
end;

end.
```

Index it (deep, so call edges are captured):

```bash
third_party/dll-win64/drag-lint.exe index tests/autotest/fixtures/forward_calltree --db tests/autotest/fixtures/forward_calltree/forward.sqlite --deep
```

(If `--deep` is not the flag name for capturing call edges, use the flag the existing `run_reverse_calltree.ps1` fixture uses -- match that script's index invocation exactly.)

- [ ] **Step 4: Add `--direction` handling to `DoReverseCallTree`**

In `src/cli/DRagLint.CLI.pas`, in `DoReverseCallTree`: after the qname/db resolution and before building the tree, read the direction. `TArgs.Direction` already parses from `--direction` (shared with callgraph). Because `Result.Direction` defaults to `'callees'` for callgraph, but `reverse-calltree` must default to `callers`, treat an EMPTY-or-absent `--direction` as `callers` for THIS verb:

```pascal
var Dir: string := LowerCase(Trim(AArgs.Direction));
// reverse-calltree historically = callers; only 'callees' switches direction.
// (callgraph sets Direction default 'callees', so do NOT trust the default here;
//  the reverse-calltree verb is invoked without --direction in the common case.)
if (Dir <> 'callers') and (Dir <> 'callees') then Dir := 'callers';
```

Then build with the matching builder:

```pascal
var Tree: TRCallTree;
if Dir = 'callees' then
  Tree := BuildForwardCallTree(Store, RootId, Opts)
else
  Tree := BuildReverseCallTree(Store, RootId, Opts);
```

Replace the existing single `BuildReverseCallTree` call with this branch. Add `DRagLint.Report.RCallTree` is already in uses (the verb uses it). No other change to the JSON/text/dot/mermaid emit -- they consume `Tree` uniformly.

IMPORTANT back-compat guard: the arg parser must NOT let callgraph's `Direction` default of `'callees'` leak into reverse-calltree. Confirm by reading the parser: `Result.Direction := 'callees'` at line ~505 is a GLOBAL default. Therefore the `if (Dir <> 'callers') and (Dir <> 'callees')` fallback above is INSUFFICIENT (an unset `--direction` yields `'callees'`, flipping the default!). FIX: change the global default to empty string and let each verb apply its own default:
- Change line ~505 `Result.Direction := 'callees';` to `Result.Direction := '';`
- In `DoCallGraph`, where it validates direction, treat empty as `'callees'` (its historic default): add `if AArgs.Direction = '' then Dir := 'callees'` in that verb's local handling (mirror the reverse-calltree pattern). Verify `DoCallGraph`'s existing validation (`--direction must be callers|callees`) still passes for the empty->callees case.

- [ ] **Step 5: Update the `reverse-calltree` usage line**

Change the usage `Writeln` (line ~395) to include `[--direction callers|callees]`:

```pascal
  Writeln('  drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...]   (N-deep call tree; callers=who calls X (default), callees=what X calls; cycle-guarded)');
```

- [ ] **Step 6: Rebuild the CLI (Win64 Debug), deploy, run the test to green**

Build (delphi-build recipe, `/p:Platform=Win64`, `src/cli/drag-lint.dproj`). Deploy the exe to `src/cli/Win64/Debug/` and `third_party/dll-win64/`.
Run: `powershell -File tests/autotest/run_forward_calltree.ps1`
Expected: `RESULT: PASS`.

- [ ] **Step 7: Regression -- run the existing reverse-calltree test**

Run: `powershell -File tests/autotest/run_reverse_calltree.ps1`
Expected: still PASS (callers default unchanged).

- [ ] **Step 8: Commit**

```bash
git add src/cli/DRagLint.CLI.pas tests/autotest/run_forward_calltree.ps1 tests/autotest/fixtures/forward_calltree
git commit -m "feat(cli): reverse-calltree --direction callers|callees (callees via BuildForwardCallTree); default callers preserved"
```

---

## PHASE 2 -- F1 IDE dock tab + invocation (BPL; live-smoke, no headless UI test)

> Every task below rebuilds the Win32 BPL. **PROCESS RULE: never close RAD Studio; if `bds.exe` is running / F2039, STOP and report BLOCKED.**

### Task 3: Butterfly dock tab (`FTabButterfly` + tree + navigation)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.DockForm.pas`

**Interfaces:**
- Consumes: existing `AddTab(const ACaption: string): TTabSheet`; `FPages: TPageControl`; the `StructureForm` `TTreeView` idiom (ReadOnly/ShowLines/OnDblClick) for reference.
- Produces: `procedure TDragLintDockFrame.PopulateButterfly(const AQName, ACallersJson, ACalleesJson: string);` -- fills the tab's tree from two `reverse-calltree/1` JSON strings (callers + callees) and selects the tab; `procedure SelectButterflyTab;`. Both public so Editor.pas can call them. Global `GDockFrame` (already captured) is the access handle.

- [ ] **Step 1: Declare the tab, tree, and methods**

In the `TDragLintDockFrame` private fields (near `FTabStruct`/`FTabGraph`), add:

```pascal
      FTabButterfly  : TTabSheet   ;
      FButterflyTree : TTreeView   ;
```

In the public section add:

```pascal
      /// <summary>Fills the Call Graph (butterfly) tab from two reverse-calltree/1
      /// JSON documents -- ACallersJson (who calls AQName) under a "Callers (N)"
      /// root and ACalleesJson (what AQName calls) under a "Callees (N)" root --
      /// then selects the tab. Empty/failed JSON yields a "(0)" root, never an
      /// error. Double-clicking a node with a file jumps to file:line.</summary>
      procedure PopulateButterfly(const AQName, ACallersJson, ACalleesJson: string);
      /// <summary>Brings the Call Graph tab to the front.</summary>
      procedure SelectButterflyTab;
```

Add `Vcl.ComCtrls` (TTreeView/TTabSheet), `System.JSON` to the unit uses if absent.

- [ ] **Step 2: Create the tab + tree in the constructor**

Where the other tabs are created (`FTabStruct := AddTab('Structure')` ... block, ~line 225), add:

```pascal
  FTabButterfly := AddTab('Call Graph');
  FButterflyTree := TTreeView.Create(Self);
  FButterflyTree.Parent        := FTabButterfly;
  FButterflyTree.Align         := alClient;
  FButterflyTree.ReadOnly      := True;
  FButterflyTree.ShowLines     := True;
  FButterflyTree.HideSelection := False;
  FButterflyTree.OnDblClick    := ButterflyTreeDblClick;
```

- [ ] **Step 3: Implement the JSON-walk populate + a helper**

Add a private helper that walks a `reverse-calltree/1` root's `callers` array into tree nodes (each node text `qname` + optional ` (cycle)`; store `file` and `line` in the node via a small record pointer or `TStringList`-encoded `Data`). Simplest robust approach: attach `file|line` as a string in `TTreeNode.Data` via an owned `TStringList`-free scheme -- instead, keep a parallel `TList` OR encode `file` + `#9` + `line` in a heap `PChar`. To avoid manual memory management, use `FButterflyTree.Items.AddChildObject(parent, text, TObject)` with a small `TNav = class FFile: string; FLine: Integer end` owned in a `FNavList: TObjectList<TNav>` field freed in destructor.

```pascal
type
  TNav = class
    FFile: string;
    FLine: Integer;
    constructor Create(const AFile: string; ALine: Integer);
  end;
```

Field: `FNavList: TObjectList<TNav>;` (create in ctor, free in dtor). Populate:

```pascal
procedure TDragLintDockFrame.PopulateButterfly(const AQName, ACallersJson, ACalleesJson: string);

  function ParseRoot(const AJson: string): TJSONObject;
  var V: TJSONValue; R: TJSONObject;
  begin
    Result := nil;
    if Trim(AJson) = '' then Exit;
    V := nil;
    try V := TJSONObject.ParseJSONValue(AJson); except V := nil; end;
    if (V is TJSONObject) and TJSONObject(V).TryGetValue<TJSONObject>('root', R) then
      Result := R  { R is owned by V; caller must keep V alive -- see note }
    else if V <> nil then V.Free;
  end;

  procedure WalkArray(const AArr: TJSONArray; AParent: TTreeNode);
  var i: Integer; Obj: TJSONObject; QN, F: string; Ln: Integer; Cyc: Boolean;
      Node: TTreeNode; Nav: TNav; Kids: TJSONArray;
  begin
    if AArr = nil then Exit;
    for i := 0 to AArr.Count - 1 do
    begin
      if not (AArr.Items[i] is TJSONObject) then Continue;
      Obj := AArr.Items[i] as TJSONObject;
      QN  := Obj.GetValue<string>('qname', '');
      F   := Obj.GetValue<string>('file', '');
      Ln  := Obj.GetValue<Integer>('line', 0);
      Cyc := False; Obj.TryGetValue<Boolean>('cycle', Cyc);
      if Cyc then QN := QN + ' (cycle)';
      Nav := TNav.Create(F, Ln); FNavList.Add(Nav);
      Node := FButterflyTree.Items.AddChildObject(AParent, QN, Nav);
      if (not Cyc) and Obj.TryGetValue<TJSONArray>('callers', Kids) then
        WalkArray(Kids, Node);
    end;
  end;

var
  CallersV, CalleesV: TJSONValue;
  CallersRoot, CalleesRoot: TJSONObject;
  RootCallers, RootCallees: TTreeNode;
  Arr: TJSONArray;
  NC, NF: Integer;
begin
  FButterflyTree.Items.BeginUpdate;
  try
    FButterflyTree.Items.Clear;
    FNavList.Clear;  { frees prior TNav objects (OwnsObjects=True) }

    CallersV := nil; CalleesV := nil;
    try CallersV := TJSONObject.ParseJSONValue(ACallersJson); except CallersV := nil; end;
    try CalleesV := TJSONObject.ParseJSONValue(ACalleesJson); except CalleesV := nil; end;
    try
      CallersRoot := nil; CalleesRoot := nil;
      if CallersV is TJSONObject then TJSONObject(CallersV).TryGetValue<TJSONObject>('root', CallersRoot);
      if CalleesV is TJSONObject then TJSONObject(CalleesV).TryGetValue<TJSONObject>('root', CalleesRoot);

      NC := 0;
      if (CallersRoot <> nil) and CallersRoot.TryGetValue<TJSONArray>('callers', Arr) then NC := Arr.Count;
      RootCallers := FButterflyTree.Items.Add(nil, Format('Callers of %s (%d)', [AQName, NC]));
      if (CallersRoot <> nil) and CallersRoot.TryGetValue<TJSONArray>('callers', Arr) then WalkArray(Arr, RootCallers);

      NF := 0;
      if (CalleesRoot <> nil) and CalleesRoot.TryGetValue<TJSONArray>('callers', Arr) then NF := Arr.Count;
      RootCallees := FButterflyTree.Items.Add(nil, Format('Callees of %s (%d)', [AQName, NF]));
      if (CalleesRoot <> nil) and CalleesRoot.TryGetValue<TJSONArray>('callers', Arr) then WalkArray(Arr, RootCallees);

      RootCallers.Expand(True);
      RootCallees.Expand(True);
    finally
      CallersV.Free;
      CalleesV.Free;
    end;
  finally
    FButterflyTree.Items.EndUpdate;
  end;
  SelectButterflyTab;
end;
```

(Note: the local `ParseRoot` helper above is illustrative; the final code uses the inlined parse in the body. Remove `ParseRoot` if unused to avoid a hint.)

- [ ] **Step 4: Implement `SelectButterflyTab` + double-click nav + `TNav`/ctor/dtor**

```pascal
procedure TDragLintDockFrame.SelectButterflyTab;
begin
  if (FPages <> nil) and (FTabButterfly <> nil) then FPages.ActivePage := FTabButterfly;
end;

constructor TNav.Create(const AFile: string; ALine: Integer);
begin inherited Create; FFile := AFile; FLine := ALine; end;

procedure TDragLintDockFrame.ButterflyTreeDblClick(Sender: TObject);
var N: TTreeNode; Nav: TNav;
begin
  N := FButterflyTree.Selected;
  if N = nil then Exit;
  if not (TObject(N.Data) is TNav) then Exit;
  Nav := TNav(N.Data);
  if (Nav.FFile <> '') and (Nav.FLine > 0) then
    OpenFileAtLine(Nav.FFile, Nav.FLine);  { reuse the existing nav helper (see Step 5) }
end;
```

In the constructor: `FNavList := TObjectList<TNav>.Create(True);`. In the destructor: `FNavList.Free;` (add a destructor if none exists; otherwise fold in). Declare `ButterflyTreeDblClick(Sender: TObject);` private.

- [ ] **Step 5: Wire navigation to the existing open-at-line helper**

Find how `StructureForm`/`DockForm` already opens a file at a line on double-click (grep `OpenFile`/`GetTopMostEditView`/`IOTAModuleServices.OpenModule`/`GxOtaGoToFileLineColumn`). Reuse that exact helper as `OpenFileAtLine(const AFile: string; ALine: Integer)`; if it lives in another unit, add it to uses. Do NOT hand-roll editor navigation -- copy the proven idiom.

- [ ] **Step 6: Build the BPL (RAD Studio CLOSED), confirm 0 errors**

delphi-build recipe -> `dclDragLintWizard.dproj` Win32 Debug. Expected `BUILD_EXITCODE=0`, no `[dcc32 Error]`. **If `bds.exe` is running: STOP, report BLOCKED.** Auto-deploys to `third_party/dll-win32/`.

- [ ] **Step 7: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.DockForm.pas
git commit -m "feat(ide): butterfly Call Graph dock tab -- callers+callees TTreeView with double-click navigation"
```

---

### Task 4: `InvokeButterfly` editor action + menu + Ctrl+Alt+B

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (action + menu wiring)
- Modify: `src/delphi-plugin/DragLint.Plugin.Keyboard.pas` (Ctrl+Alt+B)

**Interfaces:**
- Consumes: `RunAndCaptureStdout`, `GetActiveProjectDb`, `DLAskQName`, `DLExe64`, `DLT` (all in Editor.pas, used by `InvokeReverseCallTreeMessages`); `GDockFrame.PopulateButterfly` / `EnsureDockVisible` (whatever the reverse-calltree/structure actions use to surface the dock).
- Produces: `procedure InvokeButterfly(Sender: TObject);` (interface + impl); a menu item "Call Graph (Butterfly)..." under Uses & Dependencies; a `ButterflyKey` handler in Keyboard.pas bound to Ctrl+Alt+B.

- [ ] **Step 1: Declare `InvokeButterfly` in the interface**

In `DragLint.Plugin.Editor.pas` interface, near `InvokeReverseCallTreeMessages`:

```pascal
/// <summary>Builds the butterfly call graph (callers + callees) for the symbol
/// under the caret (prompts for a qname) and shows it in the dock's Call Graph
/// tab. Shells drag-lint reverse-calltree --format json twice (callers, then
/// --direction callees) on a background thread, then marshals both JSON docs to
/// the dock via TThread.Queue. Bound to Ctrl+Alt+B and a Uses &amp; Dependencies
/// menu item.</summary>
procedure InvokeButterfly(Sender: TObject);
```

- [ ] **Step 2: Implement `InvokeButterfly` (mirror `InvokeReverseCallTreeMessages`)**

```pascal
procedure InvokeButterfly(Sender: TObject);
var
  Q : string;
  Db: string;
begin
  Db := GetActiveProjectDb;
  if Db = '' then begin ShowMessage('drag-lint: no project index.'); Exit; end;
  if not DLAskQName(Q) then Exit;
  ShowButterflyForQName(Q, Db);
end;
```

Factor the shell-and-marshal into a shared `ShowButterflyForQName(const AQName, ADb: string)` so the Structure-tab path (Task 5) reuses it:

```pascal
procedure ShowButterflyForQName(const AQName, ADb: string);
var
  CmdC, CmdF: string;
begin
  CmdC := Format('"%s" reverse-calltree --qname "%s" --db "%s" --depth 3 --format json', [DLExe64, AQName, ADb]);
  CmdF := Format('"%s" reverse-calltree --qname "%s" --db "%s" --depth 3 --format json --direction callees', [DLExe64, AQName, ADb]);
  DLT('menu', 'butterfly(async): ' + CmdC + ' | ' + CmdF);
  TThread.CreateAnonymousThread(
    procedure
    var CallersOut, CalleesOut: string;
    begin
      CallersOut := ''; CalleesOut := '';
      try RunAndCaptureStdout(CmdC, CallersOut, 180000); except CallersOut := ''; end;
      try RunAndCaptureStdout(CmdF, CalleesOut, 180000); except CalleesOut := ''; end;
      var SC: string := SliceJsonBracket(CallersOut, '{', '}');
      var SF: string := SliceJsonBracket(CalleesOut, '{', '}');
      TThread.Queue(nil,
        procedure
        begin
          if GDockFrame = nil then Exit;
          GDockFrame.PopulateButterfly(AQName, SC, SF);
        end);
    end).Start;
end;
```

Declare `ShowButterflyForQName` in the interface too (Task 5 in StructureForm needs it, OR expose via the dock -- keep it in Editor.pas interface and have StructureForm call it). Ensure the dock is visible first: if the reverse-calltree/structure actions call something like `EnsureDockWindowVisible`, call it before `PopulateButterfly` (grep for the dock-show helper the "Show Structure" action uses; reuse it).

- [ ] **Step 3: Add the menu item**

Find where "Reverse Call Tree (clickable, Messages window)..." is added to the Uses & Dependencies submenu (grep `Reverse Call Tree`). Add a sibling:

```pascal
AddMenuProc(UsesDepSub, 'Call Graph (Butterfly)...', InvokeButterfly);
```

(match the exact `AddMenu*` helper + parent-item variable used there).

- [ ] **Step 4: Add the Ctrl+Alt+B keybinding**

In `DragLint.Plugin.Keyboard.pas`:
- Add a handler (near `ReverseCallTreeKey`, ~line 195):

```pascal
{ Batch F: Ctrl+Alt+B -- butterfly call graph for the symbol under the caret. }
procedure TDragLintKeyboardBinding.ButterflyKey(const Context: IOTAKeyContext;
  KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
begin
  InvokeButterfly(nil);
  BindingResult := krHandled;
end;
```

(match the EXACT signature of the existing `ReverseCallTreeKey` -- copy its declaration form.)
- Register it in `BindKeyboard` (near line 110):

```pascal
  BindingServices.AddKeyBinding( [ShortCut(Ord('B'), [ssCtrl, ssAlt])], ButterflyKey, nil);
```

- Declare `ButterflyKey` in the class (mirror `ReverseCallTreeKey`'s declaration). The Editor-unit forward decl for `InvokeButterfly` is needed exactly as Ctrl+Alt+K needed one for `InvokeReverseCallTreeMessages` -- add `InvokeButterfly` to whatever interface/forward mechanism Keyboard.pas uses to see Editor.pas actions.

- [ ] **Step 5: Build the BPL (RAD Studio CLOSED)**

delphi-build recipe -> Win32. Expected 0 errors. **If `bds.exe` running: STOP, report BLOCKED.**

- [ ] **Step 6: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas src/delphi-plugin/DragLint.Plugin.Keyboard.pas
git commit -m "feat(ide): InvokeButterfly action -- Ctrl+Alt+B + Uses & Dependencies menu -> Call Graph tab"
```

---

### Task 5: Structure-tab selection -> butterfly

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.StructureForm.pas`

**Interfaces:**
- Consumes: `StructureForm`'s existing `EnumQNameForNode(ANode: TTreeNode): string` (or the equivalent selection->qname helper -- grep to confirm the exact name); the active project DB accessor the StructureForm already uses; `ShowButterflyForQName` (Task 4, Editor.pas interface).
- Produces: on a symbol node selection/right-click, call `ShowButterflyForQName(QName, Db)`. Preference: a context-menu item "Show in Call Graph" on the structure tree's popup (safer than hijacking single-click; avoids the Batch D T9 dock-focus concern).

- [ ] **Step 1: Add a popup item to the structure tree**

Find `FPopup` construction in StructureForm (grep `FPopup`). Add an item:

```pascal
AddPopupItem(FPopup, 'Show in Call Graph', ShowInButterflyClick);
```

(match the existing popup-item-add idiom; if items are `TMenuItem.Create` + `FPopup.Items.Add`, follow that.)

- [ ] **Step 2: Implement the handler**

```pascal
procedure TDragLintStructureForm.ShowInButterflyClick(Sender: TObject);
var QN, Db: string;
begin
  if FTree.Selected = nil then Exit;
  QN := EnumQNameForNode(FTree.Selected);   { confirm exact helper name }
  if QN = '' then Exit;
  Db := ActiveDbForStructure;               { confirm exact accessor the form already uses }
  if Db = '' then Exit;
  ShowButterflyForQName(QN, Db);
end;
```

Add `DragLint.Plugin.Editor` to the uses (for `ShowButterflyForQName`). If that creates a circular unit reference (Editor already uses StructureForm indirectly), route the call through the dock instead: add a thin `TDragLintDockFrame.RequestButterfly(const AQName, ADb: string)` that calls `ShowButterflyForQName`, and have StructureForm call `GDockFrame.RequestButterfly`. Choose whichever avoids a uses cycle -- verify by compiling.

- [ ] **Step 3: Guard against dock self-focus (Batch D T9 lesson)**

`ShowButterflyForQName` already selects the Call Graph tab via `PopulateButterfly` -> `SelectButterflyTab`. That is user-initiated (a popup click), so it is acceptable to surface. Do NOT add any OnActivate/auto-select that fires on mere tree navigation.

- [ ] **Step 4: Build the BPL (RAD Studio CLOSED)**

delphi-build -> Win32. 0 errors. **If `bds.exe` running: STOP, report BLOCKED.**

- [ ] **Step 5: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.StructureForm.pas src/delphi-plugin/DragLint.Plugin.DockForm.pas
git commit -m "feat(ide): Structure tab 'Show in Call Graph' popup -> butterfly tab"
```

---

## PHASE 3 -- F2 save-your-own naming presets

### Task 6: `naming.presets` manifest round-trip (headless test + write/read helpers)

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas` (add `ReadNamingPresets`/`WriteNamingPreset`/`DeleteNamingPreset` helpers)
- Test: `tests/autotest/run_naming_presets_roundtrip.ps1`

**Interfaces:**
- Consumes: the existing `ManifestPathForWrite`-style resolver (it lives in OptionsFrames.pas for the Linter page; LintOptionsFrame is the DOCK frame -- confirm whether LintOptionsFrame has its own manifest-path resolver or must add one mirroring `ManifestPathForWrite`: dotted `.drag-lint.json` beside the active `.dproj` when a project is open, else undotted beside `DragLintExe`). The RMW idiom is `WriteMaxReturnCases` in OptionsFrames.pas -- copy its read-modify-write shape (ParseJSONValue, reuse/create nested object, RemovePair-before-AddPair, `TFile.WriteAllText(..., TEncoding.UTF8)`).
- Produces (Pascal):
  - `type TNamingPreset = record Name: string; Values: array[0..7] of string; end;`
  - `function ReadNamingPresets: TArray<TNamingPreset>;`
  - `procedure WriteNamingPreset(const APreset: TNamingPreset);` (overwrite by Name)
  - `procedure DeleteNamingPreset(const AName: string);`
  The 8 `Values` map to `NAMING_PRESET_PARAMS` in order.

- [ ] **Step 1: Write the failing test `run_naming_presets_roundtrip.ps1`**

The IDE helpers are not headless-callable, so this test validates the SAME manifest shape via a pure PowerShell RMW, asserting the contract the Pascal code must match (schema teeth + sibling-key preservation). It doubles as the manifest-format spec.

```powershell
# run_naming_presets_roundtrip.ps1 -- naming.presets survives RMW; docs/settings siblings preserved
$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:TEMP ("draglint-presets-{0}.json" -f (Get-Random))
$fail = 0
function Check($c,$m){ if(-not $c){Write-Host "FAIL: $m";$script:fail++}else{Write-Host "PASS: $m"} }

# Seed a manifest with sibling keys.
@'
{ "settings": { "deep": true }, "docs": { "max_return_cases": 20 } }
'@ | Set-Content -Encoding utf8 $tmp

# Simulate WriteNamingPreset("My", [p,F,T,E,I,P,PascalCase,PascalCase]) via the same RMW contract.
$j = Get-Content -Raw $tmp | ConvertFrom-Json
if (-not $j.naming) { $j | Add-Member naming (@{}) -Force }
$preset = [ordered]@{ name='My'; values=[ordered]@{
  param_prefix='p'; field_prefix='F'; class_prefix='T'; exception_prefix='E';
  interface_prefix='I'; pointer_prefix='P'; method_case='PascalCase'; local_case='PascalCase' } }
$j.naming | Add-Member presets @($preset) -Force
($j | ConvertTo-Json -Depth 8) | Set-Content -Encoding utf8 $tmp

# Read back.
$r = Get-Content -Raw $tmp | ConvertFrom-Json
Check ($r.naming.presets.Count -eq 1) 'one saved preset'
Check ($r.naming.presets[0].name -eq 'My') 'preset name survives'
Check ($r.naming.presets[0].values.param_prefix -eq 'p') 'param_prefix survives'
Check ($r.docs.max_return_cases -eq 20) 'docs sibling preserved'
Check ($r.settings.deep -eq $true) 'settings sibling preserved'

Remove-Item $tmp -Force
if ($fail -gt 0){Write-Host "RESULT: FAIL ($fail)";exit 1}else{Write-Host 'RESULT: PASS';exit 0}
```

- [ ] **Step 2: Run it -- it should PASS immediately** (it validates the format contract, not Pascal code). If it fails, the format contract is wrong -- fix the test/contract before writing Pascal. This is the spec the Pascal RMW must satisfy.

Run: `powershell -File tests/autotest/run_naming_presets_roundtrip.ps1`
Expected: `RESULT: PASS`.

- [ ] **Step 3: Implement the Pascal helpers mirroring the contract**

Add to `DragLint.Plugin.LintOptionsFrame.pas`. First confirm the manifest path resolver: grep for an existing `ManifestPathForWrite`/project-dir helper in this unit; if absent, add one identical to `OptionsFrames.pas`'s (dotted `.drag-lint.json` beside active `.dproj`; else undotted beside `DragLintExe`). Then:

```pascal
type
  TNamingPreset = record
    Name  : string;
    Values: array[0..7] of string;
  end;

function TDragLintLintOptionsFrame.ReadNamingPresets: TArray<TNamingPreset>;
var
  Path: string; Parsed: TJSONValue; Root, Naming: TJSONObject;
  Arr: TJSONArray; i, k: Integer; Obj, Vals: TJSONObject; P: TNamingPreset;
  Res: TList<TNamingPreset>;
begin
  SetLength(Result, 0);
  Path := ManifestPathForWrite;
  if (Path = '') or not TFile.Exists(Path) then Exit;
  Parsed := nil;
  try Parsed := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path)); except Parsed := nil; end;
  if not (Parsed is TJSONObject) then begin Parsed.Free; Exit; end;
  Root := TJSONObject(Parsed);
  Res := TList<TNamingPreset>.Create;
  try
    if Root.TryGetValue<TJSONObject>('naming', Naming)
       and Naming.TryGetValue<TJSONArray>('presets', Arr) then
      for i := 0 to Arr.Count - 1 do
        if Arr.Items[i] is TJSONObject then
        begin
          Obj := Arr.Items[i] as TJSONObject;
          P.Name := Obj.GetValue<string>('name', '');
          if Obj.TryGetValue<TJSONObject>('values', Vals) then
            for k := 0 to 7 do
              P.Values[k] := Vals.GetValue<string>(NAMING_PRESET_PARAMS[k], '');
          if P.Name <> '' then Res.Add(P);
        end;
    Result := Res.ToArray;
  finally
    Res.Free;
    Root.Free;
  end;
end;
```

`WriteNamingPreset` (RMW, overwrite by name -- mirror `WriteMaxReturnCases`):

```pascal
procedure TDragLintLintOptionsFrame.WriteNamingPreset(const APreset: TNamingPreset);
var
  Path: string; Parsed: TJSONValue; Root, Naming, ValsObj, ExistingObj: TJSONObject;
  Arr, NewArr: TJSONArray; i, k: Integer; Nm: string;
begin
  Path := ManifestPathForWrite;
  if Path = '' then Exit;
  Root := nil;
  try
    if TFile.Exists(Path) then
    begin
      Parsed := nil;
      try Parsed := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path)); except Parsed := nil; end;
      if Parsed is TJSONObject then Root := TJSONObject(Parsed) else Parsed.Free;
    end;
    if Root = nil then Root := TJSONObject.Create;

    { reuse or create "naming" }
    if not Root.TryGetValue<TJSONObject>('naming', Naming) then
    begin Naming := TJSONObject.Create; Root.AddPair('naming', Naming); end;

    { rebuild the presets array minus any same-named entry, then append the new one }
    NewArr := TJSONArray.Create;
    if Naming.TryGetValue<TJSONArray>('presets', Arr) then
      for i := 0 to Arr.Count - 1 do
        if Arr.Items[i] is TJSONObject then
        begin
          ExistingObj := Arr.Items[i] as TJSONObject;
          Nm := ExistingObj.GetValue<string>('name', '');
          if not SameText(Nm, APreset.Name) then
            NewArr.AddElement(ExistingObj.Clone as TJSONObject);
        end;
    ValsObj := TJSONObject.Create;
    for k := 0 to 7 do ValsObj.AddPair(NAMING_PRESET_PARAMS[k], APreset.Values[k]);
    var NewObj: TJSONObject := TJSONObject.Create;
    NewObj.AddPair('name', APreset.Name);
    NewObj.AddPair('values', ValsObj);
    NewArr.AddElement(NewObj);

    (Naming.RemovePair('presets')).Free;  { nil-safe }
    Naming.AddPair('presets', NewArr);

    TFile.WriteAllText(Path, Root.ToJSON, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;
```

`DeleteNamingPreset` = same shape, rebuilding the array minus `AName` and NOT appending. (Write it out fully in the implementer's edit -- do not `{ ...like WriteNamingPreset... }`.)

- [ ] **Step 4: Compile the BPL (RAD Studio CLOSED) to confirm the helpers build**

delphi-build -> Win32, 0 errors. **If `bds.exe` running: STOP, report BLOCKED.**

- [ ] **Step 5: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas tests/autotest/run_naming_presets_roundtrip.ps1
git commit -m "feat(ide): naming.presets manifest read/write/delete helpers + round-trip contract test"
```

---

### Task 7: Presets combo growth + Save-as/Delete UI + apply/detect

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas`

**Interfaces:**
- Consumes: `ReadNamingPresets`/`WriteNamingPreset`/`DeleteNamingPreset` (Task 6); the existing `FCboPreset`, `ApplyPreset`, `DetectAndSetPreset`, `FApplyingPreset`, `NAMING_PRESET_BUNDLES`, `NAMING_PRESET_PARAMS`, `FNamingEditors`.
- Produces: combo listing built-ins + saved presets + Custom; `FBtnSavePreset`/`FBtnDeletePreset`; `SavePresetClick`/`DeletePresetClick`; a `FSavedPresets: TArray<TNamingPreset>` cache refreshed on load and after save/delete; `ApplyPreset`/`DetectAndSetPreset` extended to cover saved presets.

- [ ] **Step 1: Add the two buttons beside the combo**

Where `FCboPreset` is created (grep `FCboPreset`), add after it:

```pascal
  FBtnSavePreset := TButton.Create(Self);
  FBtnSavePreset.Parent := FCboPreset.Parent;
  FBtnSavePreset.Caption := 'Save as...';
  FBtnSavePreset.Left := FCboPreset.Left + FCboPreset.Width + 8;
  FBtnSavePreset.Top  := FCboPreset.Top;
  FBtnSavePreset.OnClick := SavePresetClick;

  FBtnDeletePreset := TButton.Create(Self);
  FBtnDeletePreset.Parent := FCboPreset.Parent;
  FBtnDeletePreset.Caption := 'Delete';
  FBtnDeletePreset.Left := FBtnSavePreset.Left + FBtnSavePreset.Width + 4;
  FBtnDeletePreset.Top  := FCboPreset.Top;
  FBtnDeletePreset.OnClick := DeletePresetClick;
```

Declare `FBtnSavePreset, FBtnDeletePreset: TButton;`, `FSavedPresets: TArray<TNamingPreset>;`, `SavePresetClick(Sender: TObject);`, `DeletePresetClick(Sender: TObject);` private. Add `Vcl.StdCtrls` (TButton) and `Vcl.Dialogs` (InputQuery) to uses if absent.

- [ ] **Step 2: Rebuild the combo item list from built-ins + saved**

Extract combo population into `RebuildPresetCombo`:

```pascal
procedure TDragLintLintOptionsFrame.RebuildPresetCombo;
var i: Integer;
begin
  FSavedPresets := ReadNamingPresets;
  FCboPreset.Items.BeginUpdate;
  try
    FCboPreset.Items.Clear;
    FCboPreset.Items.Add('Embarcadero (A...)');   { index PRESET_EMBARCADERO = 0 }
    FCboPreset.Items.Add('House (p...)');          { index PRESET_HOUSE = 1 }
    for i := 0 to High(FSavedPresets) do
      FCboPreset.Items.Add(FSavedPresets[i].Name); { saved start at index 2 }
    FCboPreset.Items.Add('Custom');                { always LAST }
  finally
    FCboPreset.Items.EndUpdate;
  end;
end;
```

IMPORTANT: `PRESET_CUSTOM` is no longer the fixed index 2 -- it is now `FCboPreset.Items.Count - 1`. Introduce helpers `CustomIndex: Integer` (= last) and `SavedIndexToPreset(AIdx): Integer` (= AIdx - 2). Update every hard-coded `2`/`PRESET_CUSTOM` comparison accordingly (grep `PRESET_CUSTOM` and the literal combo indices).

- [ ] **Step 3: Extend `ApplyPreset` to handle saved presets**

```pascal
procedure TDragLintLintOptionsFrame.ApplyPreset(AKind: Integer);
var k, si: Integer; Vals: array[0..7] of string;
begin
  if AKind = CustomIndex then Exit;              { Custom = detection-only sentinel }
  if AKind <= PRESET_HOUSE then
    for k := 0 to 7 do Vals[k] := NAMING_PRESET_BUNDLES[AKind][k]
  else
  begin
    si := AKind - 2;                             { saved-preset index }
    if (si < 0) or (si > High(FSavedPresets)) then Exit;
    for k := 0 to 7 do Vals[k] := FSavedPresets[si].Values[k];
  end;
  FApplyingPreset := True;
  try
    for k := 0 to 7 do
      SetNamingEditorValue(NAMING_PRESET_PARAMS[k], Vals[k]);  { existing setter idiom }
  finally
    FApplyingPreset := False;
  end;
end;
```

(Use whatever the existing `ApplyPreset` uses to write an editor value -- copy that line, do not invent `SetNamingEditorValue` if the real code sets `FNamingEditors[...]` directly.)

- [ ] **Step 4: Extend `DetectAndSetPreset` to match saved presets too**

After the existing built-in match logic, before falling back to Custom, loop `FSavedPresets` comparing all 8 current field values; on a full match select that saved index. Only if nothing matches, select `CustomIndex`.

- [ ] **Step 5: Implement Save-as / Delete handlers**

```pascal
procedure TDragLintLintOptionsFrame.SavePresetClick(Sender: TObject);
var Nm: string; P: TNamingPreset; k: Integer;
begin
  Nm := '';
  if not InputQuery('Save naming preset', 'Preset name:', Nm) then Exit;
  Nm := Trim(Nm);
  if Nm = '' then Exit;
  if SameText(Nm, 'Custom') or SameText(Nm, 'Embarcadero (A...)') or SameText(Nm, 'House (p...)') then
  begin ShowMessage('That name is reserved for a built-in preset.'); Exit; end;
  P.Name := Nm;
  for k := 0 to 7 do P.Values[k] := GetNamingEditorValue(NAMING_PRESET_PARAMS[k]);  { existing getter idiom }
  WriteNamingPreset(P);
  RebuildPresetCombo;
  FCboPreset.ItemIndex := FCboPreset.Items.IndexOf(Nm);
  UpdatePresetButtons;
end;

procedure TDragLintLintOptionsFrame.DeletePresetClick(Sender: TObject);
var Nm: string;
begin
  if FCboPreset.ItemIndex < 0 then Exit;
  Nm := FCboPreset.Items[FCboPreset.ItemIndex];
  { built-ins + Custom not deletable }
  if (FCboPreset.ItemIndex <= PRESET_HOUSE) or (FCboPreset.ItemIndex = CustomIndex) then Exit;
  if MessageDlg(Format('Delete saved preset "%s"?', [Nm]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  DeleteNamingPreset(Nm);
  RebuildPresetCombo;
  FCboPreset.ItemIndex := CustomIndex;
  UpdatePresetButtons;
end;
```

Add `UpdatePresetButtons`: `FBtnDeletePreset.Enabled := (FCboPreset.ItemIndex > PRESET_HOUSE) and (FCboPreset.ItemIndex <> CustomIndex);`. Call it in `PresetSelected` and after Load. (Use the real getter the frame already has for reading a naming field value; grep the existing `Save`/`DetectAndSetPreset` to find it.)

- [ ] **Step 6: Wire `RebuildPresetCombo` + `UpdatePresetButtons` into frame load**

Where the frame currently builds the combo / calls `DetectAndSetPreset` on load, call `RebuildPresetCombo` first (so saved presets are listed), then `DetectAndSetPreset`, then `UpdatePresetButtons`.

- [ ] **Step 7: Build the BPL (RAD Studio CLOSED)**

delphi-build -> Win32, 0 errors. **If `bds.exe` running: STOP, report BLOCKED.**

- [ ] **Step 8: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.LintOptionsFrame.pas
git commit -m "feat(ide): save-your-own naming presets -- combo + Save as.../Delete backed by naming.presets manifest"
```

---

## PHASE 4 -- Verification, docs, release

### Task 8: Full battery + version bump + docs

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (VERSION), `docs/lint/CHANGELOG*`, `README*`, `docs/AI-USAGE*`/`AI-INDEX-FIRST*`, `docs/INDEX-SCHEMA.md` (or the manifest doc)

- [ ] **Step 1: Run the full existing battery + the two new tests**

Run each and confirm `RESULT: PASS` / exit 0, zero FAIL:
`run_forward_calltree.ps1`, `run_naming_presets_roundtrip.ps1`, `run_reverse_calltree.ps1`, `run_self_field_refs.ps1`, `run_bare_rhs_refs.ps1`, `run_naming_prefix_autofix.ps1`, `run_naming_autofix.ps1`, `run_deps_report.ps1`, `run_manifest.ps1`, `tests/autofix/run_fixable_catalog.ps1`.

- [ ] **Step 2: Version bump**

In `src/cli/DRagLint.CLI.pas` change `VERSION` `'0.98.0-alpha'` -> `'0.99.0-alpha'`. Rebuild CLI Win64 Debug, confirm `drag-lint --version` prints `0.99.0-alpha`, deploy to both exe locations.

- [ ] **Step 3: Docs**

- CHANGELOG: new v0.99.0-alpha section (butterfly Call Graph tab + Ctrl+Alt+B + Structure "Show in Call Graph"; `reverse-calltree --direction callees`; save-your-own naming presets in `drag-lint.json`).
- README: document the Call Graph tab + Ctrl+Alt+B; the new `--direction` flag on `reverse-calltree`; saved presets (note they live in `.drag-lint.json` / global manifest and are per-project when a project is open).
- AI-USAGE / AI-INDEX-FIRST: add `reverse-calltree --direction callers|callees` to the verb list; note the butterfly is IDE-only (no CLI verb); note `naming.presets` is a manifest key (IDE-written, not yet CLI-read).
- INDEX-SCHEMA / manifest doc: add the `naming.presets` key shape.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore(release): v0.99.0-alpha version bump + CHANGELOG/README/AI-docs for butterfly tab + reverse-calltree --direction + naming presets"
```

- [ ] **Step 5: Final Win32 BPL rebuild carrying all IDE changes (RAD Studio CLOSED)**

delphi-build -> Win32, 0 errors; confirm deploy to `third_party/dll-win32/`. **If `bds.exe` running: STOP, report BLOCKED.**

```bash
git add third_party/dll-win32
git commit -m "build(plugin): rebuild Win32 BPL carrying Batch F (butterfly tab, Ctrl+Alt+B, naming presets)"
```

---

### Task 9: Final whole-branch review + release

- [ ] **Step 1: Request a final whole-branch code review** (superpowers:requesting-code-review or /code-review high). Address Critical/Important findings; defer Minor with a note. Re-run affected tests after any fix.

- [ ] **Step 2: Pack the release** -- run the existing `pack-lint-release.ps1` to produce the Win64 + Win32 CLI zips (+ the Win32 BPL), matching the v0.96/0.97/0.98 release artifacts.

- [ ] **Step 3: Cut the GH release** -- push `main`, tag `v0.99.0-alpha`, create the GitHub release with both CLI zips + the Win32 BPL, marked Latest. (Follow the exact `gh release create` invocation used for v0.98.)

- [ ] **Step 4: Update the live-IDE smoke checklist** in the SDD ledger / BACKLOG (F1-a..d, F2-a..d from the spec) for the user to run, and refresh BACKLOG RESUME + auto-memory (handoff skill).

---

## Live-IDE smoke checklist (USER runs; NOT headless)

- **F1-a:** cursor on a symbol -> Ctrl+Alt+B -> Call Graph tab surfaces, Callers + Callees populated.
- **F1-b:** Uses & Dependencies -> "Call Graph (Butterfly)..." does the same.
- **F1-c:** Structure tab -> right-click a symbol -> "Show in Call Graph" -> butterfly updates to that root; dock does NOT self-select on ordinary tree navigation.
- **F1-d:** double-click a caller node -> jumps to the call site; double-click a callee node -> jumps to the callee's declaration; root / empty-site nodes do nothing.
- **F2-a:** set the 8 naming fields, Save as... "X" -> combo shows "X" selected; the manifest contains `naming.presets[X]`.
- **F2-b:** switch to Custom then back to "X" -> the 8 fields restore.
- **F2-c:** Delete "X" -> combo drops it; Delete disabled on built-ins / Custom.
- **F2-d:** reopen the dock/frame -> saved presets reappear; editing a field flips the combo to Custom.

---

## Self-Review notes

- **Spec coverage:** F1 data (Task 1-2), F1 UI+nav (Task 3), F1 invocation both paths (Task 4-5), F2 storage+schema (Task 6), F2 UI+apply+detect (Task 7), testing (Task 2/6/8), build+release (Task 8-9). All spec sections mapped.
- **Refinement vs spec (both within design intent):** (1) callees clickability is delivered by a `--direction` flag on the EXISTING `reverse-calltree` verb (one JSON schema for both halves) rather than shelling two mismatched verbs -- cleaner, reuses `WalkCallers`. (2) forward nodes navigate to the callee's DECLARATION (TCallEdge has no call-site line); documented in Task 1 + smoke F1-d.
- **Type consistency:** `TRCallTree`/`TRCallNode`/`TRCallOptions` reused verbatim; `TNamingPreset` defined in Task 6 and consumed in Task 7; `NAMING_PRESET_PARAMS` order is the single source of truth for the 8 fields across engine JSON and manifest.
- **Open confirmations for implementers (grep-to-confirm, not placeholders):** exact names of the StructureForm qname/DB accessors (`EnumQNameForNode`/`ActiveDbForStructure`), the existing open-file-at-line helper, the `AddMenu*`/`AddPopupItem` idioms, and whether LintOptionsFrame already has a `ManifestPathForWrite`. Each task says exactly what to grep and what pattern to copy.
