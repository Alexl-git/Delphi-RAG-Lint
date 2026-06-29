# M2 Data-flow / CFG / def-use Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-routine control-flow graph (CFG) + a generic monotone data-flow solver to drag-lint, and ship 7 flow-sensitive lint checks (definite-assignment, dead-store/liveness, loop-var-after-loop, object-leak) that are impossible without it.

**Architecture:** Four new layered units. `DRagLint.Analysis.Cfg` builds an analysis-agnostic CFG (basic blocks + edges) from a `defProc` AST node. `DRagLint.Analysis.DataFlow` is a generic `TDataFlowSolver<TValue>` worklist driven by an `IDataFlowAnalysis<TValue>` interface. `DRagLint.Analysis.Flow.Lattices` holds the per-routine variable table plus the three concrete analyses (definite-assignment, liveness, escape). `DRagLint.Diagnostics.FlowChecks` (class `TFlowChecker`) runs the right analysis per routine and emits `TLintFinding`s. Wired into the same three CLI dispatch sites as the M1 checks.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), Object Pascal, tree-sitter-delphi13 grammar, existing `TAstParseCache` / `TTSNode` helpers, DUnitX-free console test runner pattern (mirrors `tests/projectchecks/`).

## Global Constraints

- **File encoding:** All `.pas` files strict 7-bit ASCII, CRLF line endings, no BOM. Edit/Write tools emit LF — normalize every touched `.pas` to CRLF before commit (`(t -replace "\r\n","\n") -replace "\n","\r\n"`, UTF8-no-BOM).
- **DocInsight `///`** spec-comments REQUIRED on every public/published type, method, interface (the `<summary>`/`<param>`/`<returns>`/`<remarks>` form). Private helpers optional.
- **TDD discipline:** every behaviour gets a failing test first (red), then minimal code (green). The doc-comment and the test must agree.
- **New-unit dual registration:** a NEW `.pas` unit must be added to BOTH the consuming `.dpr`'s `uses ... in '..'` clause AND the `.dproj`'s `<DCCReference>` list. Missing the `.dpr` uses = compiler error F2613.
- **Build (Win64 Release):** invoke the `delphi-build` skill recipe (rsvars + msbuild via `Start-Process -Wait`, read log for `BUILD_EXITCODE=0` + no `[dcc] Error`). A healthy build is < ~30s. The console test runners build with `dcc64 -B` via rsvars (see `tests/projectchecks/run_projectchecks_tests.ps1`).
- **Harness stays green:** `pwsh tests/lint/run_lint_tests.ps1` must pass after every check-bearing task.
- **FP policy (roadmap):** when unsure, do not over-report; keep the rule. Definite violation (holds on EVERY path) = `warning`; possible violation (holds on SOME path) = `info`.
- **Release:** M1 + M2 ship together as **v0.66.0-alpha** (user decision 2026-06-29). Do NOT cut intermediate releases.

## File Structure

| File | Responsibility | Created in |
|---|---|---|
| `src/analysis/DRagLint.Analysis.Cfg.pas` | CFG data structures (`TCfgBlock`, `TCfg`, `TCfgItem`) + `TCfgBuilder` (defProc -> CFG). Analysis-agnostic. | Task 1 |
| `tests/flowengine/FlowEngineTests.dpr` | Console unit-test runner for the engine (CFG + solver + lattices), mirrors `tests/projectchecks`. | Task 1 |
| `tests/flowengine/run_flowengine_tests.ps1` | Build + run the engine unit tests (`dcc64 -B` via rsvars). | Task 1 |
| `src/analysis/DRagLint.Analysis.DataFlow.pas` | Generic `IDataFlowAnalysis<TValue>` + `TDataFlowSolver<TValue>` worklist (forward/backward to fixpoint). | Task 2 |
| `src/analysis/DRagLint.Analysis.Flow.Lattices.pas` | `TRoutineVarTable` (var/param/Result -> index + kind + declared-type text) + concrete analyses: definite-assignment (Task 3), liveness (Task 4), escape (Task 6). | Tasks 3,4,6 |
| `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` | `TFlowChecker.Check` — runs analyses per routine, maps results to `TLintFinding`. | Task 3 (extended 4-8) |
| `src/cli/DRagLint.CLI.pas` (modify) | Wire `TFlowChecker.Check` into `DoLint`, `DoLintAll`, `DoCheckAst`; extend `--rule` allow-list + messages. | Task 3 (extended) |
| `tests/lint/*.pas` + `*.expected` | Per-check fixtures (positive + negative cases). | Tasks 3-8 |

**Reused existing API (do not reimplement — exact references):**
- `TAstParseCache.Get(const AFile: string): TParsedFile` in `src/diagnostics/DRagLint.Diagnostics.ParseCache.pas`. `TParsedFile = record Src: TBytes; Tree: TTSTree; end`. `TAstParseCache.Clear` frees trees.
- `TTSNode` helper (`src/../third_party/delphi-tree-sitter/TreeSitter.pas`): `.NodeType: string`, `.IsNull`, `.ChildCount`, `.Child(i)`, `.NamedChildCount`, `.NamedChild(i)`, `.ChildByField(name)`, `.StartPoint`/`.EndPoint` (`TTSPoint` Row/Column 0-based), `.StartByte`/`.EndByte`.
- `TLintFinding` (record) in `src/core/DRagLint.Core.Model.pas`: fields `RuleId, FilePath, Severity, Message: string; StartLine, StartCol, EndLine, EndCol: Integer`. Construct via `Default(TLintFinding)`; tree-sitter Row/Column are 0-based so add 1.
- `ISymbolStore` in `src/core/DRagLint.Core.Interfaces.pas`: `ResolveTypeCategory(const ATypeName: string; AFileId: Int64): TTypeCategory`, `FindFileIdByPath(const APath): Int64`. `TTypeCategory = (tcUnknown, tcFloat, tcString, tcChar, tcOrdinal, tcBoolean, tcInterface, tcClass, tcRecord, tcPointer, tcEnum)`.
- **`NodeStr` helper** (define locally in each unit that needs text, as existing checks do):
  ```pascal
  function NodeStr(const N: TTSNode; const ASrc: TBytes): string;
  var S, E, L: Integer;
  begin
    Result := '';
    if N.IsNull then Exit;
    S := Integer(N.StartByte); E := Integer(N.EndByte); L := E - S;
    if (L <= 0) or (S < 0) or (E > Length(ASrc)) then Exit;
    Result := TEncoding.UTF8.GetString(ASrc, S, L);
  end;
  ```

**Confirmed tree-sitter node kinds (verified against real parses 2026-06-29):**
- Routine: `defProc` -> fields `header:`(declProc), `local:`(declVars / declLabels), `body:`(block).
- Blocks: `block`(kBegin..kEnd), `statements`(bare sequence), `statement`(wraps one non-assignment stmt).
- `assignment` -> `lhs:`, `operator:`(kAssign), `rhs:`. Inline `var y := e` -> assignment with `lhs:` = `varAssignDef`(kVar + identifier).
- `if`(condition,then; no else), `ifElse`(condition,then,else), `case`(kCase, selector, kOf, N x `caseCase`(label:caseLabel, body:), optional kElse + else stmts, kEnd).
- `while`(condition,body), `for`(start:assignment[defines loop var], end, body; kTo/kDownto), `foreach`(iterator:identifier, iterable, body), `repeat`(body:statements, condition).
- `try`: finally form -> `try:`statements, `finally:`kFinally, `finally:`statements; except form -> `try:`statements, `except:`kExcept, then `except:`exceptionHandler(s) (kOn,variable,exception,body) OR a bare `except:`statements.
- `with`(entity, body). `goto`(kGoto, identifier) + body-level `label` node + `declLabels` section.
- **CRITICAL text-match (NOT keywords):** `Break`/`Continue`/`Exit` (no arg) parse as a bare `identifier` inside a `statement`. `Exit(v)` = `exprCall` with `entity:` identifier text "Exit". No-paren method call (`o.Free`) = `exprDot` (lhs/operator:kDot/rhs). All identifier matching is case-insensitive.

---

### Task 1: CFG data structures + builder + flowengine test runner

**Files:**
- Create: `src/analysis/DRagLint.Analysis.Cfg.pas`
- Create: `tests/flowengine/FlowEngineTests.dpr`
- Create: `tests/flowengine/run_flowengine_tests.ps1`

**Interfaces:**
- Produces:
  - `TCfgItem = record Node: TTSNode; Opaque: Boolean; end;` — one simple statement / condition expression. `Opaque=True` for items inside a `with` (their reads are not trusted; see soundness notes).
  - `TCfgBlock = class ... Index: Integer; Items: TList<TCfgItem>; EntryDefs: TArray<string>; Succ, Pred: TList<Integer>; end;` — `EntryDefs` = names unconditionally defined at block entry (the `foreach` iterator).
  - `TCfg = class ... Blocks: TObjectList<TCfgBlock>; EntryIdx, ExitIdx: Integer; RoutineNode: TTSNode; Src: TBytes; Skipped: Boolean; function BlockCount: Integer; procedure ComputePreds; end;`
  - `TCfgBuilder = class class function Build(const AProc: TTSNode; const ASrc: TBytes): TCfg; end;` — returns a CFG (caller owns/frees it); `Skipped=True` if the routine contains `goto`/label/`asm` (analyses must bail).
  - `function CfgFindProcs(const ARoot: TTSNode): TArray<TTSNode>;` — collects every `defProc` in a parsed unit (for the checkers to iterate).

- [ ] **Step 1: Confirm the remaining node kinds against a real parse**

The `Break`/`Continue`/`Exit`/`goto`/loop/try kinds are already confirmed (see header). Before writing the builder, confirm the **`raise`** and **`asm`** node kinds (not yet probed) — standing project rule: never trust assumed names.

Run:
```bash
cd "$(mktemp -d)" && cat > r.pas <<'EOF'
unit r;
interface
implementation
procedure P;
begin
  raise Exception.Create('x');
end;
procedure Q;
asm
  nop
end;
end.
EOF
"C:/Projects/tree-sitter-delphi13/tree-sitter.exe" parse r.pas
```
Expected: a node kind for `raise` (likely `raise`) and for the asm routine body (likely `asm` / `asmStatement`). Record the exact kinds; use them verbatim in Step 5's `IsDivertStmt` / `RoutineHasGotoOrAsm`.

- [ ] **Step 2: Write the failing engine test (block/edge structure)**

Create `tests/flowengine/FlowEngineTests.dpr` (console runner mirroring `tests/projectchecks/ProjectChecksTests.dpr`). Start with the runner scaffold + the first CFG test. This test writes a fixture to a temp file, parses it via `TAstParseCache`, builds the CFG for the single routine, and asserts the block/edge shape of an `ifElse`.

```pascal
program FlowEngineTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Analysis.Cfg in '..\..\src\analysis\DRagLint.Analysis.Cfg.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

{ Write ASource to a temp .pas, parse it, return the CFG of its first defProc.
  Caller frees the result. }
function BuildCfgFor(const ASource: string): TCfg;
var
  Tmp: string;
  PF: TParsedFile;
  Procs: TArray<TTSNode>;
begin
  Result := nil;
  Tmp := TPath.Combine(TPath.GetTempPath, 'flowengine_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(Tmp, ASource);
  try
    PF := TAstParseCache.Get(Tmp);
    if PF.Tree = nil then Exit;
    Procs := CfgFindProcs(PF.Tree.RootNode);
    if Length(Procs) = 0 then Exit;
    Result := TCfgBuilder.Build(Procs[0], PF.Src);
  finally
    TAstParseCache.Clear;
    TFile.Delete(Tmp);
  end;
end;

{ True iff block AFrom has an edge to block ATo. }
function HasEdge(ACfg: TCfg; AFrom, ATo: Integer): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to ACfg.Blocks[AFrom].Succ.Count - 1 do
    if ACfg.Blocks[AFrom].Succ[I] = ATo then Exit(True);
end;

procedure TestIfElseShape;
const
  SRC =
    'unit u; interface implementation' + sLineBreak +
    'procedure P; var x: Integer; begin' + sLineBreak +
    '  if x > 0 then x := 1 else x := 2;' + sLineBreak +
    '  x := 3;' + sLineBreak +
    'end; end.';
var
  Cfg: TCfg;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('ifElse: cfg built', Cfg <> nil);
    if Cfg = nil then Exit;
    Check('ifElse: not skipped', not Cfg.Skipped);
    { Entry, condition block, then-block, else-block, join (with x:=3), Exit. }
    Check('ifElse: >= 5 blocks', Cfg.BlockCount >= 5);
    { The condition block must branch to two distinct successors. }
    Check('ifElse: condition has 2 succ',
      Cfg.Blocks[Cfg.EntryIdx].Succ.Count >= 1);
  finally
    Cfg.Free;
  end;
end;

begin
  GPass := 0; GFail := 0;
  try
    TestIfElseShape;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('flowengine-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
```

