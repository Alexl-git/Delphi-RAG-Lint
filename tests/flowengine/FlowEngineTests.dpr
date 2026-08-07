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
  DRagLint.Core.Encoding in '..\..\src\core\DRagLint.Core.Encoding.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Analysis.Cfg in '..\..\src\analysis\DRagLint.Analysis.Cfg.pas',
  DRagLint.Analysis.DataFlow in '..\..\src\analysis\DRagLint.Analysis.DataFlow.pas',
  DRagLint.Analysis.Flow.Lattices in '..\..\src\analysis\DRagLint.Analysis.Flow.Lattices.pas',
  DRagLint.Analysis.Liveness in '..\..\src\analysis\DRagLint.Analysis.Liveness.pas';

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

{ ---- B9: exit / break / continue must LEAVE the flow -------------------------

  EmitStmt decided "is this statement a divert?" by comparing the `statement`
  node's WHOLE TEXT against 'exit'. That text carries the trailing semicolon, so
  the comparison was 'exit;' = 'exit' -- always false. No bare `exit;`,
  `exit(v);`, `break;` or `continue;` had ever diverted: each fell through to
  whatever came after it.

  It hid because a guard clause's join block usually holds the very assignment
  the fall-through would have skipped, so the wrong edge changed nothing
  observable. It stopped hiding where the assignment sits BEYOND the join --
  DataCopy's CopyFileVerified, where an `except` handler ending in `exit` let the
  "exception fired before SrcSize was set" state reach the code after the try.

  These assert the EDGE, not a downstream finding, because that is the thing
  that was wrong: a rule-level test would pass again the moment any rule stopped
  looking, and the fall-through would still be there for the next analysis. }

function CfgItemText(const ACfg: TCfg; ABlock, AItem: Integer): string;
var N: TTSNode; S, E, L: Integer;
begin
  Result := '';
  N := ACfg.Blocks[ABlock].Items[AItem].Node;
  S := Integer(N.StartByte); E := Integer(N.EndByte); L := E - S;
  if (L <= 0) or (S < 0) or (E > Length(ACfg.Src)) then Exit;
  Result := LowerCase(Trim(TEncoding.UTF8.GetString(ACfg.Src, S, L)));
end;

{ Index of the block holding an item whose source text is exactly ATextLower,
  or -1. }
function BlockWithItem(const ACfg: TCfg; const ATextLower: string): Integer;
var B, I: Integer;
begin
  Result := -1;
  for B := 0 to ACfg.BlockCount - 1 do
    for I := 0 to ACfg.Blocks[B].Items.Count - 1 do
      if CfgItemText(ACfg, B, I) = ATextLower then Exit(B);
end;

function ReachesBlock(const ACfg: TCfg; AFrom, ATarget: Integer): Boolean;
var Seen: TList<Integer>; Q: TQueue<Integer>; B, S: Integer;
begin
  Result := False;
  if (AFrom < 0) or (ATarget < 0) then Exit;
  Seen := TList<Integer>.Create; Q := TQueue<Integer>.Create;
  try
    Q.Enqueue(AFrom); Seen.Add(AFrom);
    while Q.Count > 0 do
    begin
      B := Q.Dequeue;
      if B = ATarget then Exit(True);
      for S := 0 to ACfg.Blocks[B].Succ.Count - 1 do
        if Seen.IndexOf(ACfg.Blocks[B].Succ[S]) < 0 then
        begin Seen.Add(ACfg.Blocks[B].Succ[S]); Q.Enqueue(ACfg.Blocks[B].Succ[S]); end;
    end;
  finally Seen.Free; Q.Free; end;
end;

procedure TestBareExitDiverts;
const SRC =
  'unit u; interface implementation' + sLineBreak +
  'function P(b: Boolean): Integer; var n: Integer; begin' + sLineBreak +
  '  result := 0;' + sLineBreak +
  '  if b then exit;' + sLineBreak +
  '  n := 5;' + sLineBreak +
  '  result := n;' + sLineBreak +
  'end; end.';
