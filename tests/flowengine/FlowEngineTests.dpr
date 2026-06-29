program FlowEngineTests;

// M2 engine TDD harness: control-flow graph (CFG) builder, generic data-flow
// solver, and the concrete lattices. Parses real .pas fixtures via the shared
// TAstParseCache, so the exe needs tree-sitter.dll + tree-sitter-delphi13.dll
// on PATH at runtime (run_flowengine_tests.ps1 prepends third_party\dll-win64).

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  TreeSitterLib in '..\..\third_party\delphi-tree-sitter\TreeSitterLib.pas',
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Analysis.Cfg in '..\..\src\analysis\DRagLint.Analysis.Cfg.pas',
  DRagLint.Analysis.DataFlow in '..\..\src\analysis\DRagLint.Analysis.DataFlow.pas',
  DRagLint.Analysis.Flow.Lattices in '..\..\src\analysis\DRagLint.Analysis.Flow.Lattices.pas';

type
  { Toy forward analysis: "has any block with >=1 item executed upstream?" --
    a finite-height boolean lattice used only to exercise the solver. }
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
begin Result := [AIn[0] or (ABlock.Items.Count > 0)]; end;
function TToyForward.Equals(const A, B: TBoolVal): Boolean;
begin Result := A[0] = B[0]; end;

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
    { Entry, first block (condition), then-block, else-block, join (x:=3), Exit. }
    Check('ifElse: >= 5 blocks', Cfg.BlockCount >= 5);
    Check('ifElse: entry has a successor', Cfg.Blocks[Cfg.EntryIdx].Succ.Count >= 1);
  finally
    Cfg.Free;
  end;
end;

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

procedure TestForRecordsLoopVar;
const SRC =
  'unit u; interface implementation procedure P; var i, s: Integer; begin' + sLineBreak +
  '  s := 0; for i := 1 to 10 do s := s + i; Writeln(i);' + sLineBreak +
  'end; end.';