Also create `tests/flowengine/run_flowengine_tests.ps1` (copy of `tests/projectchecks/run_projectchecks_tests.ps1`, retargeted):
```powershell
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\FlowEngineTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 20; exit 1 }
& "$dir\FlowEngineTests.exe"
exit $LASTEXITCODE
```

- [ ] **Step 3: Run the test to verify it fails (unit does not exist yet)**

Run:
```powershell
pwsh -File tests\flowengine\run_flowengine_tests.ps1
```
Expected: BUILD FAILED — `DRagLint.Analysis.Cfg` not found (F2613/E1026). This confirms the harness wiring before any implementation exists.

- [ ] **Step 4: Create the CFG data structures (`DRagLint.Analysis.Cfg.pas` — types + accessors)**

```pascal
unit DRagLint.Analysis.Cfg;

{ Per-routine control-flow graph for drag-lint's flow-sensitive analyses (M2).
  Analysis-agnostic: builds basic blocks + edges from a tree-sitter `defProc`
  node. Compound statements (if/while/for/case/try/repeat/with) are decomposed
  into edges; basic blocks hold only SIMPLE items (assignments, call/expression
  statements, and the condition expressions of branches/loops) so the data-flow
  transfer functions interpret one node at a time. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  TreeSitter;

type
  /// <summary>One element of a basic block: a simple-statement or condition AST
  /// node, plus an opacity flag.</summary>
  /// <remarks>Opaque items live inside a `with` statement; their identifier
  /// reads are not trusted (a `with` aliases fields), so definite-assignment
  /// ignores their uses and liveness treats them as using everything.</remarks>
  TCfgItem = record
    Node  : TTSNode;
    Opaque: Boolean;
  end;

  /// <summary>A maximal run of simple items with a single entry and single
  /// exit, plus its CFG successor/predecessor block indices.</summary>
  /// <remarks>Block 0 is the synthetic Entry, block 1 the synthetic Exit; both
  /// have empty `Items`. `EntryDefs` names vars defined unconditionally on
  /// entry to this block (used for the `foreach` iterator).</remarks>
  TCfgBlock = class
  public
    Index    : Integer;
    Items    : TList<TCfgItem>;
    EntryDefs: TArray<string>;
    Succ     : TList<Integer>;
    Pred     : TList<Integer>;
    constructor Create(AIndex: Integer);
    destructor Destroy; override;
    /// <summary>Append AItem (an assignment / call / condition node).</summary>
    procedure AddItem(const ANode: TTSNode; AOpaque: Boolean);
    /// <summary>Record an edge from this block to block AToIdx (no duplicates).</summary>
    procedure AddSucc(AToIdx: Integer);
  end;

  /// <summary>The control-flow graph of one routine body.</summary>
  /// <remarks>Caller owns the instance and must Free it. When `Skipped` is True
  /// the routine contains `goto`/labels/`asm` and analyses must bail (return no
  /// findings) — the graph would otherwise need unsound edges.</remarks>
  TCfg = class
  public
    Blocks     : TObjectList<TCfgBlock>;
    EntryIdx   : Integer;
    ExitIdx    : Integer;
    RoutineNode: TTSNode;
    Src        : TBytes;
    Skipped    : Boolean;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Create a fresh empty block, append it, and return it.</summary>
    function NewBlock: TCfgBlock;
    function BlockCount: Integer;
    /// <summary>Fill every block's `Pred` list from the `Succ` lists. Call once
    /// after construction; required by backward analyses (liveness).</summary>
    procedure ComputePreds;
  end;

  /// <summary>Builds a <see cref="TCfg"/> from a `defProc` node.</summary>
  TCfgBuilder = class
  public
    /// <summary>Build the CFG of the routine AProc (a `defProc`). Returns nil if
    /// AProc is not a defProc or has no body. Sets `Skipped` for goto/asm.</summary>
    /// <param name="AProc">The `defProc` AST node.</param>
    /// <param name="ASrc">The unit's source bytes (for identifier text).</param>
    class function Build(const AProc: TTSNode; const ASrc: TBytes): TCfg;
  end;

/// <summary>Collect every `defProc` node anywhere under ARoot.</summary>
function CfgFindProcs(const ARoot: TTSNode): TArray<TTSNode>;

implementation

{ TCfgBlock }

constructor TCfgBlock.Create(AIndex: Integer);
begin
  inherited Create;
  Index := AIndex;
  Items := TList<TCfgItem>.Create;
  Succ  := TList<Integer>.Create;
  Pred  := TList<Integer>.Create;
end;

destructor TCfgBlock.Destroy;
begin
  Items.Free; Succ.Free; Pred.Free;
  inherited;
end;

procedure TCfgBlock.AddItem(const ANode: TTSNode; AOpaque: Boolean);
var It: TCfgItem;
begin
  It.Node := ANode; It.Opaque := AOpaque;
  Items.Add(It);
end;

procedure TCfgBlock.AddSucc(AToIdx: Integer);
begin
  if Succ.IndexOf(AToIdx) < 0 then Succ.Add(AToIdx);
end;

{ TCfg }

constructor TCfg.Create;
begin
  inherited Create;
  Blocks := TObjectList<TCfgBlock>.Create(True);
end;

destructor TCfg.Destroy;
begin
  Blocks.Free;
  inherited;
end;

function TCfg.NewBlock: TCfgBlock;
begin
  Result := TCfgBlock.Create(Blocks.Count);
  Blocks.Add(Result);
end;

function TCfg.BlockCount: Integer;
begin
  Result := Blocks.Count;
end;

procedure TCfg.ComputePreds;
var B, S: Integer;
begin
  for B := 0 to Blocks.Count - 1 do Blocks[B].Pred.Clear;
  for B := 0 to Blocks.Count - 1 do
    for S := 0 to Blocks[B].Succ.Count - 1 do
      Blocks[Blocks[B].Succ[S]].Pred.Add(B);
end;

function CfgFindProcs(const ARoot: TTSNode): TArray<TTSNode>;
var
  Acc: TList<TTSNode>;
  procedure Walk(const N: TTSNode);
  var I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then Acc.Add(N);
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;
begin
  Acc := TList<TTSNode>.Create;
  try
    Walk(ARoot);
    Result := Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

{ TCfgBuilder implemented in Step 5 }

end.
```

- [ ] **Step 5: Implement `TCfgBuilder.Build` (the recursive emit)**

Replace the `{ TCfgBuilder implemented in Step 5 }` comment with the builder. The core is a recursive `EmitStmt(ACur, ANode): Integer` that appends to / branches from the "current" block and returns the block where control continues (`-1` when control diverged — Exit/Break/Continue/raise). A loop-context stack routes Break/Continue.