var Cfg: TCfg; ExitBlk, AsgnBlk: Integer;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('bare exit: built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
    if Cfg = nil then Exit;
    ExitBlk := BlockWithItem(Cfg, 'exit;');
    AsgnBlk := BlockWithItem(Cfg, 'n := 5');
    Check('bare exit: the exit statement is in a block', ExitBlk >= 0);
    if ExitBlk < 0 then Exit;
    Check('bare exit: exactly one successor', Cfg.Blocks[ExitBlk].Succ.Count = 1);
    Check('bare exit: successor is the CFG Exit block',
          (Cfg.Blocks[ExitBlk].Succ.Count = 1) and (Cfg.Blocks[ExitBlk].Succ[0] = Cfg.ExitIdx));
    Check('bare exit: does not fall through to the code after the guard',
          not ReachesBlock(Cfg, ExitBlk, AsgnBlk));
  finally Cfg.Free; end;
end;

procedure TestValuedExitDiverts;
const SRC =
  'unit u; interface implementation' + sLineBreak +
  'function P(b: Boolean): Integer; var n: Integer; begin' + sLineBreak +
  '  if b then exit(0);' + sLineBreak +
  '  n := 5;' + sLineBreak +
  '  result := n;' + sLineBreak +
  'end; end.';
var Cfg: TCfg; ExitBlk, AsgnBlk: Integer;
begin
  Cfg := BuildCfgFor(SRC);
  try
    Check('exit(v): built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
    if Cfg = nil then Exit;
    ExitBlk := BlockWithItem(Cfg, 'exit(0);');
    AsgnBlk := BlockWithItem(Cfg, 'n := 5');
    Check('exit(v): the exit statement is in a block', ExitBlk >= 0);
    if ExitBlk < 0 then Exit;
    Check('exit(v): successor is the CFG Exit block',
          (Cfg.Blocks[ExitBlk].Succ.Count = 1) and (Cfg.Blocks[ExitBlk].Succ[0] = Cfg.ExitIdx));
    Check('exit(v): does not fall through to the code after the guard',
          not ReachesBlock(Cfg, ExitBlk, AsgnBlk));
  finally Cfg.Free; end;
end;

procedure TestBreakAndContinueDivert;
const SRC_BREAK =
  'unit u; interface implementation' + sLineBreak +
  'procedure P; var n: Integer; begin' + sLineBreak +
  '  while n > 0 do' + sLineBreak +
  '  begin' + sLineBreak +
  '    if n = 1 then break;' + sLineBreak +
  '    n := 2;' + sLineBreak +
  '  end;' + sLineBreak +
  '  n := 3;' + sLineBreak +
  'end; end.';
  SRC_CONT =
  'unit u; interface implementation' + sLineBreak +
  'procedure P; var n: Integer; begin' + sLineBreak +
  '  while n > 0 do' + sLineBreak +
  '  begin' + sLineBreak +
  '    if n = 1 then continue;' + sLineBreak +
  '    n := 2;' + sLineBreak +
  '  end;' + sLineBreak +
  '  n := 3;' + sLineBreak +
  'end; end.';
var Cfg: TCfg; Blk, BodyBlk, HdrBlk: Integer;
begin
  Cfg := BuildCfgFor(SRC_BREAK);
  try
    Check('break: built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
    if Cfg = nil then Exit;
    Blk     := BlockWithItem(Cfg, 'break;');
    BodyBlk := BlockWithItem(Cfg, 'n := 2');
    HdrBlk  := BlockWithItem(Cfg, 'n > 0');
    Check('break: the break statement is in a block', Blk >= 0);
    if Blk < 0 then Exit;
    Check('break: exactly one successor', Cfg.Blocks[Blk].Succ.Count = 1);
    { break leaves the loop entirely: neither the rest of the body nor the
      header may be reachable from it. }
    Check('break: rest of the loop body is unreachable from it',
          not ReachesBlock(Cfg, Blk, BodyBlk));
    Check('break: the loop header is unreachable from it',
          not ReachesBlock(Cfg, Blk, HdrBlk));
  finally Cfg.Free; end;

  Cfg := BuildCfgFor(SRC_CONT);
  try
    Check('continue: built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
    if Cfg = nil then Exit;
    Blk     := BlockWithItem(Cfg, 'continue;');
    BodyBlk := BlockWithItem(Cfg, 'n := 2');
    HdrBlk  := BlockWithItem(Cfg, 'n > 0');
    Check('continue: the continue statement is in a block', Blk >= 0);
    if Blk < 0 then Exit;
    { continue goes DIRECTLY back to the loop header -- not on to the rest of
      the body. (The body is reachable again THROUGH the header, which is why
      this asserts the immediate successor rather than reachability.) }
    Check('continue: exactly one successor', Cfg.Blocks[Blk].Succ.Count = 1);
    Check('continue: its successor is the loop header',
          (Cfg.Blocks[Blk].Succ.Count = 1) and (Cfg.Blocks[Blk].Succ[0] = HdrBlk));
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

procedure TestLivenessBackward;
const SRC =
  'unit u; interface implementation procedure P(a: Integer);' + sLineBreak +
  'var x: Integer; begin x := a; Writeln(x); end; end.';
var
  Tmp: string; PF: TParsedFile; Procs: TArray<TTSNode>;
  Cfg: TCfg; Vars: TRoutineVarTable; LIn, LOut: TArray<TArray<Boolean>>;
begin
  Tmp := TPath.Combine(TPath.GetTempPath, 'lv_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(Tmp, SRC);
  try
    PF := TAstParseCache.Get(Tmp);
    Procs := CfgFindProcs(PF.Tree.RootNode);
    Cfg := TCfgBuilder.Build(Procs[0], PF.Src);
    Vars := TRoutineVarTable.Build(Procs[0], PF.Src);
    try
      TDataFlowSolver<TArray<Boolean>>.Solve(Cfg, TLiveness.Create(Vars, PF.Src), LIn, LOut);
      Check('liveness: value param "a" live at entry', LIn[Cfg.EntryIdx][Vars.IndexOf('a')]);
      Check('liveness: local "x" not live at entry', not LIn[Cfg.EntryIdx][Vars.IndexOf('x')]);
    finally Cfg.Free; Vars.Free; end;
  finally TAstParseCache.Clear; TFile.Delete(Tmp); end;
end;

function EscapeOpenAtExit(const ASource: string): Boolean;
var Tmp: string; PF: TParsedFile; Procs: TArray<TTSNode>;
    Cfg: TCfg; Vars: TRoutineVarTable; EIn, EOut: TArray<TArray<Boolean>>; oi: Integer;
begin
  Result := False;
  Tmp := TPath.Combine(TPath.GetTempPath, 'esc_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(Tmp, ASource);
  try
    PF := TAstParseCache.Get(Tmp);
    Procs := CfgFindProcs(PF.Tree.RootNode);
    Cfg := TCfgBuilder.Build(Procs[0], PF.Src);
    Vars := TRoutineVarTable.Build(Procs[0], PF.Src);
    try
      TDataFlowSolver<TArray<Boolean>>.Solve(Cfg, TEscape.Create(Vars, PF.Src), EIn, EOut);
      oi := Vars.IndexOf('o');
      if oi >= 0 then Result := EIn[Cfg.ExitIdx][oi];
    finally Cfg.Free; Vars.Free; end;
  finally TAstParseCache.Clear; TFile.Delete(Tmp); end;
end;

procedure TestEscapeLeak;
begin
  Check('escape: created+unfreed is open at exit',
    EscapeOpenAtExit('unit u; interface implementation procedure P; var o: TObject;' + sLineBreak +
      'begin o := TObject.Create; end; end.'));
  Check('escape: freed is not open at exit',
    not EscapeOpenAtExit('unit u; interface implementation procedure P; var o: TObject;' + sLineBreak +
      'begin o := TObject.Create; o.Free; end; end.'));
end;

{ Solve TFreedState for the first proc of ASource; return Must/May dangling
  at the routine Exit's IN for var AVarName. Caller need not free anything --
  Cfg/Vars are local. }
procedure FreedStateAtExit(const ASource, AVarName: string; out AMust, AMay: Boolean);
var
  Tmp: string; PF: TParsedFile; Procs: TArray<TTSNode>;
  Cfg: TCfg; Vars: TRoutineVarTable; FIn, FOut: TArray<TFreedVal>; Ix: Integer;
begin
  AMust := False; AMay := False;
  Tmp := TPath.Combine(TPath.GetTempPath, 'fs_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(Tmp, ASource);
  try
    PF := TAstParseCache.Get(Tmp);
    if PF.Tree = nil then Exit;
    Procs := CfgFindProcs(PF.Tree.RootNode);
    if Length(Procs) = 0 then Exit;
    Cfg := TCfgBuilder.Build(Procs[0], PF.Src);
    Vars := TRoutineVarTable.Build(Procs[0], PF.Src);
    try
      if Cfg.Skipped then Exit;
      if not TDataFlowSolver<TFreedVal>.Solve(Cfg, TFreedState.Create(Vars, PF.Src), FIn, FOut) then Exit;
      Ix := Vars.IndexOf(LowerCase(AVarName));
      if Ix < 0 then Exit;
      AMust := FIn[Cfg.ExitIdx].Must[Ix];
      AMay  := FIn[Cfg.ExitIdx].May[Ix];
    finally Cfg.Free; Vars.Free; end;
  finally TAstParseCache.Clear; TFile.Delete(Tmp); end;
end;

procedure TestFreedStateLinearDangling;
var Must, May: Boolean;
begin
  { X.Free; X.Free; -> dangling (must) at exit: both frees leave X non-nil. }
  FreedStateAtExit(
    'unit u; interface implementation procedure P; var x: TObject; begin' + sLineBreak +
    '  x := TObject.Create; x.Free; x.Free;' + sLineBreak +
    'end; end.', 'x', Must, May);
  Check('freedstate: linear raw-free -> must-dangling at exit', Must);
  Check('freedstate: linear raw-free -> may-dangling at exit', May);
end;

procedure TestFreedStateReassignThenFreeEndsDangling;
var Must, May: Boolean;
begin
  { reassigned between two frees -> NOT dangling at exit (2nd free acts on a
    fresh object, and itself leaves it dangling again -- but only ONE free
    follows the reassignment, so must/may here reflects that final Free). }
  FreedStateAtExit(
    'unit u; interface implementation procedure P; var x: TObject; begin' + sLineBreak +
    '  x := TObject.Create; x.Free; x := TObject.Create; x.Free;' + sLineBreak +
    'end; end.', 'x', Must, May);
  Check('freedstate: reassign-between -> still ends dangling (final Free)', Must);
end;

procedure TestFreedStateReassignClears;
var Must, May: Boolean;
begin
  { reassign after a free, with NO free following -> the fresh object is live,
    so x is NOT dangling at exit: proves reassignment clears the freed state. }
  FreedStateAtExit(
    'unit u; interface implementation procedure P; var x: TObject; begin' + sLineBreak +
    '  x := TObject.Create; x.Free; x := TObject.Create;' + sLineBreak +
    'end; end.', 'x', Must, May);
  Check('freedstate: reassign-after-free clears dangling (must)', not Must);
  Check('freedstate: reassign-after-free clears dangling (may)', not May);
end;

procedure TestFreedStateFreeAndNilClears;
var Must, May: Boolean;
begin
  { FreeAndNil nils x -> NOT dangling at exit. }
  FreedStateAtExit(
    'unit u; interface implementation procedure P; var x: TObject; begin' + sLineBreak +
    '  x := TObject.Create; FreeAndNil(x);' + sLineBreak +
    'end; end.', 'x', Must, May);
  Check('freedstate: FreeAndNil -> not dangling (must)', not Must);
  Check('freedstate: FreeAndNil -> not dangling (may)', not May);
end;

procedure TestFreedStateBranchMergeMayOnly;
var Must, May: Boolean;
begin
  { free on ONE if-branch only -> may-dangling but not must-dangling at exit. }
  FreedStateAtExit(
    'unit u; interface implementation procedure P(b: Boolean); var x: TObject; begin' + sLineBreak +
    '  x := TObject.Create; if b then x.Free;' + sLineBreak +
    'end; end.', 'x', Must, May);
  Check('freedstate: branch-merge -> may-dangling', May);
  Check('freedstate: branch-merge -> NOT must-dangling', not Must);
end;

{ Find the (block index, item index) of the first CFG item whose source text
  starts with ANeedle (case-insensitive; NeedLe should already be lowercase).
  Returns False if not found. Scans blocks in index order, low to high, so a
  substring that appears in multiple items always matches the earliest one --
  fine for these fixtures, where each needle is unique. }
function FindItem(const ACfg: TCfg; const ASrc: TBytes; const ANeedle: string;
  out ABlockIdx, AItemIdx: Integer): Boolean;
var B, I: Integer; Txt: string;
begin
  Result := False;
  ABlockIdx := -1; AItemIdx := -1;
  for B := 0 to ACfg.BlockCount - 1 do
    for I := 0 to ACfg.Blocks[B].Items.Count - 1 do
    begin
      Txt := NodeText(ACfg.Blocks[B].Items[I].Node, ASrc);
      if Txt.StartsWith(ANeedle) then
      begin
        ABlockIdx := B; AItemIdx := I; Exit(True);
      end;
    end;
end;

{ Boundary-liveness (M2 core): a branchy routine --
    procedure P(a: Integer);
    var x, y: Integer;
    begin
      x := a;           // item 0: def x, use a
      if a > 0 then
        y := x           // then-branch: def y, use x
      else
        y := 0;          // else-branch: def y
      Writeln(y);        // last item: use y
    end;
  LiveAfterItem right after "x := a" must include x (read by both branches'
  "y := x" -- well, only the then-branch reads x, but liveness is a MAY
  analysis: x is live if read on SOME path -- and exclude y (not yet defined,
  and even once defined its later uses don't reach back through x's def).
  LiveAfterItem right after "Writeln(y)" (the join block's last item) must
  exclude both: nothing left downstream reads either var. }
procedure TestBoundaryLiveness;
const SRC =
  'unit u; interface implementation procedure P(a: Integer);' + sLineBreak +
  'var x, y: Integer; begin' + sLineBreak +
  '  x := a;' + sLineBreak +
  '  if a > 0 then' + sLineBreak +
  '    y := x' + sLineBreak +
  '  else' + sLineBreak +
  '    y := 0;' + sLineBreak +
  '  Writeln(y);' + sLineBreak +
  'end; end.';
var
  Tmp: string; PF: TParsedFile; Procs: TArray<TTSNode>;
  Cfg: TCfg; Vars: TRoutineVarTable;
  BIdx, IIdx: Integer;
  Live: TArray<Boolean>;
  XIx, YIx: Integer;
begin
  Tmp := TPath.Combine(TPath.GetTempPath, 'bl_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(Tmp, SRC);
  try
    PF := TAstParseCache.Get(Tmp);
    Procs := CfgFindProcs(PF.Tree.RootNode);
    Cfg := TCfgBuilder.Build(Procs[0], PF.Src);
    Vars := TRoutineVarTable.Build(Procs[0], PF.Src);
    try
      Check('boundary-liveness: cfg built + not skipped', (Cfg <> nil) and not Cfg.Skipped);
      if (Cfg = nil) or Cfg.Skipped then Exit;
      XIx := Vars.IndexOf('x');
      YIx := Vars.IndexOf('y');
      Check('boundary-liveness: var table has x and y', (XIx >= 0) and (YIx >= 0));

      { after "x := a": x live (used on the then-path "y := x"); y not live. }
      Check('boundary-liveness: found "x := a"', FindItem(Cfg, PF.Src, 'x := a', BIdx, IIdx));
      Live := LiveAfterItem(Cfg, Vars, PF.Src, BIdx, IIdx);
      Check('boundary-liveness: after "x := a", x is live', Live[XIx]);
      Check('boundary-liveness: after "x := a", y is not live', not Live[YIx]);

      { after "Writeln(y)" (last item of the join block): nothing downstream
        reads x or y -> both dead. }
      Check('boundary-liveness: found "writeln(y)"', FindItem(Cfg, PF.Src, 'writeln(y)', BIdx, IIdx));
      Live := LiveAfterItem(Cfg, Vars, PF.Src, BIdx, IIdx);
      Check('boundary-liveness: after "Writeln(y)", x is not live', not Live[XIx]);
      Check('boundary-liveness: after "Writeln(y)", y is not live', not Live[YIx]);

      { LiveBeforeItem at "Writeln(y)" must include y (it is about to be read)
        and exclude x (still dead). }
      Live := LiveBeforeItem(Cfg, Vars, PF.Src, BIdx, IIdx);
      Check('boundary-liveness: before "Writeln(y)", y is live', Live[YIx]);
      Check('boundary-liveness: before "Writeln(y)", x is not live', not Live[XIx]);
    finally Cfg.Free; Vars.Free; end;
  finally TAstParseCache.Clear; TFile.Delete(Tmp); end;
end;

begin
  GPass := 0; GFail := 0;
  try
    TestIfElseShape;
    TestWhileBackEdge;
    TestGotoSkips;
    TestForRecordsLoopVar;
    TestTryFinallyBuilds;
    TestBareExitDiverts;
    TestValuedExitDiverts;
    TestBreakAndContinueDivert;
    TestSolverForwardFixpoint;
    TestDefiniteAssignmentMust;
    TestDefiniteAssignmentMayOnly;
    TestLivenessBackward;
    TestEscapeLeak;
    TestFreedStateLinearDangling;
    TestFreedStateReassignThenFreeEndsDangling;
    TestFreedStateReassignClears;
    TestFreedStateFreeAndNilClears;
    TestFreedStateBranchMergeMayOnly;
    TestBoundaryLiveness;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('flowengine-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