var Cfg: TCfg;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('for: built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
    if Cfg = nil then Exit;
    Check('for: records 1 loop var', Cfg.ForVars.Count = 1);
    if Cfg.ForVars.Count = 1 then
      Check('for: loop var is "i"', Cfg.ForVars[0].VarName = 'i');
  finally Cfg.Free; end;
end;

procedure TestTryFinallyBuilds;
const SRC =
  'unit u; interface implementation procedure P; var o: TObject; begin' + sLineBreak +
  '  try o := TObject.Create; finally o.Free; end;' + sLineBreak +
  'end; end.';
var Cfg: TCfg; B, Reach: Integer; Seen: TList<Integer>; Q: TQueue<Integer>; S: Integer;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('try: built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
    if Cfg = nil then Exit;
    { Exit must be reachable from Entry via the finally block. }
    Seen := TList<Integer>.Create; Q := TQueue<Integer>.Create;
    try
      Reach := 0; Q.Enqueue(Cfg.EntryIdx); Seen.Add(Cfg.EntryIdx);
      while Q.Count > 0 do
      begin
        B := Q.Dequeue;
        if B = Cfg.ExitIdx then Reach := 1;
        for S := 0 to Cfg.Blocks[B].Succ.Count - 1 do
          if Seen.IndexOf(Cfg.Blocks[B].Succ[S]) < 0 then
          begin Seen.Add(Cfg.Blocks[B].Succ[S]); Q.Enqueue(Cfg.Blocks[B].Succ[S]); end;
      end;
      Check('try: Exit reachable from Entry', Reach = 1);
    finally Seen.Free; Q.Free; end;
  finally Cfg.Free; end;
end;

procedure TestSolverForwardFixpoint;
const SRC =
  'unit u; interface implementation procedure P; var x: Integer; begin' + sLineBreak +
  '  x := 1; if x > 0 then x := 2; x := 3;' + sLineBreak +
  'end; end.';
var Cfg: TCfg; AIn, AOut: TArray<TBoolVal>; OK: Boolean;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('solver: cfg built', Cfg <> nil);
    if Cfg = nil then Exit;
    OK := TDataFlowSolver<TBoolVal>.Solve(Cfg, TToyForward.Create, AIn, AOut);
    Check('solver: solved', OK);
    if not OK then Exit;
    Check('solver: reaches true at Exit', AOut[Cfg.ExitIdx][0]);
  finally Cfg.Free; end;
end;

{ Solve definite-assignment for the first proc of ASource; return the must/may
  at the Exit block's IN plus the var table (caller frees both Cfg and Vars). }
procedure SolveDefAsgn(const ASource: string; out ACfg: TCfg; out AVars: TRoutineVarTable;
  out AIn, AOut: TArray<TDefAsgnVal>);
var Tmp: string; PF: TParsedFile; Procs: TArray<TTSNode>;
begin
  ACfg := nil; AVars := nil;
  Tmp := TPath.Combine(TPath.GetTempPath, 'da_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(Tmp, ASource);
  try
    PF := TAstParseCache.Get(Tmp);
    if PF.Tree = nil then Exit;
    Procs := CfgFindProcs(PF.Tree.RootNode);
    if Length(Procs) = 0 then Exit;
    ACfg := TCfgBuilder.Build(Procs[0], PF.Src);
    AVars := TRoutineVarTable.Build(Procs[0], PF.Src);
    TDataFlowSolver<TDefAsgnVal>.Solve(ACfg, TDefiniteAssignment.Create(AVars, PF.Src), AIn, AOut);
  finally
    TAstParseCache.Clear; TFile.Delete(Tmp);
  end;
end;

procedure TestDefiniteAssignmentMust;
var Cfg: TCfg; Vars: TRoutineVarTable; AIn, AOut: TArray<TDefAsgnVal>; Ix: Integer;
begin
  { x assigned on BOTH branches -> must at Exit. }
  SolveDefAsgn(
    'unit u; interface implementation function F(b: Boolean): Integer;' + sLineBreak +
    'var x: Integer; begin if b then x := 1 else x := 2; Result := x; end; end.',
    Cfg, Vars, AIn, AOut);
  try
    Check('def-assign: built', (Cfg <> nil) and (Vars <> nil));
    if Cfg = nil then Exit;
    Ix := Vars.IndexOf('x');
    Check('def-assign: x must-assigned at Exit', AIn[Cfg.ExitIdx].Must[Ix]);
    Check('def-assign: Result must-assigned at Exit', AIn[Cfg.ExitIdx].Must[Vars.IndexOf('result')]);
  finally Cfg.Free; Vars.Free; end;
end;

procedure TestDefiniteAssignmentMayOnly;
var Cfg: TCfg; Vars: TRoutineVarTable; AIn, AOut: TArray<TDefAsgnVal>; Ix: Integer;
begin
  { x assigned on ONE branch -> may but not must at Exit. }
  SolveDefAsgn(
    'unit u; interface implementation function F(b: Boolean): Integer;' + sLineBreak +
    'var x: Integer; begin if b then x := 1; Result := x; end; end.',
    Cfg, Vars, AIn, AOut);
  try
    if Cfg = nil then begin Check('def-assign-may: built', False); Exit; end;
    Ix := Vars.IndexOf('x');
    Check('def-assign-may: x may at Exit', AIn[Cfg.ExitIdx].May[Ix]);
    Check('def-assign-may: x NOT must at Exit', not AIn[Cfg.ExitIdx].Must[Ix]);
  finally Cfg.Free; Vars.Free; end;
end;

begin
  GPass := 0; GFail := 0;
  try
    TestIfElseShape;
    TestWhileBackEdge;
    TestGotoSkips;
    TestForRecordsLoopVar;
    TestTryFinallyBuilds;
    TestSolverForwardFixpoint;
    TestDefiniteAssignmentMust;
    TestDefiniteAssignmentMayOnly;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('flowengine-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