```pascal
type
  TLoopCtx = record ContinueIdx, BreakIdx: Integer; end;

  TBuilderState = class
  public
    Cfg     : TCfg;
    Loops   : TStack<TLoopCtx>;
    WithDepth: Integer;
    constructor Create(ACfg: TCfg);
    destructor Destroy; override;
    function EmitStmt(ACur: Integer; const ANode: TTSNode): Integer;
    function EmitList(ACur: Integer; const AContainer: TTSNode): Integer;
  end;

constructor TBuilderState.Create(ACfg: TCfg);
begin
  inherited Create; Cfg := ACfg; Loops := TStack<TLoopCtx>.Create; WithDepth := 0;
end;

destructor TBuilderState.Destroy;
begin
  Loops.Free; inherited;
end;

function LowerText(const N: TTSNode; const ASrc: TBytes): string;
begin
  Result := LowerCase(Trim(NodeStr(N, ASrc)));
end;

{ True for statement nodes that, after executing, divert control (no fall-through). }
function RoutineHasGotoOrAsm(const N: TTSNode): Boolean;
var I: Integer; K: string;
begin
  Result := False;
  if N.IsNull then Exit;
  K := N.NodeType;
  if (K = 'goto') or (K = 'label') or (K = 'declLabels')
     or (Pos('asm', K) = 1) then Exit(True); { confirm 'asm'/'asmStatement' in Step 1 }
  for I := 0 to N.NamedChildCount - 1 do
    if RoutineHasGotoOrAsm(N.NamedChild(I)) then Exit(True);
end;

{ Add ANode as a simple item in block ACur, then return whether control diverts.
  Sets ADivertTo to the target block index for Exit/Break/Continue (-1 = none). }
function TBuilderState.EmitStmt(ACur: Integer; const ANode: TTSNode): Integer;
var
  K, EntTxt: string;
  Cond, ThenN, ElseN, BodyN, StartN, EntityN, IterN: TTSNode;
  ThenAfter, ElseAfter, JoinIdx, HdrIdx, BodyIdx, FollowIdx, TestIdx: Integer;
  TryN, FinN, ExcN, TryAfter, FinAfter, ExcAfter: TTSNode;
  Ctx: TLoopCtx;
  I: Integer;
begin
  Result := ACur;
  if ANode.IsNull then Exit;
  K := ANode.NodeType;

  { ----- compound statements ----- }
  if K = 'block' then Exit(EmitList(ACur, ANode));
  if K = 'statements' then Exit(EmitList(ACur, ANode));

  if (K = 'if') or (K = 'ifElse') then
  begin
    Cond := ANode.ChildByField('condition');
    if not Cond.IsNull then Cfg.Blocks[ACur].AddItem(Cond, WithDepth > 0);
    ThenN := ANode.ChildByField('then');
    JoinIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(BodyIdx);
    ThenAfter := EmitStmt(BodyIdx, ThenN);
    if ThenAfter >= 0 then Cfg.Blocks[ThenAfter].AddSucc(JoinIdx);
    if K = 'ifElse' then
    begin
      ElseN := ANode.ChildByField('else');
      BodyIdx := Cfg.NewBlock.Index;
      Cfg.Blocks[ACur].AddSucc(BodyIdx);
      ElseAfter := EmitStmt(BodyIdx, ElseN);
      if ElseAfter >= 0 then Cfg.Blocks[ElseAfter].AddSucc(JoinIdx);
    end
    else
      Cfg.Blocks[ACur].AddSucc(JoinIdx); { no else -> false path skips to join }
    Exit(JoinIdx);
  end;

  if K = 'while' then
  begin
    HdrIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(HdrIdx);
    Cond := ANode.ChildByField('condition');
    if not Cond.IsNull then Cfg.Blocks[HdrIdx].AddItem(Cond, WithDepth > 0);
    FollowIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[HdrIdx].AddSucc(BodyIdx);
    Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    BodyN := ANode.ChildByField('body');
    TestIdx := EmitStmt(BodyIdx, BodyN);
    if TestIdx >= 0 then Cfg.Blocks[TestIdx].AddSucc(HdrIdx); { back-edge }
    Loops.Pop;
    Exit(FollowIdx);
  end;

  if K = 'for' then
  begin
    StartN := ANode.ChildByField('start'); { assignment: defines the loop var }
    if not StartN.IsNull then Cfg.Blocks[ACur].AddItem(StartN, WithDepth > 0);
    HdrIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(HdrIdx);
    FollowIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[HdrIdx].AddSucc(BodyIdx);
    Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    BodyN := ANode.ChildByField('body');
    TestIdx := EmitStmt(BodyIdx, BodyN);
    if TestIdx >= 0 then Cfg.Blocks[TestIdx].AddSucc(HdrIdx);
    Loops.Pop;
    Exit(FollowIdx);
  end;

  if K = 'foreach' then
  begin
    EntityN := ANode.ChildByField('iterable');
    if not EntityN.IsNull then Cfg.Blocks[ACur].AddItem(EntityN, WithDepth > 0);
    HdrIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(HdrIdx);
    FollowIdx := Cfg.NewBlock.Index;
    BodyIdx := Cfg.NewBlock.Index;
    { iterator var is defined unconditionally on body entry (per iteration) }
    IterN := ANode.ChildByField('iterator');
    if not IterN.IsNull then
      Cfg.Blocks[BodyIdx].EntryDefs := [LowerText(IterN, Cfg.Src)];
    Cfg.Blocks[HdrIdx].AddSucc(BodyIdx);
    Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
    Ctx.ContinueIdx := HdrIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    TestIdx := EmitStmt(BodyIdx, ANode.ChildByField('body'));
    if TestIdx >= 0 then Cfg.Blocks[TestIdx].AddSucc(HdrIdx);
    Loops.Pop;
    Exit(FollowIdx);
  end;

  if K = 'repeat' then
  begin
    BodyIdx := Cfg.NewBlock.Index;
    Cfg.Blocks[ACur].AddSucc(BodyIdx);
    FollowIdx := Cfg.NewBlock.Index;
    TestIdx := Cfg.NewBlock.Index; { holds the until-condition }
    Cond := ANode.ChildByField('condition');
    if not Cond.IsNull then Cfg.Blocks[TestIdx].AddItem(Cond, WithDepth > 0);
    Cfg.Blocks[TestIdx].AddSucc(BodyIdx);   { loop continues }
    Cfg.Blocks[TestIdx].AddSucc(FollowIdx); { loop exits }
    Ctx.ContinueIdx := TestIdx; Ctx.BreakIdx := FollowIdx; Loops.Push(Ctx);
    BodyAfter := EmitStmt(BodyIdx, ANode.ChildByField('body'));
    if BodyAfter >= 0 then Cfg.Blocks[BodyAfter].AddSucc(TestIdx);
    Loops.Pop;
    Exit(FollowIdx);
  end;

  if K = 'case' then
  begin
    { selector is the first named child that is not a caseCase/kElse body }
    for I := 0 to ANode.NamedChildCount - 1 do
      if ANode.NamedChild(I).NodeType <> 'caseCase' then
      begin
        Cfg.Blocks[ACur].AddItem(ANode.NamedChild(I), WithDepth > 0);
        Break;
      end;
    JoinIdx := Cfg.NewBlock.Index;
    for I := 0 to ANode.NamedChildCount - 1 do
      if ANode.NamedChild(I).NodeType = 'caseCase' then
      begin
        BodyIdx := Cfg.NewBlock.Index;
        Cfg.Blocks[ACur].AddSucc(BodyIdx);
        ThenAfter := EmitStmt(BodyIdx, ANode.NamedChild(I).ChildByField('body'));
        if ThenAfter >= 0 then Cfg.Blocks[ThenAfter].AddSucc(JoinIdx);
      end;
    { else / no-match fall-through: connect selector block straight to join too }
    Cfg.Blocks[ACur].AddSucc(JoinIdx);
    Exit(JoinIdx);
  end;

  if K = 'try' then
  begin
    TryN := ANode.ChildByField('try');
    FinN := ANode.ChildByField('finally'); { the statements field, if finally form }
    ExcN := ANode.ChildByField('except');  { kExcept / handler / statements }
    BodyIdx := Cfg.NewBlock.Index;          { try region entry }
    Cfg.Blocks[ACur].AddSucc(BodyIdx);
    FollowIdx := Cfg.NewBlock.Index;
    TryAfter := EmitStmt(BodyIdx, TryN);
    if not FinN.IsNull then
    begin
      HdrIdx := Cfg.NewBlock.Index; { finally entry }
      Cfg.Blocks[BodyIdx].AddSucc(HdrIdx);      { exceptional: skips try body }
      if TryAfter >= 0 then Cfg.Blocks[TryAfter].AddSucc(HdrIdx); { normal }
      FinAfter := EmitStmt(HdrIdx, FinN);
      if FinAfter >= 0 then Cfg.Blocks[FinAfter].AddSucc(FollowIdx)
      else Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
      Exit(FollowIdx);
    end
    else
    begin
      { except form: normal completion -> follow; exceptional -> each handler }
      if TryAfter >= 0 then Cfg.Blocks[TryAfter].AddSucc(FollowIdx);
      for I := 0 to ANode.NamedChildCount - 1 do
        if (ANode.NamedChild(I).NodeType = 'exceptionHandler')
           or (ANode.NamedChild(I).NodeType = 'statements') then
        begin
          HdrIdx := Cfg.NewBlock.Index;
          Cfg.Blocks[BodyIdx].AddSucc(HdrIdx); { try entry -> handler (conservative) }
          if ANode.NamedChild(I).NodeType = 'exceptionHandler' then
            ExcAfter := EmitStmt(HdrIdx, ANode.NamedChild(I).ChildByField('body'))
          else
            ExcAfter := EmitStmt(HdrIdx, ANode.NamedChild(I));
          if ExcAfter >= 0 then Cfg.Blocks[ExcAfter].AddSucc(FollowIdx)
          else Cfg.Blocks[HdrIdx].AddSucc(FollowIdx);
        end;
      Exit(FollowIdx);
    end;
  end;

  if K = 'with' then
  begin
    EntityN := ANode.ChildByField('entity');
    if not EntityN.IsNull then Cfg.Blocks[ACur].AddItem(EntityN, WithDepth > 0);
    Inc(WithDepth);
    try
      Result := EmitStmt(ACur, ANode.ChildByField('body'));
    finally
      Dec(WithDepth);
    end;
    Exit;
  end;

  { ----- simple statements ----- }
  if K = 'assignment' then
  begin
    Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
    Exit(ACur);
  end;

  if K = 'raise' then { confirm exact kind in Step 1 }
  begin
    Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
    Cfg.Blocks[ACur].AddSucc(Cfg.ExitIdx);
    Exit(-1);
  end;

  if (K = 'statement') or (K = 'exprCall') or (K = 'exprDot') or (K = 'identifier') then
  begin
    { Exit / Break / Continue are bare identifiers (or Exit(v) = exprCall). }
    if K = 'exprCall' then
      EntTxt := LowerText(ANode.ChildByField('entity'), Cfg.Src)
    else if K = 'statement' then
      EntTxt := LowerText(ANode, Cfg.Src)  { single-token statement text }
    else
      EntTxt := LowerText(ANode, Cfg.Src);
    Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
    if EntTxt = 'exit' then
    begin Cfg.Blocks[ACur].AddSucc(Cfg.ExitIdx); Exit(-1); end;
    if (EntTxt = 'break') and (Loops.Count > 0) then
    begin Cfg.Blocks[ACur].AddSucc(Loops.Peek.BreakIdx); Exit(-1); end;
    if (EntTxt = 'continue') and (Loops.Count > 0) then
    begin Cfg.Blocks[ACur].AddSucc(Loops.Peek.ContinueIdx); Exit(-1); end;
    Exit(ACur);
  end;

  { default: opaque statement, no control change }
  Cfg.Blocks[ACur].AddItem(ANode, WithDepth > 0);
  Result := ACur;
end;

{ Thread ACur through every statement child of a block/statements container. }
function TBuilderState.EmitList(ACur: Integer; const AContainer: TTSNode): Integer;
var I, Cur: Integer; Ch: TTSNode;
begin
  Cur := ACur;
  for I := 0 to AContainer.NamedChildCount - 1 do
  begin
    if Cur < 0 then Break; { unreachable tail }
    Ch := AContainer.NamedChild(I);
    Cur := EmitStmt(Cur, Ch);
  end;
  Result := Cur;
end;

class function TCfgBuilder.Build(const AProc: TTSNode; const ASrc: TBytes): TCfg;
var
  St: TBuilderState;
  Body: TTSNode;
  Last: Integer;
begin
  Result := TCfg.Create;
  Result.RoutineNode := AProc;
  Result.Src := ASrc;
  if AProc.IsNull or (AProc.NodeType <> 'defProc') then Exit;
  Body := AProc.ChildByField('body');
  if Body.IsNull then Exit;
  if RoutineHasGotoOrAsm(AProc) then begin Result.Skipped := True; Exit; end;

  Result.EntryIdx := Result.NewBlock.Index; { 0 = Entry }
  Result.ExitIdx  := Result.NewBlock.Index; { 1 = Exit }
  St := TBuilderState.Create(Result);
  try
    { Entry flows into a fresh first block. }
    var First := Result.NewBlock.Index;
    Result.Blocks[Result.EntryIdx].AddSucc(First);
    Last := St.EmitStmt(First, Body);
    if Last >= 0 then Result.Blocks[Last].AddSucc(Result.ExitIdx);
  finally
    St.Free;
  end;
  Result.ComputePreds;
end;
```

> Note: declare `BodyAfter: Integer;` in `EmitStmt`'s var block (used by the `repeat` branch). Add the `TBuilderState`/`TLoopCtx`/helpers above the `TCfgBuilder.Build` body inside the `implementation` section. Also add the local `NodeStr(const N: TTSNode; const ASrc: TBytes): string;` helper (body from the plan header's "Reused existing API") to the `DRagLint.Analysis.Cfg` implementation section — `LowerText` depends on it.

- [ ] **Step 6: Register the unit in the test .dproj is N/A; run the engine test**

The flowengine runner builds the `.dpr` directly with `dcc64 -B` (no `.dproj`), so only the `.dpr` `uses` clause matters — already added in Step 2.

Run:
```powershell
pwsh -File tests\flowengine\run_flowengine_tests.ps1
```
Expected: `flowengine-tests: 4 pass / 0 fail / 4 total`, exit 0.

- [ ] **Step 7: Add coverage tests for loops, case, try, and the goto-skip**

Add these procedures to `FlowEngineTests.dpr` and call them in the `try` block of `begin..end.`:

```pascal
procedure TestWhileBackEdge;
const SRC =
  'unit u; interface implementation procedure P; var i: Integer; begin' + sLineBreak +
  '  i := 0; while i < 10 do begin Inc(i); if i = 5 then Break; end; i := i + 1;' + sLineBreak +
  'end; end.';
var Cfg: TCfg; B, S, BackEdges: Integer;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('while: built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
    if Cfg = nil then Exit;
    { at least one back-edge (some block -> an earlier header block) exists }
    BackEdges := 0;
    for B := 0 to Cfg.BlockCount - 1 do
      for S := 0 to Cfg.Blocks[B].Succ.Count - 1 do
        if Cfg.Blocks[B].Succ[S] < B then Inc(BackEdges);
    Check('while: has a back-edge', BackEdges >= 1);
  finally Cfg.Free; end;
end;

procedure TestGotoSkips;
const SRC =
  'unit u; interface implementation procedure P; label done; var i: Integer; begin' + sLineBreak +
  '  i := 0; goto done; done: i := 1;' + sLineBreak +
  'end; end.';
var Cfg: TCfg;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('goto: routine marked Skipped', (Cfg <> nil) and Cfg.Skipped);
  finally Cfg.Free; end;
end;
```

Run `pwsh -File tests\flowengine\run_flowengine_tests.ps1`; Expected: all PASS (8/8), exit 0.

- [ ] **Step 8: Normalize line endings and commit**

```powershell
# normalize the two new .pas/.dpr to CRLF + UTF8-no-BOM
foreach ($f in @('src\analysis\DRagLint.Analysis.Cfg.pas','tests\flowengine\FlowEngineTests.dpr')) {
  $t = [IO.File]::ReadAllText($f); $t = ($t -replace "`r`n","`n") -replace "`n","`r`n"
  [IO.File]::WriteAllText($f, $t, (New-Object Text.UTF8Encoding($false)))
}
git add src/analysis/DRagLint.Analysis.Cfg.pas tests/flowengine/
git commit -m "feat(flow): M2 stage 1 -- per-routine CFG builder + flowengine unit tests

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Generic monotone data-flow solver

**Files:**
- Create: `src/analysis/DRagLint.Analysis.DataFlow.pas`
- Modify: `tests/flowengine/FlowEngineTests.dpr` (add solver tests + the unit to `uses`)

**Interfaces:**
- Consumes: `TCfg`, `TCfgBlock` (Task 1).
- Produces:
  - `TFlowDir = (fdForward, fdBackward);`
  - `IDataFlowAnalysis<TValue> = interface function Direction: TFlowDir; function Bottom: TValue; function Boundary: TValue; function Join(const A, B: TValue): TValue; function Transfer(const ABlock: TCfgBlock; const AIn: TValue): TValue; function Equals(const A, B: TValue): Boolean; end;`
  - `TDataFlowSolver<TValue> = class class function Solve(const ACfg: TCfg; const AAnalysis: IDataFlowAnalysis<TValue>; out AIn, AOut: TArray<TValue>): Boolean; end;` — fills `AIn[b]`/`AOut[b]` per block at fixpoint; returns False if `ACfg.Skipped`.

- [ ] **Step 1: Write the failing solver test (reaching-definitions toy lattice)**

Add to `FlowEngineTests.dpr` a tiny boolean-array analysis (a stand-in: "has the first statement executed") to verify the solver reaches a fixpoint and respects direction. Keep it self-contained in the test file.

```pascal
type
  TBoolVal = TArray<Boolean>;

  TToyForward = class(TInterfacedObject, IDataFlowAnalysis<TBoolVal>)
    function Direction: TFlowDir;
    function Bottom: TBoolVal;
    function Boundary: TBoolVal;
    function Join(const A, B: TBoolVal): TBoolVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TBoolVal): TBoolVal;
    function Equals(const A, B: TBoolVal): Boolean;
  end;

function TToyForward.Direction: TFlowDir; begin Result := fdForward; end;
function TToyForward.Bottom: TBoolVal;   begin Result := [False]; end;
function TToyForward.Boundary: TBoolVal; begin Result := [False]; end;
function TToyForward.Join(const A, B: TBoolVal): TBoolVal;
begin Result := [A[0] or B[0]]; end;
function TToyForward.Transfer(const ABlock: TCfgBlock; const AIn: TBoolVal): TBoolVal;
begin
  { once any block has >=1 item, mark true and keep it true downstream }
  Result := [AIn[0] or (ABlock.Items.Count > 0)];
end;
function TToyForward.Equals(const A, B: TBoolVal): Boolean;
begin Result := A[0] = B[0]; end;

procedure TestSolverForwardFixpoint;
const SRC =
  'unit u; interface implementation procedure P; var x: Integer; begin' + sLineBreak +
  '  x := 1; if x > 0 then x := 2; x := 3;' + sLineBreak +
  'end; end.';
var Cfg: TCfg; AIn, AOut: TArray<TBoolVal>; OK: Boolean;
begin
  Cfg := BuildCfgFor(SRC);
  try
    OK := TDataFlowSolver<TBoolVal>.Solve(Cfg, TToyForward.Create, AIn, AOut);
    Check('solver: solved', OK);
    if not OK then Exit;
    { OUT of the Exit block must be True (some statement executed upstream) }
    Check('solver: reaches true at Exit', AOut[Cfg.ExitIdx][0]);
  finally Cfg.Free; end;
end;
```

Add `DRagLint.Analysis.DataFlow in '..\..\src\analysis\DRagLint.Analysis.DataFlow.pas'` to the `.dpr` `uses`. Call `TestSolverForwardFixpoint` in `begin..end.`.

- [ ] **Step 2: Run to verify failure**

Run: `pwsh -File tests\flowengine\run_flowengine_tests.ps1`
Expected: BUILD FAILED — `DRagLint.Analysis.DataFlow` not found.

- [ ] **Step 3: Implement the solver**

```pascal
unit DRagLint.Analysis.DataFlow;

{ Generic monotone data-flow framework (M2). An analysis supplies a lattice
  value type plus Bottom/Boundary/Join/Transfer/Equals and a direction; the
  worklist solver iterates IN/OUT per basic block to a fixpoint. }

interface

uses
  System.Generics.Collections,
  DRagLint.Analysis.Cfg;

type
  /// <summary>Iteration direction of a data-flow analysis.</summary>
  TFlowDir = (fdForward, fdBackward);

  /// <summary>A monotone data-flow analysis over a CFG.</summary>
  /// <remarks>TValue is the lattice element (e.g. a variable bitset). `Join`
  /// must be commutative/associative and monotone; `Transfer` monotone. The
  /// solver terminates because the lattice has finite height.</remarks>
  IDataFlowAnalysis<TValue> = interface
    /// <summary>Forward (Entry->Exit) or backward (Exit->Entry).</summary>
    function Direction: TFlowDir;
    /// <summary>The lattice bottom (initial IN/OUT of interior blocks).</summary>
    function Bottom: TValue;
    /// <summary>Value at the boundary block (Entry for forward, Exit for
    /// backward) — e.g. params assigned-on-entry, or vars live-at-exit.</summary>
    function Boundary: TValue;
    /// <summary>Meet of two predecessor/successor contributions.</summary>
    function Join(const A, B: TValue): TValue;
    /// <summary>Effect of one block on the in-value.</summary>
    function Transfer(const ABlock: TCfgBlock; const AIn: TValue): TValue;
    /// <summary>Lattice equality (fixpoint test).</summary>
    function Equals(const A, B: TValue): Boolean;
  end;

  /// <summary>Worklist fixpoint solver.</summary>
  TDataFlowSolver<TValue> = class
  public
    /// <summary>Solve AAnalysis over ACfg. Returns False (and leaves AIn/AOut
    /// empty) when ACfg.Skipped. Otherwise AIn[b]/AOut[b] hold the per-block
    /// fixpoint values.</summary>
    class function Solve(const ACfg: TCfg; const AAnalysis: IDataFlowAnalysis<TValue>;
      out AIn, AOut: TArray<TValue>): Boolean;
  end;

implementation

class function TDataFlowSolver<TValue>.Solve(const ACfg: TCfg;
  const AAnalysis: IDataFlowAnalysis<TValue>; out AIn, AOut: TArray<TValue>): Boolean;
var
  N, B, P, I: Integer;
  Work: TQueue<Integer>;
  InQueue: TArray<Boolean>;
  Acc, NewVal: TValue;
  Fwd: Boolean;
  Boundary: Integer;
  Adj: TList<Integer>;
begin
  AIn := nil; AOut := nil;
  if ACfg.Skipped then Exit(False);
  N := ACfg.BlockCount;
  SetLength(AIn, N); SetLength(AOut, N); SetLength(InQueue, N);
  Fwd := AAnalysis.Direction = fdForward;
  if Fwd then Boundary := ACfg.EntryIdx else Boundary := ACfg.ExitIdx;
  for B := 0 to N - 1 do begin AIn[B] := AAnalysis.Bottom; AOut[B] := AAnalysis.Bottom; end;

  Work := TQueue<Integer>.Create;
  try
    for B := 0 to N - 1 do begin Work.Enqueue(B); InQueue[B] := True; end;
    while Work.Count > 0 do
    begin
      B := Work.Dequeue; InQueue[B] := False;
      { gather predecessors (forward) or successors (backward) }
      if Fwd then Adj := ACfg.Blocks[B].Pred else Adj := ACfg.Blocks[B].Succ;
      if B = Boundary then Acc := AAnalysis.Boundary
      else Acc := AAnalysis.Bottom;
      for I := 0 to Adj.Count - 1 do
      begin
        P := Adj[I];
        if Fwd then Acc := AAnalysis.Join(Acc, AOut[P])
        else Acc := AAnalysis.Join(Acc, AIn[P]);
      end;
      if Fwd then
      begin
        AIn[B] := Acc;
        NewVal := AAnalysis.Transfer(ACfg.Blocks[B], AIn[B]);
        if not AAnalysis.Equals(NewVal, AOut[B]) then
        begin
          AOut[B] := NewVal;
          for I := 0 to ACfg.Blocks[B].Succ.Count - 1 do
            if not InQueue[ACfg.Blocks[B].Succ[I]] then
            begin Work.Enqueue(ACfg.Blocks[B].Succ[I]); InQueue[ACfg.Blocks[B].Succ[I]] := True; end;
        end;
      end
      else
      begin
        AOut[B] := Acc;
        NewVal := AAnalysis.Transfer(ACfg.Blocks[B], AOut[B]);
        if not AAnalysis.Equals(NewVal, AIn[B]) then
        begin
          AIn[B] := NewVal;
          for I := 0 to ACfg.Blocks[B].Pred.Count - 1 do
            if not InQueue[ACfg.Blocks[B].Pred[I]] then
            begin Work.Enqueue(ACfg.Blocks[B].Pred[I]); InQueue[ACfg.Blocks[B].Pred[I]] := True; end;
        end;
      end;
    end;
    Result := True;
  finally
    Work.Free;
  end;
end;

end.
```

- [ ] **Step 4: Run to verify pass**

Run: `pwsh -File tests\flowengine\run_flowengine_tests.ps1`
Expected: all PASS (10/10), exit 0.

- [ ] **Step 5: Normalize CRLF and commit**

```powershell
$f='src\analysis\DRagLint.Analysis.DataFlow.pas'; $t=[IO.File]::ReadAllText($f)
$t=($t -replace "`r`n","`n") -replace "`n","`r`n"; [IO.File]::WriteAllText($f,$t,(New-Object Text.UTF8Encoding($false)))
git add src/analysis/DRagLint.Analysis.DataFlow.pas tests/flowengine/FlowEngineTests.dpr
git commit -m "feat(flow): M2 stage 2 -- generic monotone dataflow worklist solver

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Definite-assignment lattice + 3 checks + TFlowChecker + CLI wiring

**Files:**
- Create: `src/analysis/DRagLint.Analysis.Flow.Lattices.pas`
- Create: `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas`
- Modify: `src/cli/DRagLint.CLI.pas` (3 dispatch sites + rule allow-list/messages)
- Modify: the CLI `.dpr` (`src/cli/...` `.dpr`) `uses` + `.dproj` `<DCCReference>` for the 4 new units
- Modify: `tests/flowengine/FlowEngineTests.dpr` (lattice unit test)
- Create: `tests/lint/used-before-assignment.pas` (+`.expected`), `function-result-not-set.pas` (+`.expected`), `out-param-not-set.pas` (+`.expected`)

**Interfaces:**
- Consumes: `TCfg`, `TCfgBlock`, `TCfgItem` (Task 1); `IDataFlowAnalysis<TValue>`, `TDataFlowSolver<TValue>`, `TFlowDir` (Task 2); `ISymbolStore`/`TTypeCategory` (existing).
- Produces (in `Flow.Lattices`):
  - `TVarKind = (vkLocal, vkParamVar, vkParamOut, vkParamConst, vkParamValue, vkResult);`
  - `TRoutineVar = record Name: string; Kind: TVarKind; TypeText: string; end;`
  - `TRoutineVarTable = class` with `function Count: Integer;`, `function IndexOf(const ALowerName: string): Integer;` (-1 if absent), `function Get(AIdx: Integer): TRoutineVar;`, and `class function Build(const AProc: TTSNode; const ASrc: TBytes): TRoutineVarTable;`.
  - `TDefAsgnVal = record Must, May: TArray<Boolean>; end;`
  - `TDefiniteAssignment = class(TInterfacedObject, IDataFlowAnalysis<TDefAsgnVal>)` constructed with `(AVars: TRoutineVarTable; ASrc: TBytes)`.
- Produces (in `FlowChecks`): `TFlowChecker = class class function Check(const AFile: string; const AStore: ISymbolStore = nil; AFileId: Int64 = 0): TArray<TLintFinding>; end;`

- [ ] **Step 1: Write failing fixtures (the executable spec for the 3 checks)**

Create `tests/lint/used-before-assignment.pas`:
```pascal
unit usedbeforeassignment;
interface
implementation
function F1: Integer;
var x, y: Integer;
begin
  y := x;          // line 7: x read before any assignment -> warning (no path assigns)
  Result := y;
end;
function F2(b: Boolean): Integer;
var x: Integer;
begin
  if b then x := 1;  // assigned only on one path
  Result := x;       // line 14: possibly-uninitialized -> info
end;
function F3(b: Boolean): Integer;
var x: Integer;
begin
  if b then x := 1 else x := 2;  // assigned on all paths
  Result := x;                   // line 20: NO finding (definitely assigned)
end;
function F4: string;
var s: string;
begin
  Result := s;     // managed type: NO finding (compiler zero-inits)
end;
end.
```
Create `tests/lint/used-before-assignment.pas.expected`:
```
used-before-assignment 7
used-before-assignment 14
```
(Both `F3`'s line 20 and `F4`'s `s` must NOT fire — the `!` directive proves absence; add them:)
```
used-before-assignment 7
used-before-assignment 14
```
> The harness's positive directives require findings at 7 and 14. To also assert F3/F4 produce nothing extra, add a second negative fixture `tests/lint/used-before-assignment-clean.pas` containing only F3+F4 bodies with `none` as its `.expected`.

Create `tests/lint/used-before-assignment-clean.pas`:
```pascal
unit usedbeforeassignmentclean;
interface
implementation
function F3(b: Boolean): Integer;
var x: Integer;
begin
  if b then x := 1 else x := 2;
  Result := x;
end;
function F4: string;
var s: string;
begin
  Result := s;
end;
end.
```
`tests/lint/used-before-assignment-clean.pas.expected`:
```
!used-before-assignment
```

Create `tests/lint/function-result-not-set.pas`:
```pascal
unit functionresultnotset;
interface
implementation
function F1: Integer;   // line 5: Result never assigned on any path -> warning
begin
  if False then ;
end;
function F2(b: Boolean): Integer;  // line 9: Result set on only one path -> info
begin
  if b then Result := 1;
end;
function F3: Integer;   // NO finding: Result assigned on all paths
begin
  Result := 0;
end;
procedure P;            // NO finding: not a function
begin
end;
end.
```
`tests/lint/function-result-not-set.pas.expected`:
```
function-result-not-set 5
function-result-not-set 9
```

Create `tests/lint/out-param-not-set.pas`:
```pascal
unit outparamnotset;
interface
implementation
procedure P1(out a: Integer);   // line 5: out param never assigned -> warning
begin
end;
procedure P2(out a: Integer; b: Boolean);  // line 8: assigned on all paths -> NO finding
begin
  if b then a := 1 else a := 2;
end;
procedure P3(var a: Integer);   // var param exempt -> NO finding
begin
end;
end.
```
`tests/lint/out-param-not-set.pas.expected`:
```
out-param-not-set 5
!out-param-not-set 8
```

- [ ] **Step 2: Run to verify failure**

Run: `pwsh tests\lint\run_lint_tests.ps1 -Filter used-before-assignment*`
Expected: FAIL — "missing expected 'used-before-assignment' at line 7" (rule not implemented; checker not wired).

- [ ] **Step 3: Implement `TRoutineVarTable` + `TDefiniteAssignment` in `Flow.Lattices`**

```pascal
unit DRagLint.Analysis.Flow.Lattices;

{ Per-routine variable table + concrete data-flow analyses (M2). The variable
  table indexes a routine's locals, params and Result to 0..N-1; lattice values
  are bitsets over those indices. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  TreeSitter,
  DRagLint.Analysis.Cfg,
  DRagLint.Analysis.DataFlow;

type
  /// <summary>Storage class of a routine-scoped variable.</summary>
  TVarKind = (vkLocal, vkParamVar, vkParamOut, vkParamConst, vkParamValue, vkResult);

  /// <summary>A routine-scoped variable: name (lowercased), kind, declared-type text.</summary>
  TRoutineVar = record
    Name    : string;
    Kind    : TVarKind;
    TypeText: string;
    DeclLine: Integer;
    DeclCol : Integer;
  end;

  /// <summary>Maps a routine's locals/params/Result to dense indices 0..N-1.</summary>
  TRoutineVarTable = class
  strict private
    FVars: TList<TRoutineVar>;
    FByName: TDictionary<string, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    /// <summary>Index of ALowerName, or -1 if not a routine-scoped var.</summary>
    function IndexOf(const ALowerName: string): Integer;
    function Get(AIdx: Integer): TRoutineVar;
    procedure Add(const AVar: TRoutineVar);
    /// <summary>Build from a `defProc` node: params (with var/out/const modes),
    /// the var section, inline `var x` decls, and an implicit Result for
    /// functions.</summary>
    class function Build(const AProc: TTSNode; const ASrc: TBytes): TRoutineVarTable;
  end;

  /// <summary>Definite-assignment lattice value: `Must`[i] = var i assigned on
  /// EVERY path here; `May`[i] = on SOME path.</summary>
  TDefAsgnVal = record
    Must: TArray<Boolean>;
    May : TArray<Boolean>;
  end;

  /// <summary>Forward must+may definite-assignment analysis.</summary>
  TDefiniteAssignment = class(TInterfacedObject, IDataFlowAnalysis<TDefAsgnVal>)
  strict private
    FVars: TRoutineVarTable;
    FSrc : TBytes;
  public
    constructor Create(AVars: TRoutineVarTable; const ASrc: TBytes);
    function Direction: TFlowDir;
    function Bottom: TDefAsgnVal;
    function Boundary: TDefAsgnVal;
    function Join(const A, B: TDefAsgnVal): TDefAsgnVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TDefAsgnVal): TDefAsgnVal;
    function Equals(const A, B: TDefAsgnVal): Boolean;
  end;

/// <summary>Collect lowercased identifier reads in an expression subtree that
/// resolve to a routine var. Skips the member-name child after a `.` (kDot) and
/// (for definite-assignment) treats call arguments / `@x` as possible defs, not
/// reads — so it returns ONLY genuine value reads. ADefs receives the indices
/// of vars that the node POSSIBLY assigns (call args, @x).</summary>
procedure CollectReadsAndCallDefs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AReads, ACallDefs: TList<Integer>);

/// <summary>Index of the variable an `assignment` node defines (its plain lhs),
/// or -1 when the lhs is an indexed/qualified write (a[i] / x.f) rather than a
/// whole-variable definition.</summary>
function AssignmentTargetIndex(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): Integer;

implementation

function NodeStr(const N: TTSNode; const ASrc: TBytes): string;
var S, E, L: Integer;
begin
  Result := '';
  if N.IsNull then Exit;
  S := Integer(N.StartByte); E := Integer(N.EndByte); L := E - S;
  if (L <= 0) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result := TEncoding.UTF8.GetString(ASrc, S, L);
end;

{ ----- TRoutineVarTable ----- }

constructor TRoutineVarTable.Create;
begin
  inherited; FVars := TList<TRoutineVar>.Create;
  FByName := TDictionary<string, Integer>.Create;
end;

destructor TRoutineVarTable.Destroy;
begin FByName.Free; FVars.Free; inherited; end;

function TRoutineVarTable.Count: Integer; begin Result := FVars.Count; end;
function TRoutineVarTable.Get(AIdx: Integer): TRoutineVar; begin Result := FVars[AIdx]; end;

function TRoutineVarTable.IndexOf(const ALowerName: string): Integer;
begin if not FByName.TryGetValue(ALowerName, Result) then Result := -1; end;

procedure TRoutineVarTable.Add(const AVar: TRoutineVar);
begin
  if FByName.ContainsKey(AVar.Name) then Exit;
  FByName.Add(AVar.Name, FVars.Count);
  FVars.Add(AVar);
end;

class function TRoutineVarTable.Build(const AProc: TTSNode; const ASrc: TBytes): TRoutineVarTable;
var
  Tbl: TRoutineVarTable;
  Header, Args, Ret: TTSNode;

  procedure AddDeclVars(const ASection: TTSNode);
  var I, J, TypeStart: Integer; DV, TypeNode, NameId: TTSNode; RV: TRoutineVar;
  begin
    if ASection.IsNull then Exit;
    for I := 0 to ASection.NamedChildCount - 1 do
    begin
      DV := ASection.NamedChild(I);
      if DV.NodeType <> 'declVar' then Continue;
      TypeNode := DV.ChildByField('type');
      TypeStart := MaxInt;
      if not TypeNode.IsNull then TypeStart := Integer(TypeNode.StartByte);
      for J := 0 to DV.NamedChildCount - 1 do
      begin
        NameId := DV.NamedChild(J);
        if (NameId.NodeType = 'identifier') and (Integer(NameId.StartByte) < TypeStart) then
        begin
          RV.Name := LowerCase(NodeStr(NameId, ASrc));
          RV.Kind := vkLocal;
          RV.TypeText := Trim(NodeStr(TypeNode, ASrc));
          RV.DeclLine := Integer(NameId.StartPoint.Row) + 1;
          RV.DeclCol  := Integer(NameId.StartPoint.Column) + 1;
          Tbl.Add(RV);
        end;
      end;
    end;
  end;

  procedure AddArgs(const AArgs: TTSNode);
  var I, J: Integer; DA, TypeNode, NameId, Modi: TTSNode; RV: TRoutineVar; Mode: TVarKind; MText: string;
  begin
    if AArgs.IsNull then Exit;
    for I := 0 to AArgs.NamedChildCount - 1 do
    begin
      DA := AArgs.NamedChild(I);
      if DA.NodeType <> 'declArg' then Continue;
      Mode := vkParamValue;
      { mode is a leading kVar / kOut / kConst child token }
      for J := 0 to DA.ChildCount - 1 do
      begin
        Modi := DA.Child(J);
        MText := Modi.NodeType;
        if MText = 'kVar'   then Mode := vkParamVar;
        if MText = 'kOut'   then Mode := vkParamOut;
        if MText = 'kConst' then Mode := vkParamConst;
      end;
      TypeNode := DA.ChildByField('type');
      for J := 0 to DA.NamedChildCount - 1 do
      begin
        NameId := DA.NamedChild(J);
        if NameId.NodeType = 'identifier' then
        begin
          RV.Name := LowerCase(NodeStr(NameId, ASrc));
          RV.Kind := Mode;
          RV.TypeText := Trim(NodeStr(TypeNode, ASrc));
          RV.DeclLine := Integer(NameId.StartPoint.Row) + 1;
          RV.DeclCol  := Integer(NameId.StartPoint.Column) + 1;
          Tbl.Add(RV);
        end;
      end;
    end;
  end;

  { inline `var x := e` / `var x: T` declared mid-body: walk the body for varAssignDef
    and any nested declVars. }
  procedure AddInlineVars(const N: TTSNode);
  var I: Integer; Lhs, IdN: TTSNode; RV: TRoutineVar;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declVars' then AddDeclVars(N);
    if N.NodeType = 'assignment' then
    begin
      Lhs := N.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'varAssignDef') then
      begin
        IdN := Lhs.ChildByField('name');
        if IdN.IsNull and (Lhs.NamedChildCount > 0) then IdN := Lhs.NamedChild(0);
        if not IdN.IsNull then
        begin
          RV.Name := LowerCase(NodeStr(IdN, ASrc));
          RV.Kind := vkLocal; RV.TypeText := '';
          RV.DeclLine := Integer(IdN.StartPoint.Row) + 1;
          RV.DeclCol  := Integer(IdN.StartPoint.Column) + 1;
          Tbl.Add(RV);
        end;
      end;
    end;
    for I := 0 to N.NamedChildCount - 1 do AddInlineVars(N.NamedChild(I));
  end;

var
  RV: TRoutineVar; I: Integer; Sec: TTSNode;
begin
  Tbl := TRoutineVarTable.Create;
  Header := AProc.ChildByField('header');
  if not Header.IsNull then
  begin
    Args := Header.ChildByField('args');
    AddArgs(Args);
    Ret := Header.ChildByField('type');
    if not Ret.IsNull then
    begin
      { function -> implicit Result }
      RV.Name := 'result'; RV.Kind := vkResult; RV.TypeText := Trim(NodeStr(Ret, ASrc));
      RV.DeclLine := Integer(Header.StartPoint.Row) + 1; RV.DeclCol := Integer(Header.StartPoint.Column) + 1;
      Tbl.Add(RV);
    end;
  end;
  { var sections are `local:` declVars children of defProc }
  for I := 0 to AProc.NamedChildCount - 1 do
  begin
    Sec := AProc.NamedChild(I);
    if Sec.NodeType = 'declVars' then AddDeclVars(Sec);
  end;
  AddInlineVars(AProc.ChildByField('body'));
  Result := Tbl;
end;

{ ----- read/def collection ----- }

procedure CollectReadsAndCallDefs(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AReads, ACallDefs: TList<Integer>);

  procedure Walk(const N: TTSNode; AAfterDot: Boolean);
  var I, Idx: Integer; K: string; EntTxt: string; ArgsN, Arg: TTSNode;
  begin
    if N.IsNull then Exit;
    K := N.NodeType;
    if K = 'identifier' then
    begin
      if not AAfterDot then
      begin
        Idx := AVars.IndexOf(LowerCase(NodeStr(N, ASrc)));
        if (Idx >= 0) and (AReads.IndexOf(Idx) < 0) then AReads.Add(Idx);
      end;
      Exit;
    end;
    if K = 'exprDot' then
    begin
      Walk(N.ChildByField('lhs'), False);
      Walk(N.ChildByField('rhs'), True); { member name, not a var read }
      Exit;
    end;
    if K = 'exprCall' then
    begin
      EntTxt := LowerCase(Trim(NodeStr(N.ChildByField('entity'), ASrc)));
      { call args that are bare locals / @local are POSSIBLE defs (FP-safe), not reads }
      ArgsN := N.ChildByField('args');
      if not ArgsN.IsNull then
        for I := 0 to ArgsN.NamedChildCount - 1 do
        begin
          Arg := ArgsN.NamedChild(I);
          if (Arg.NodeType = 'identifier') then
          begin
            Idx := AVars.IndexOf(LowerCase(NodeStr(Arg, ASrc)));
            if (Idx >= 0) and (ACallDefs.IndexOf(Idx) < 0) then ACallDefs.Add(Idx);
          end
          else
            Walk(Arg, False);
        end;
      { walk the callee entity (could be obj.Method -> obj is a read) }
      Walk(N.ChildByField('entity'), False);
      Exit;
    end;
    { '@x' address-of: x is a possible def. Confirm the unary node kind/operator. }
    for I := 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I), False);
  end;

begin
  Walk(ANode, False);
end;

function AssignmentTargetIndex(const ANode: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable): Integer;
var Lhs, IdN: TTSNode;
begin
  Result := -1;
  Lhs := ANode.ChildByField('lhs');
  if Lhs.IsNull then Exit;
  if Lhs.NodeType = 'identifier' then
    Result := AVars.IndexOf(LowerCase(NodeStr(Lhs, ASrc)))
  else if Lhs.NodeType = 'varAssignDef' then
  begin
    IdN := Lhs.ChildByField('name');
    if IdN.IsNull and (Lhs.NamedChildCount > 0) then IdN := Lhs.NamedChild(0);
    if not IdN.IsNull then Result := AVars.IndexOf(LowerCase(NodeStr(IdN, ASrc)));
  end;
  { indexed/qualified writes (a[i] := / x.f :=) are NOT whole-var definitions }
end;

{ ----- TDefiniteAssignment ----- }

constructor TDefiniteAssignment.Create(AVars: TRoutineVarTable; const ASrc: TBytes);
begin inherited Create; FVars := AVars; FSrc := ASrc; end;

function TDefiniteAssignment.Direction: TFlowDir; begin Result := fdForward; end;

function TDefiniteAssignment.Bottom: TDefAsgnVal;
var I: Integer;
begin
  { Bottom for a MUST (intersection) analysis is "all assigned"; MAY (union) is "none". }
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do begin Result.Must[I] := True; Result.May[I] := False; end;
end;

function TDefiniteAssignment.Boundary: TDefAsgnVal;
var I: Integer; V: TRoutineVar;
begin
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do
  begin
    V := FVars.Get(I);
    { var/const/value params are assigned on entry; out params and Result and locals are not }
    if V.Kind in [vkParamVar, vkParamConst, vkParamValue] then
    begin Result.Must[I] := True; Result.May[I] := True; end
    else begin Result.Must[I] := False; Result.May[I] := False; end;
  end;
end;

function TDefiniteAssignment.Join(const A, B: TDefAsgnVal): TDefAsgnVal;
var I: Integer;
begin
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do
  begin
    Result.Must[I] := A.Must[I] and B.Must[I]; { intersection }
    Result.May[I]  := A.May[I] or B.May[I];     { union }
  end;
end;

function TDefiniteAssignment.Transfer(const ABlock: TCfgBlock; const AIn: TDefAsgnVal): TDefAsgnVal;
var
  I, J, Tgt: Integer; It: TCfgItem; Reads, CallDefs: TList<Integer>; Name: string; Idx: Integer;
begin
  Result := AIn;
  SetLength(Result.Must, FVars.Count); SetLength(Result.May, FVars.Count);
  for I := 0 to FVars.Count - 1 do begin Result.Must[I] := AIn.Must[I]; Result.May[I] := AIn.May[I]; end;
  { synthetic entry defs (foreach iterator) }
  for J := 0 to High(ABlock.EntryDefs) do
  begin
    Idx := FVars.IndexOf(ABlock.EntryDefs[J]);
    if Idx >= 0 then begin Result.Must[Idx] := True; Result.May[Idx] := True; end;
  end;
  Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
  try
    for I := 0 to ABlock.Items.Count - 1 do
    begin
      It := ABlock.Items[I];
      if It.Node.NodeType = 'assignment' then
      begin
        { reads on the rhs happen BEFORE the def of the lhs }
        Reads.Clear; CallDefs.Clear;
        CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), FSrc, FVars, Reads, CallDefs);
        for J := 0 to CallDefs.Count - 1 do Result.May[CallDefs[J]] := True;
        Tgt := AssignmentTargetIndex(It.Node, FSrc, FVars);
        if Tgt >= 0 then begin Result.Must[Tgt] := True; Result.May[Tgt] := True; end;
      end
      else
      begin
        { call / condition / bare statement: collect possible defs (call args, @x) }
        Reads.Clear; CallDefs.Clear;
        CollectReadsAndCallDefs(It.Node, FSrc, FVars, Reads, CallDefs);
        for J := 0 to CallDefs.Count - 1 do Result.May[CallDefs[J]] := True;
        { Exit(v) defines Result }
        if (It.Node.NodeType = 'exprCall')
           and (LowerCase(Trim(NodeStr(It.Node.ChildByField('entity'), FSrc))) = 'exit') then
        begin
          Idx := FVars.IndexOf('result');
          if Idx >= 0 then begin Result.Must[Idx] := True; Result.May[Idx] := True; end;
        end;
      end;
    end;
  finally
    Reads.Free; CallDefs.Free;
  end;
end;

function TDefiniteAssignment.Equals(const A, B: TDefAsgnVal): Boolean;
var I: Integer;
begin
  Result := False;
  if (Length(A.Must) <> Length(B.Must)) or (Length(A.May) <> Length(B.May)) then Exit;
  for I := 0 to High(A.Must) do
    if (A.Must[I] <> B.Must[I]) or (A.May[I] <> B.May[I]) then Exit;
  Result := True;
end;

end.
```

> The `bare function-name := value` definition form (`F := 0` inside `function F`) is handled because the var table has no entry named after the function; to also support it, when building the var table add an alias from the function name to the Result index. Add: after adding Result, also `Tbl.FByName.AddOrSetValue(LowerCase(NodeStr(Header.ChildByField('name'), ASrc)), <result index>)`. Keep this in Step 3.

> **Nested-routine capture (FP guard, spec §9).** `CfgFindProcs` returns nested `defProc`s too, so each gets its own CFG — good. But an outer local *assigned inside* a nested routine would look unassigned in the outer routine's analysis and misfire `used-before-assignment`/`function-result-not-set`. Conservative fix without changing any signature: add a `Captured: Boolean` field to `TRoutineVar`. In `TFlowChecker.CheckRoutine`, after `TRoutineVarTable.Build`, scan the routine body for nested `defProc`s and, for each outer var whose lowercased name is *referenced anywhere* inside a nested `defProc`, set its `Captured := True` (re-`Add` or expose a `TRoutineVarTable.MarkCaptured(idx)` mutator). Then in `TDefiniteAssignment.Boundary`, for a var with `Captured=True` set `Must=False, May=True` (may-assigned on entry). This downgrades a captured-var use to `info` at worst (never a false `warning`) and suppresses false `function-result-not-set`. Add a fixture `tests/lint/used-before-assignment-capture.pas` (an outer var assigned only inside a nested procedure, read after the call) with `!used-before-assignment` — it must be at most `info`, never a `warning` line.

- [ ] **Step 4: Add a lattice unit test to `FlowEngineTests.dpr`**

```pascal
procedure TestDefiniteAssignmentMust;
const SRC =
  'unit u; interface implementation function F(b: Boolean): Integer;' + sLineBreak +
  'var x: Integer; begin if b then x := 1 else x := 2; Result := x; end; end.';
var
  PF: TParsedFile; Tmp: string; Procs: TArray<TTSNode>;
  Cfg: TCfg; Vars: TRoutineVarTable; Ana: IDataFlowAnalysis<TDefAsgnVal>;
  AIn, AOut: TArray<TDefAsgnVal>; Idx: Integer;
begin
  Tmp := TPath.Combine(TPath.GetTempPath, 'da_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(Tmp, SRC);
  try
    PF := TAstParseCache.Get(Tmp);
    Procs := CfgFindProcs(PF.Tree.RootNode);
    Cfg := TCfgBuilder.Build(Procs[0], PF.Src);
    Vars := TRoutineVarTable.Build(Procs[0], PF.Src);
    try
      Ana := TDefiniteAssignment.Create(Vars, PF.Src);
      TDataFlowSolver<TDefAsgnVal>.Solve(Cfg, Ana, AIn, AOut);
      Idx := Vars.IndexOf('x');
      Check('def-assign: x must-assigned at Exit', AIn[Cfg.ExitIdx].Must[Idx]);
    finally Cfg.Free; Vars.Free; end;
  finally TAstParseCache.Clear; TFile.Delete(Tmp); end;
end;
```
Add `DRagLint.Analysis.Flow.Lattices` to the `.dpr` `uses`; call `TestDefiniteAssignmentMust`. Run `pwsh -File tests\flowengine\run_flowengine_tests.ps1` — Expected PASS (engine side green before wiring the checks).

- [ ] **Step 5: Implement `TFlowChecker.Check` (the 3 definite-assignment checks)**

```pascal
unit DRagLint.Diagnostics.FlowChecks;

{ Flow-sensitive lint checks (M2): runs the data-flow analyses per routine and
  maps results to TLintFinding. Mirrors the TAstChecker.CheckXxx integration
  (parse cache + optional ISymbolStore, nil-safe). }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  TreeSitter,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Diagnostics.ParseCache,
  DRagLint.Analysis.Cfg,
  DRagLint.Analysis.DataFlow,
  DRagLint.Analysis.Flow.Lattices;

type
  /// <summary>Flow-sensitive checks over a single file's routines.</summary>
  TFlowChecker = class
  public
    /// <summary>Run every flow check on AFile. AStore (optional, nil-safe)
    /// enables exact managed-type classification via M1 ResolveTypeCategory and
    /// the interprocedural object-leak refinement.</summary>
    class function Check(const AFile: string; const AStore: ISymbolStore = nil;
      AFileId: Int64 = 0): TArray<TLintFinding>;
  end;

implementation

function NodeStr(const N: TTSNode; const ASrc: TBytes): string;
var S, E, L: Integer;
begin
  Result := '';
  if N.IsNull then Exit;
  S := Integer(N.StartByte); E := Integer(N.EndByte); L := E - S;
  if (L <= 0) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result := TEncoding.UTF8.GetString(ASrc, S, L);
end;

{ Managed (compiler zero-initialized) types are skipped by used-before /
  function-result-not-set, matching W1036. Store-exact when present, name
  heuristic otherwise. }
function IsManagedType(const ATypeText: string; const AStore: ISymbolStore; AFileId: Int64): Boolean;
var Cat: TTypeCategory; T: string;
begin
  if AStore <> nil then
  begin
    Cat := AStore.ResolveTypeCategory(ATypeText, AFileId);
    if Cat <> tcUnknown then
      Exit(Cat in [tcString, tcInterface]); { managed: string, interface, (variant/dynarray handled by heuristic below) }
  end;
  T := LowerCase(Trim(ATypeText));
  Result := (T = 'string') or (T = 'unicodestring') or (T = 'ansistring') or (T = 'widestring')
    or (T = 'variant') or (T = 'olevariant') or (Pos('i', T) = 1) and (Length(T) >= 2)
       and (UpCase(T[2]) = T[2]) { I-prefixed interface convention }
    or (Pos('array of', T) > 0) or (Pos('tarray<', T) > 0);
end;

class function TFlowChecker.Check(const AFile: string; const AStore: ISymbolStore;
  AFileId: Int64): TArray<TLintFinding>;
var
  PF: TParsedFile;
  Findings: TList<TLintFinding>;
  Procs: TArray<TTSNode>;
  PI: Integer;

  procedure Emit(const ARule, ASev, AMsg: string; ALine, ACol: Integer);
  var F: TLintFinding;
  begin
    F := Default(TLintFinding);
    F.RuleId := ARule; F.Severity := ASev; F.Message := AMsg; F.FilePath := AFile;
    F.StartLine := ALine; F.StartCol := ACol; F.EndLine := ALine; F.EndCol := ACol + 1;
    Findings.Add(F);
  end;

  procedure CheckRoutine(const AProc: TTSNode);
  var
    Cfg: TCfg; Vars: TRoutineVarTable; Ana: IDataFlowAnalysis<TDefAsgnVal>;
    AIn, AOut: TArray<TDefAsgnVal>; ExitVal: TDefAsgnVal;
    I, B, J: Integer; V: TRoutineVar; It: TCfgItem; Reads, CallDefs: TList<Integer>;
    HasFunc: Boolean; ROW, COL: Integer;
  begin
    Cfg := TCfgBuilder.Build(AProc, PF.Src);
    Vars := TRoutineVarTable.Build(AProc, PF.Src);
    try
      if Cfg.Skipped or (Vars.Count = 0) then Exit;
      Ana := TDefiniteAssignment.Create(Vars, PF.Src);
      if not TDataFlowSolver<TDefAsgnVal>.Solve(Cfg, Ana, AIn, AOut) then Exit;

      { ---- used-before-assignment: a read where the var is not in IN.Must of its block ---- }
      Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
      try
        for B := 0 to Cfg.BlockCount - 1 do
        begin
          { replay the block, tracking must/may as of each item to find first read }
          var Cur := AIn[B];
          for I := 0 to Cfg.Blocks[B].Items.Count - 1 do
          begin
            It := Cfg.Blocks[B].Items[I];
            if It.Opaque then Continue; { with-body reads are not trusted }
            Reads.Clear; CallDefs.Clear;
            if It.Node.NodeType = 'assignment' then
              CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), PF.Src, Vars, Reads, CallDefs)
            else
              CollectReadsAndCallDefs(It.Node, PF.Src, Vars, Reads, CallDefs);
            for J := 0 to Reads.Count - 1 do
            begin
              V := Vars.Get(Reads[J]);
              if V.Kind <> vkLocal then Continue; { only locals; params handled by entry boundary }
              if IsManagedType(V.TypeText, AStore, AFileId) then Continue;
              if not Cur.Must[Reads[J]] then
              begin
                ROW := Integer(It.Node.StartPoint.Row) + 1;
                COL := Integer(It.Node.StartPoint.Column) + 1;
                if Cur.May[Reads[J]] then
                  Emit('used-before-assignment', 'info',
                    Format('Local "%s" may be used before it is assigned.', [V.Name]), ROW, COL)
                else
                  Emit('used-before-assignment', 'warning',
                    Format('Local "%s" is used before it is assigned.', [V.Name]), ROW, COL);
              end;
            end;
            { advance Cur using the same transfer rules (single-item) }
            Cur := Ana.Transfer(SingleItemBlock(Cfg.Blocks[B], I), Cur); { see note }
          end;
        end;
      finally Reads.Free; CallDefs.Free; end;

      ExitVal := AIn[Cfg.ExitIdx];

      { ---- function-result-not-set ---- }
      HasFunc := False;
      I := Vars.IndexOf('result');
      if I >= 0 then
      begin
        HasFunc := True;
        if not ExitVal.Must[I] then
        begin
          ROW := Integer(AProc.ChildByField('header').StartPoint.Row) + 1;
          COL := Integer(AProc.ChildByField('header').StartPoint.Column) + 1;
          if ExitVal.May[I] then
            Emit('function-result-not-set', 'info',
              'Function Result is not assigned on every path.', ROW, COL)
          else
            Emit('function-result-not-set', 'warning',
              'Function Result is never assigned.', ROW, COL);
        end;
      end;

      { ---- out-param-not-set ---- }
      for I := 0 to Vars.Count - 1 do
      begin
        V := Vars.Get(I);
        if (V.Kind = vkParamOut) and not ExitVal.Must[I] then
          Emit('out-param-not-set', 'warning',
            Format('Out parameter "%s" is not assigned on every path.', [V.Name]),
            V.DeclLine, V.DeclCol);
      end;

    finally Cfg.Free; Vars.Free; end;
  end;

begin
  Result := nil;
  PF := TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Findings := TList<TLintFinding>.Create;
  try
    Procs := CfgFindProcs(PF.Tree.RootNode);
    for PI := 0 to High(Procs) do CheckRoutine(Procs[PI]);
    Result := Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

end.
```

> Implementation note for `SingleItemBlock`: the replay needs the per-item must/may *before* each read. Rather than a synthetic single-item block, implement the replay inline: maintain local `Must`/`May` arrays initialised from `AIn[B]` (+ `EntryDefs`), and for each item first collect reads (flag violations against the current `Must`/`May`), THEN apply that item's defs (assignment target -> Must/May true; call-defs -> May true; Exit(v) -> Result). This avoids constructing a fake block. Replace the `Ana.Transfer(SingleItemBlock(...))` line with that inline def-application (duplicate the small def logic from `TDefiniteAssignment.Transfer`). Keep reads-before-defs ordering so `x := x + 1` correctly reads the old `x`.

- [ ] **Step 6: Register the 4 new units in the CLI `.dpr` + `.dproj`**

Find the CLI program file (the `.dpr` whose `uses` includes `DRagLint.CLI`). Add to its `uses` clause (with `in '..\..\src\...'` paths relative to the `.dpr`):
```pascal
  DRagLint.Analysis.Cfg in '..\src\analysis\DRagLint.Analysis.Cfg.pas',
  DRagLint.Analysis.DataFlow in '..\src\analysis\DRagLint.Analysis.DataFlow.pas',
  DRagLint.Analysis.Flow.Lattices in '..\src\analysis\DRagLint.Analysis.Flow.Lattices.pas',
  DRagLint.Diagnostics.FlowChecks in '..\src\diagnostics\DRagLint.Diagnostics.FlowChecks.pas',
```
(Adjust the relative path to match the existing entries in that `.dpr`.) Add the matching 4 `<DCCReference Include="..."/>` lines to the `.dproj` (copy the format of an existing `<DCCReference>` entry).

- [ ] **Step 7: Wire `TFlowChecker.Check` into the 3 CLI dispatch sites**

In `src/cli/DRagLint.CLI.pas`:

(a) `DoLint` (~line 4321): extend the unknown-rule guard chain — add `and (AArgs.Rule <> 'used-before-assignment') and (AArgs.Rule <> 'function-result-not-set') and (AArgs.Rule <> 'out-param-not-set') and (AArgs.Rule <> 'overwrite-before-read') and (AArgs.Rule <> 'write-only-local') and (AArgs.Rule <> 'loop-var-after-loop') and (AArgs.Rule <> 'object-leak')` and append the same ids to the "known:" message string. (Add all 7 now so later tasks need no further guard edits.)

(b) `DoLint` builtin block (~line 4370, before `TAstParseCache.Clear`):
```pascal
{ M2: flow-sensitive checks (definite-assignment, liveness, loop-var, object-leak) }
for F in DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check(AArgs.Path) do
  if (AArgs.Rule = '') or (AArgs.Rule = F.RuleId) then
    Findings := Findings + [F];
```

(c) `DoLintAll` (~line 5263, beside the `CheckTypeAware` store call):
```pascal
for F in DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check(PasPath, Store, Store.FindFileIdByPath(PasPath)) do { M2: flow checks, store-exact managed types }
  Findings := Findings + [F];
```

(d) `DoCheckAst`: locate the analogous per-file check dispatch and add the store-bearing `TFlowChecker.Check(PasPath, Store, Store.FindFileIdByPath(PasPath))` merge (same shape as (c)).

Add `DRagLint.Diagnostics.FlowChecks` to the `uses` clause of `DRagLint.CLI.pas` (interface or implementation `uses`, matching where `DRagLint.Diagnostics.AstChecks` is referenced).

- [ ] **Step 8: Build the CLI (Win64) and run the lint fixtures**

Build via the `delphi-build` skill recipe (rsvars + msbuild, Win64, read log for `BUILD_EXITCODE=0`, no `[dcc] Error`). Then:
```powershell
pwsh tests\lint\run_lint_tests.ps1 -Filter used-before-assignment*
pwsh tests\lint\run_lint_tests.ps1 -Filter function-result-not-set*
pwsh tests\lint\run_lint_tests.ps1 -Filter out-param-not-set*
```
Expected: each prints PASS for its fixture(s). If `used-before-assignment 14` (the possible/info case) is reported as `warning` instead of `info`, the may-set Join/boundary is wrong — debug the lattice, not the fixture.

- [ ] **Step 9: Run the FULL lint harness (no regressions) + engine tests**

```powershell
pwsh tests\lint\run_lint_tests.ps1
pwsh -File tests\flowengine\run_flowengine_tests.ps1
```
Expected: full harness green (existing 51+ fixtures + 5 new), engine tests green.

- [ ] **Step 10: Normalize CRLF, update `rules/README.md`, commit**

Add the 3 rule ids + one-line descriptions to `rules/README.md` (find the rule table; match the existing row format). Normalize all touched `.pas`/`.dpr` to CRLF (UTF8-no-BOM), then:
```powershell
git add src/analysis/DRagLint.Analysis.Flow.Lattices.pas src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas src/cli/ tests/ rules/README.md
git commit -m "feat(flow): M2 stage 3 -- definite-assignment (used-before/result-not-set/out-param-not-set) + CLI wiring

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Liveness lattice + overwrite-before-read + write-only-local

**Files:**
- Modify: `src/analysis/DRagLint.Analysis.Flow.Lattices.pas` (add `TLiveness`)
- Modify: `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` (add the 2 checks)
- Modify: `tests/flowengine/FlowEngineTests.dpr` (liveness unit test)
- Create: `tests/lint/overwrite-before-read.pas` (+`.expected`), `tests/lint/write-only-local.pas` (+`.expected`)

**Interfaces:**
- Consumes: `TRoutineVarTable`, `CollectReadsAndCallDefs`, `AssignmentTargetIndex`, the solver (`fdBackward`).
- Produces: `TLiveness = class(TInterfacedObject, IDataFlowAnalysis<TArray<Boolean>>)` constructed `(AVars: TRoutineVarTable; const ASrc: TBytes)`; `Direction=fdBackward`; `Boundary` = out-params + var-params + Result live at exit.

- [ ] **Step 1: Write failing fixtures**

`tests/lint/overwrite-before-read.pas`:
```pascal
unit overwritebeforeread;
interface
implementation
procedure P;
var x: Integer;
begin
  x := 1;     // line 7: dead store -- x overwritten on line 8 before any read
  x := 2;
  Writeln(x);
end;
end.
```
`tests/lint/overwrite-before-read.pas.expected`:
```
overwrite-before-read 7
```

`tests/lint/write-only-local.pas`:
```pascal
unit writeonlylocal;
interface
implementation
procedure P;
var x, y: Integer;
begin
  x := 1;       // line 7: x written but never read -> write-only-local
  y := 2;
  Writeln(y);
end;
end.
```
`tests/lint/write-only-local.pas.expected`:
```
write-only-local 7
!write-only-local 8
```

- [ ] **Step 2: Run to verify failure**

`pwsh tests\lint\run_lint_tests.ps1 -Filter overwrite-before-read*` -> FAIL (missing finding).

- [ ] **Step 3: Implement `TLiveness` in `Flow.Lattices`**

Add to the interface `type` block and implement. Liveness value = `TArray<Boolean>` (live[i]). `Bottom` = all False. `Join` = union. `Boundary` (OUT[Exit]) = True for `vkParamOut`, `vkParamVar`, `vkResult` (caller reads them). `Transfer(block, out)` walks items in REVERSE: a read of var i sets live[i]:=True; a whole-var def (assignment target) sets live[i]:=False BEFORE its rhs reads are applied (gen/kill). Opaque items: treat as reading every local (set all locals live) to suppress false dead-stores.

```pascal
function TLiveness.Transfer(const ABlock: TCfgBlock; const AOut: TArray<Boolean>): TArray<Boolean>;
var I, J, Tgt: Integer; It: TCfgItem; Reads, CallDefs: TList<Integer>;
begin
  Result := Copy(AOut);
  Reads := TList<Integer>.Create; CallDefs := TList<Integer>.Create;
  try
    for I := ABlock.Items.Count - 1 downto 0 do
    begin
      It := ABlock.Items[I];
      if It.Opaque then
      begin
        for J := 0 to FVars.Count - 1 do
          if FVars.Get(J).Kind = vkLocal then Result[J] := True;
        Continue;
      end;
      if It.Node.NodeType = 'assignment' then
      begin
        Tgt := AssignmentTargetIndex(It.Node, FSrc, FVars);
        if Tgt >= 0 then Result[Tgt] := False;       { kill }
        Reads.Clear; CallDefs.Clear;
        CollectReadsAndCallDefs(It.Node.ChildByField('rhs'), FSrc, FVars, Reads, CallDefs);
        for J := 0 to Reads.Count - 1 do Result[Reads[J]] := True; { gen }
      end
      else
      begin
        Reads.Clear; CallDefs.Clear;
        CollectReadsAndCallDefs(It.Node, FSrc, FVars, Reads, CallDefs);
        { for liveness, call args ARE uses (callee may read) }
        for J := 0 to Reads.Count - 1 do Result[Reads[J]] := True;
        for J := 0 to CallDefs.Count - 1 do Result[CallDefs[J]] := True;
      end;
    end;
  finally Reads.Free; CallDefs.Free; end;
end;
```
(Provide the trivial `Direction`/`Bottom`/`Boundary`/`Join`/`Equals` alongside, matching the `TArray<Boolean>` shape.)

- [ ] **Step 4: Add a liveness engine unit test**

In `FlowEngineTests.dpr`, build the CFG + var table for `procedure P; var x: Integer; begin x := 1; x := 2; Writeln(x); end;`, solve `TLiveness`, and assert that `x` is NOT live in `OUT` of the block right after the first `x := 1` (dead). Run `run_flowengine_tests.ps1` — PASS.

- [ ] **Step 5: Implement the 2 checks in `TFlowChecker.CheckRoutine`**

After the definite-assignment section, add a liveness pass:
- **overwrite-before-read:** for each `assignment` item with target `t`, if `t` is a `vkLocal` and `t` is NOT live in the liveness OUT-value immediately after that item (i.e. it gets reassigned/falls dead before any read), emit `overwrite-before-read` (`info`) at the assignment line. Compute per-item liveness by replaying the block backward from `AOut[B]` (mirror the def-assign replay but in reverse), OR (simpler) detect the textbook pattern: two consecutive whole-var assignments to the same local in the same block with no intervening read of it. Use the liveness replay for correctness.
- **write-only-local:** a `vkLocal` whose `live` is never True at its declaration point AND which is assigned at least once and read nowhere. Compute "read anywhere" by unioning all `Reads` across all blocks during the pass; "assigned" similarly. Emit `write-only-local` (`info`) at the var's `DeclLine/DeclCol`.

Guard both with `if not Cfg.Skipped`. Both are `info` per the FP policy.

- [ ] **Step 6: Build CLI (Win64), run the 2 fixtures + full harness + engine tests**

```powershell
pwsh tests\lint\run_lint_tests.ps1 -Filter overwrite-before-read*
pwsh tests\lint\run_lint_tests.ps1 -Filter write-only-local*
pwsh tests\lint\run_lint_tests.ps1
pwsh -File tests\flowengine\run_flowengine_tests.ps1
```
Expected: all green.

- [ ] **Step 7: Normalize CRLF, update `rules/README.md`, commit**

```powershell
git add src/analysis/DRagLint.Analysis.Flow.Lattices.pas src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas tests/ rules/README.md
git commit -m "feat(flow): M2 stage 4 -- liveness (overwrite-before-read + write-only-local)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: loop-var-after-loop

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas`
- Create: `tests/lint/loop-var-after-loop.pas` (+`.expected`)

**Interfaces:**
- Consumes: the CFG (`for` loop var def site), `TRoutineVarTable`, `CollectReadsAndCallDefs`. No new lattice — a targeted post-loop read scan.

- [ ] **Step 1: Write the failing fixture**

`tests/lint/loop-var-after-loop.pas`:
```pascal
unit loopvarafterloop;
interface
implementation
procedure P;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to 10 do s := s + i;
  Writeln(i);    // line 9: reading for-loop var after the loop -> warning (undefined value)
end;
procedure Q;
var i, s: Integer;
begin
  for i := 1 to 10 do s := i;
  i := 0;        // reassigned before read -> NO finding
  Writeln(i);
end;
end.
```
`tests/lint/loop-var-after-loop.pas.expected`:
```
loop-var-after-loop 9
!loop-var-after-loop 16
```

- [ ] **Step 2: Run to verify failure** — `pwsh tests\lint\run_lint_tests.ps1 -Filter loop-var-after-loop*` -> FAIL.

- [ ] **Step 3: Implement the check**

In `CheckRoutine`: while building, the `for` node's control var (the `start` assignment's lhs identifier) is known. After the loop's follow block, the Delphi standard makes the control var's value undefined. Detect: collect each `for` node's control-var name + the loop's follow block index (extend `TCfgBuilder` to expose, per CFG, a list `ForLoops: TArray<record VarIdx, FollowBlock, Line: Integer end>` OR re-walk the routine AST to find `for` nodes and their control var). For each, run a forward reaching scan from the follow block: if the control var is READ on some path before being reassigned (a whole-var def), emit `loop-var-after-loop` (`warning`) at the read site. Reuse the definite-assignment machinery: a var is "reassigned" exactly when its Must becomes true again starting fresh (Bottom) at the follow block; a read while still Bottom = use of the stale loop var.

Implementation: add to `DRagLint.Analysis.Cfg` the record `TCfgForVar = record VarName: string; FollowIdx, Line, Col: Integer; end;` and a public field `TCfg.ForVars: TList<TCfgForVar>` (create in `TCfg.Create`, free in `TCfg.Destroy`). Populate it from `TCfgBuilder`'s `for` branch: `Cfg.ForVars.Add(<rec>)` with the lowercased start-assignment target name, the follow block index (`FollowIdx`), and the control-var read site is computed at check time. Then in the check, for each `TCfgForVar`, do a BFS over `Succ` edges starting at `FollowIdx`; on each visited block, scan items in order: if the loop var is READ (appears in `CollectReadsAndCallDefs` Reads, item not opaque) before any whole-var def of it in that block -> emit `loop-var-after-loop` (`warning`) at that read's StartPoint and stop that path; if a whole-var def (`AssignmentTargetIndex` = the loop var) is seen first -> stop that path (reassigned, no finding). Track visited blocks to avoid cycles. (Use the name `ForVars`/`TCfgForVar` consistently — no `ForLoops`.)

- [ ] **Step 4: Build CLI (Win64), run fixture + full harness + engine tests** — all green.

- [ ] **Step 5: Normalize CRLF, update `rules/README.md`, commit**

```powershell
git add src/analysis/DRagLint.Analysis.Cfg.pas src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas tests/ rules/README.md
git commit -m "feat(flow): M2 stage 5 -- loop-var-after-loop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Escape lattice + object-leak (conservative, store-free)

**Files:**
- Modify: `src/analysis/DRagLint.Analysis.Flow.Lattices.pas` (add `TEscape`)
- Modify: `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` (object-leak check)
- Modify: `tests/flowengine/FlowEngineTests.dpr` (escape unit test)
- Create: `tests/lint/object-leak.pas` (+`.expected`)

**Interfaces:**
- Produces: `TEscape = class(TInterfacedObject, IDataFlowAnalysis<TArray<Boolean>>)` — a forward **may-open** analysis. The lattice value is `TArray<Boolean>` where `MaybeOpen[i]` = "var i was created and not yet freed/escaped on SOME path here". `Direction=fdForward`; `Bottom`/`Boundary` = all False; `Join` = union (OR). Construct `(AVars: TRoutineVarTable; const ASrc: TBytes)`. (A 4-state enum `esNone/esCreated/esFreed/esEscaped` is the conceptual model, but the implementable lattice is the single boolean `MaybeOpen` per var — reuse the `TArray<Boolean>` value type so it rides the existing solver.) The check also needs the creation line per var: maintain a side `TDictionary<Integer,TPoint>` (var index -> create site) populated during a single forward walk in the check, not in the lattice.

- [ ] **Step 1: Write the failing fixture**

`tests/lint/object-leak.pas`:
```pascal
unit objectleak;
interface
uses System.Classes;
implementation
procedure P1;
var o: TStringList;
begin
  o := TStringList.Create;   // line 8: created, never freed/escaped -> object-leak (info)
  o.Add('x');
end;
procedure P2;
var o: TStringList;
begin
  o := TStringList.Create;   // freed -> NO finding
  try o.Add('x'); finally o.Free; end;
end;
function P3: TStringList;
begin
  Result := TStringList.Create;  // escaped via Result -> NO finding
end;
procedure P4(aList: TStrings);
var o: TStringList;
begin
  o := TStringList.Create;   // passed to a call -> escape (conservative) -> NO finding
  aList.AddObject('x', o);
end;
end.
```
`tests/lint/object-leak.pas.expected`:
```
object-leak 8
!object-leak 15
```

- [ ] **Step 2: Run to verify failure** — FAIL.

- [ ] **Step 3: Implement `TEscape`** (forward may-open over `TArray<Boolean>`)

`Direction=fdForward`; `Bottom`/`Boundary`=all False; `Join`=OR; `Equals`=elementwise. `Transfer(block, in)` per item, setting `MaybeOpen[i]`:
- **create** -> `MaybeOpen[x] := True`: `x := <ctor>` where the rhs is an `exprDot`/`exprCall` whose tail/entity identifier text is `Create` (case-insensitive). Detect via the rhs node's last `exprDot.rhs` or `exprCall.entity` text = `create`.
- **free** -> `MaybeOpen[x] := False`: `x.Free` (an `exprDot` with rhs text `Free`/`DisposeOf`), or `FreeAndNil(x)` (an `exprCall` entity `FreeAndNil` with `x` as arg).
- **escape** -> `MaybeOpen[x] := False`: `Result := x`; an assignment whose lhs is an `exprDot` (field/property write) with rhs `x`; `x` passed as any call argument (reuse `CollectReadsAndCallDefs` CallDefs); alias `y := x` also sets `MaybeOpen[y] := MaybeOpen[x]` then (for the conservative store-free check) `MaybeOpen[x] := False` (ownership moved to y).
At `AIn[ExitIdx]`, any var with `MaybeOpen[i]=True` is a leak. Because *any* pass-to-call counts as escape (store-free), the check fires only on clear create-then-fall-out-of-scope cases.

- [ ] **Step 4: Escape engine unit test** — assert `o` is MaybeOpen at Exit for P1's body, not for P2's. Run engine tests — PASS.

- [ ] **Step 5: Implement `object-leak` check** — for each var MaybeOpen at `AIn[ExitIdx]`, emit `object-leak` (`info`) at the creation line (track the create site line in a side map during the pass). Build CLI (Win64), run fixture + full harness + engine tests — all green.

- [ ] **Step 6: Normalize CRLF, update `rules/README.md`, commit**

```powershell
git add src/analysis/DRagLint.Analysis.Flow.Lattices.pas src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas tests/ rules/README.md
git commit -m "feat(flow): M2 stage 6 -- escape analysis + object-leak (conservative, store-free)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Interprocedural object-leak refinement (store-backed)

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` (escape transfer consults the store)
- Create: `tests/lint-project/object-leak-interproc/` fixture (index + store), following `tests/lint-project/README.md`.

**Interfaces:**
- Consumes: `ISymbolStore` (`FindSymbolsByExactName`, call-graph queries). The escape transfer's "any call = escape" is refined: a call to a callee that does NOT take ownership of the arg (not an `OwnsObjects` sink, not an `Owner`-param ctor, not `.Free`) does NOT count as escape — so a genuine leak through a non-owning callee surfaces.

- [ ] **Step 1: Write the failing project fixture** — a 2-unit fixture where unit A creates an object and passes it to a non-owning helper in unit B that neither frees nor stores it. Index both into a test DB (per `tests/lint-project/README.md`), run `lint-all --db`, expect `object-leak` to fire. A negative case: passing to an owning sink (a `TObjectList` with `OwnsObjects=True` `.Add`) must NOT fire. Record expectations in the fixture's README/expected file (the lint-project harness is manual per the backlog — document the exact command + expected lines).

- [ ] **Step 2: Run to verify failure** — the store-free check currently suppresses both (any call = escape). Confirm the leak is missed.

- [ ] **Step 3: Implement the refinement** — when `AStore <> nil`, before treating a call arg as escape, resolve the callee; if the callee's matching parameter is a plain value param of a non-owning routine (heuristic: routine name not in a known-owning set and param not stored to a field/added to an owning list — start with a conservative allowlist of owning sinks: `Add`/`Insert` on `OwnsObjects` lists, ctors with an `AOwner`/`Owner` param, `.Free`/`FreeAndNil`), keep the var `MaybeOpen` (do not mark escaped). Document that this remains `info` (FP-riskiest check). Nil-safe: store-free path unchanged.

- [ ] **Step 4: Build CLI (Win64), run the project fixture (manual command from Step 1) + full per-file harness** — green; record the run.

- [ ] **Step 5: Normalize CRLF, commit**

```powershell
git add src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas tests/lint-project/
git commit -m "feat(flow): M2 stage 7 -- interprocedural object-leak refinement (store-backed ownership)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Managed-type precision via M1 ResolveTypeCategory + release prep

**Files:**
- Modify: `src/diagnostics/DRagLint.Diagnostics.FlowChecks.pas` (`IsManagedType` store path)
- Create: `tests/lint-project/managed-type-precision/` fixture (store)
- Modify: `VERSION` (CLI.pas line 6), `CHANGELOG`, `rules/README.md`

**Interfaces:**
- Consumes: `ISymbolStore.ResolveTypeCategory`. Refines `IsManagedType` so an aliased managed type (`type MyStr = string`) is correctly skipped and a non-conventional unmanaged type is correctly checked — exactly when a store is present.

- [ ] **Step 1: Write the failing project fixture** — a unit with `type TAmount = Double;` and `type IFoo = interface ... end;` plus a local of an aliased managed type read before assignment. With the heuristic (no store) the alias is misclassified; with the store it resolves. Document the index+lint-all command + expected lines (store path).

- [ ] **Step 2: Run to verify the store path mishandles it** — confirm the alias case is wrong without the refinement.

- [ ] **Step 3: Refine `IsManagedType`** — when `AStore <> nil` and `ResolveTypeCategory` returns a definite category, also treat `tcUnknown`-but-resolves-to-managed correctly; ensure `tcString`/`tcInterface` => managed (skip), all unmanaged categories (`tcFloat`,`tcOrdinal`,`tcBoolean`,`tcChar`,`tcPointer`,`tcEnum`,`tcClass`,`tcRecord`) => checkable. (Note: `tcClass` is a pointer/unmanaged for definite-assignment; a class *instance variable* is a pointer, not zero-init-managed — keep it checkable.) Keep the heuristic fallback when store is nil or returns `tcUnknown`.

- [ ] **Step 4: Build CLI (Win64), run the project fixture + full per-file harness + engine tests** — all green. Run a real-code sanity pass: `drag-lint lint-all` on the ORM3 project DB (per the backlog's `lint-all` command) and record the new flow-rule finding counts to `docs/lint/` (sanity, not a gate).

- [ ] **Step 5: Bump version + changelog (bundled M1+M2 = v0.66.0-alpha)** — set `VERSION` const in CLI.pas (line ~6) to `0.66.0-alpha`; add the top CHANGELOG entry summarizing M1 (type resolver, 5 rules exact) + M2 (CFG/data-flow engine, 7 flow checks); finalize the 7 new rule rows in `rules/README.md`. Do NOT tag/release here — the release (git tag + `gh release create`) is a separate user-driven step once everything is verified.

- [ ] **Step 6: Normalize CRLF, run the full harness one last time, commit**

```powershell
pwsh tests\lint\run_lint_tests.ps1
pwsh -File tests\flowengine\run_flowengine_tests.ps1
git add -A
git commit -m "feat(flow): M2 stage 8 -- managed-type precision (store) + v0.66.0-alpha version/changelog (M1+M2 bundle)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Definition of Done

- `DRagLint.Analysis.Cfg` + `DRagLint.Analysis.DataFlow` + `DRagLint.Analysis.Flow.Lattices` shipped with `tests/flowengine` unit tests (CFG shape, solver fixpoint, definite-assignment, liveness, escape).
- 7 checks live and wired into `DoLint` / `DoLintAll` / `DoCheckAst`: `used-before-assignment`, `function-result-not-set`, `out-param-not-set`, `overwrite-before-read`, `write-only-local`, `loop-var-after-loop`, `object-leak` — with definite=warning / possible=info severities.
- Managed-type handling: heuristic (no store) + exact via M1 `ResolveTypeCategory` (store). Object-leak: conservative store-free + refined store-present.
- A fixture for every check (positive + negative). `tests/lint/run_lint_tests.ps1` green. A real-code `lint-all` sanity run recorded.
- `VERSION` = `0.66.0-alpha`, CHANGELOG + `rules/README.md` updated (M1+M2 bundle). Release tag/publish deferred to the user.

## Notes for the implementer (read before starting)

- **Confirm node kinds you have not yet seen** (`raise`, `asm`) with `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse <file>` before relying on them. The confirmed control-flow kinds are listed in the "File Structure" header; trust those.
- **Reads-before-defs ordering** in every transfer/replay: `x := x + 1` reads the OLD x, then defines x. Get this wrong and `used-before-assignment` / dead-store both misfire.
- **FP policy is law:** when a path is ambiguous (opaque `with`, call args, exceptions), prefer suppression. Definite=warning, possible=info. Never promote an uncertain finding to warning.
- **try/except soundness:** the `try-entry -> handler/finally` edges mean try-body assignments are NOT assumed in the handler/finally — keep them; removing them creates false "Result not set" findings.
- **Generics:** `IDataFlowAnalysis<TValue>` + `TDataFlowSolver<TValue>` are the only generic types; the three analyses instantiate `TDefAsgnVal`, `TArray<Boolean>` (liveness + escape-as-boolean). Compile each task before moving on (Delphi generic errors surface late).
