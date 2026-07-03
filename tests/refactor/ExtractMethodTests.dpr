program ExtractMethodTests;
{$APPTYPE CONSOLE}

// Task 2 TDD harness: Extract Method selection resolution + refuse guards.
// Parses embedded fixtures via the shared TAstParseCache (needs tree-sitter
// DLLs on PATH at runtime -- run_extractmethod_unit_tests.ps1 copies them
// next to the exe, mirroring run_buildlocal_tests.ps1 / FlowEngineTests.dpr).

uses
  System.SysUtils,
  System.IOUtils,
  TreeSitterLib in '..\..\third_party\delphi-tree-sitter\TreeSitterLib.pas',
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  DRagLint.Diagnostics.ParseCache in '..\..\src\diagnostics\DRagLint.Diagnostics.ParseCache.pas',
  DRagLint.Analysis.Cfg in '..\..\src\analysis\DRagLint.Analysis.Cfg.pas',
  DRagLint.Analysis.DataFlow in '..\..\src\analysis\DRagLint.Analysis.DataFlow.pas',
  DRagLint.Analysis.Flow.Lattices in '..\..\src\analysis\DRagLint.Analysis.Flow.Lattices.pas',
  DRagLint.Analysis.Liveness in '..\..\src\analysis\DRagLint.Analysis.Liveness.pas',
  DRagLint.Refactor.TextEdit in '..\..\src\refactor\DRagLint.Refactor.TextEdit.pas',
  DRagLint.Refactor.ExtractMethod in '..\..\src\refactor\DRagLint.Refactor.ExtractMethod.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

{ Write ASource to a temp .pas, call Build over [AFromLine..AToLine], return
  the refuse reason (empty on success). Caller checks Result/edits. }
function RefuseFor(const ASource: string; AFromLine, AToLine: Integer;
  const ANewName: string; out AEdits: TArray<TTextEdit>): string;
var
  P: string;
begin
  P:= TPath.Combine(TPath.GetTempPath, 'em_fixture_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(P, ASource, TEncoding.ANSI);
  TAstParseCache.Clear;
  try
    AEdits:= TExtractMethodRefactoring.Build(P, AFromLine, AToLine, ANewName, Result);
  finally
    TAstParseCache.Clear;
    if TFile.Exists(P) then TFile.Delete(P);
  end;
end;

{ Task 3 TDD harness: write ASource to a temp .pas, resolve the selection
  [AFromLine..AToLine] (must succeed -- callers pick shapes Task 2 accepts),
  build the routine's var table + CFG, and classify. Mirrors RefuseFor's
  temp-file / parse-cache discipline exactly. AVarNames returns the lower-
  cased var-table names by index (index-aligned, 1:1 with AVars.Count) so
  tests can assert "Inputs contains a" by name, not by hardcoded index. }
function ClassifyFor(const ASource: string; AFromLine, AToLine: Integer;
  out AVarNames: TArray<string>): TExtractVars;
var
  P: string;
  PF: TParsedFile;
  Sel: TExtractSelection;
  Refuse: string;
  Vars: TRoutineVarTable;
  Cfg: TCfg;
  I: Integer;
begin
  AVarNames:= nil;
  P:= TPath.Combine(TPath.GetTempPath, 'em_classify_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(P, ASource, TEncoding.ANSI);
  TAstParseCache.Clear;
  try
    if ResolveExtractSelection(P, AFromLine, AToLine, Sel, Refuse) <> eoOK then
    begin
      Result:= Default(TExtractVars);
      Result.Refuse:= 'resolve failed: ' + Refuse;
      Exit;
    end;
    PF:= TAstParseCache.Get(P);
    Vars:= TRoutineVarTable.Build(Sel.Proc, PF.Src);
    try
      SetLength(AVarNames, Vars.Count);
      for I:= 0 to Vars.Count - 1 do AVarNames[I]:= Vars.Get(I).Name;
      Cfg:= TCfgBuilder.Build(Sel.Proc, PF.Src);
      try
        Cfg.ComputePreds;
        Result:= TExtractMethodRefactoring.ClassifyVars(Sel, Cfg, Vars, PF.Src);
      finally
        Cfg.Free;
      end;
    finally
      Vars.Free;
    end;
  finally
    TAstParseCache.Clear;
    if TFile.Exists(P) then TFile.Delete(P);
  end;
end;

{ True when AArr contains the var-table index whose name (via ANames) equals
  ALowerName. Lets tests assert set membership by name. }
function ContainsVarName(const AArr: TArray<Integer>; const ANames: TArray<string>; const ALowerName: string): Boolean;
var I: Integer;
begin
  Result:= False;
  for I:= 0 to High(AArr) do
    if (AArr[I] >= 0) and (AArr[I] < Length(ANames)) and (ANames[AArr[I]] = ALowerName) then
      Exit(True);
end;

{ Position of the var named ALowerName (resolved via ANames) within AArr, or
  -1 when absent. Lets tests assert the ORDER of Inputs (first-use order). }
function IndexOfVarName(const AArr: TArray<Integer>; const ANames: TArray<string>; const ALowerName: string): Integer;
var I: Integer;
begin
  Result:= -1;
  for I:= 0 to High(AArr) do
    if (AArr[I] >= 0) and (AArr[I] < Length(ANames)) and (ANames[AArr[I]] = ALowerName) then
      Exit(I);
end;

{ (a) range spans two routines -> refuse "selection is not inside a single routine" }
procedure TestSpansTwoRoutines;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P1;'#13#10 +                    { 4 }
    'begin'#13#10 +                            { 5 }
    '  Writeln(''a'');'#13#10 +                { 6 }
    'end;'#13#10 +                             { 7 }
    'procedure P2;'#13#10 +                    { 8 }
    'begin'#13#10 +                            { 9 }
    '  Writeln(''b'');'#13#10 +                { 10 }
    'end;'#13#10 +                             { 11 }
    'end.'#13#10;                              { 12 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  { line 6 is inside P1's body, line 10 is inside P2's body }
  Reason:= RefuseFor(SRC, 6, 10, 'NewMeth', Edits);
  Check('spans-two-routines: refuses', Reason <> '');
  Check('spans-two-routines: reason mentions single routine',
    Pos('selection is not inside a single routine', Reason) > 0);
  Check('spans-two-routines: nil edits', Edits = nil);
end;

{ (b) range cuts a statement -> refuse "selection must be whole statements" }
procedure TestCutsStatement;
const
  SRC =
    'unit u;'#13#10 +                                { 1 }
    'interface'#13#10 +                              { 2 }
    'implementation'#13#10 +                         { 3 }
    'procedure P;'#13#10 +                            { 4 }
    'var x: Integer;'#13#10 +                        { 5 }
    'begin'#13#10 +                                  { 6 }
    '  x := 1 +'#13#10 +                             { 7  statement continues on line 8 }
    '    2;'#13#10 +                                 { 8 }
    '  x := 3;'#13#10 +                              { 9 }
    'end;'#13#10 +                                   { 10 }
    'end.'#13#10;                                    { 11 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  { selecting only line 7 cuts the 'x := 1 + 2;' statement in half }
  Reason:= RefuseFor(SRC, 7, 7, 'NewMeth', Edits);
  Check('cuts-statement: refuses', Reason <> '');
  Check('cuts-statement: reason mentions whole statements',
    Pos('selection must be whole statements', Reason) > 0);
  Check('cuts-statement: nil edits', Edits = nil);
end;

{ (c) routine has goto (TCfg.Skipped) -> refuse "routine uses goto/asm" }
procedure TestGotoRoutine;
const
  SRC =
    'unit u;'#13#10 +                                     { 1 }
    'interface'#13#10 +                                   { 2 }
    'implementation'#13#10 +                              { 3 }
    'procedure P;'#13#10 +                                 { 4 }
    'label done;'#13#10 +                                 { 5 }
    'var i: Integer;'#13#10 +                             { 6 }
    'begin'#13#10 +                                       { 7 }
    '  i := 0;'#13#10 +                                   { 8 }
    '  goto done;'#13#10 +                                { 9 }
    '  done: i := 1;'#13#10 +                             { 10 }
    'end;'#13#10 +                                        { 11 }
    'end.'#13#10;                                         { 12 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  Reason:= RefuseFor(SRC, 8, 8, 'NewMeth', Edits);
  Check('goto-routine: refuses', Reason <> '');
  Check('goto-routine: reason mentions goto/asm',
    Pos('routine uses goto/asm', Reason) > 0);
  Check('goto-routine: nil edits', Edits = nil);
end;

{ (d) range contains Exit -> refuse "selection contains Exit" }
procedure TestContainsExit;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P;'#13#10 +                      { 4 }
    'var x: Integer;'#13#10 +                  { 5 }
    'begin'#13#10 +                            { 6 }
    '  x := 1;'#13#10 +                        { 7 }
    '  Exit;'#13#10 +                          { 8 }
    '  x := 2;'#13#10 +                        { 9 }
    'end;'#13#10 +                             { 10 }
    'end.'#13#10;                              { 11 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  Reason:= RefuseFor(SRC, 7, 8, 'NewMeth', Edits);
  Check('contains-exit: refuses', Reason <> '');
  Check('contains-exit: reason mentions Exit',
    Pos('selection contains Exit', Reason) > 0);
  Check('contains-exit: nil edits', Edits = nil);
end;

{ (e) Break that escapes (loop starts before the selection) -> refuse }
procedure TestEscapingBreak;
const
  SRC =
    'unit u;'#13#10 +                                       { 1 }
    'interface'#13#10 +                                     { 2 }
    'implementation'#13#10 +                                { 3 }
    'procedure P;'#13#10 +                                   { 4 }
    'var i: Integer;'#13#10 +                               { 5 }
    'begin'#13#10 +                                         { 6 }
    '  i := 0;'#13#10 +                                     { 7 }
    '  while i < 10 do'#13#10 +                             { 8 }
    '  begin'#13#10 +                                       { 9 }
    '    Inc(i);'#13#10 +                                   { 10  select this line: Break below still targets the while, }
    '    if i = 5 then Break;'#13#10 +                      { 11  but selecting ONLY line 10 leaves the loop out of the run }
    '  end;'#13#10 +                                        { 12 }
    'end;'#13#10 +                                          { 13 }
    'end.'#13#10;                                           { 14 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  { Select just the 'if i = 5 then Break;' statement (line 11) on its own --
    its Break targets the enclosing while, which is NOT inside the selection. }
  Reason:= RefuseFor(SRC, 11, 11, 'NewMeth', Edits);
  Check('escaping-break: refuses', Reason <> '');
  Check('escaping-break: reason mentions break escaping',
    Pos('break', LowerCase(Reason)) > 0);
  Check('escaping-break: nil edits', Edits = nil);
end;

{ (f) range crosses nesting (starts in a 'then', ends outside) -> refuse }
procedure TestCrossesNesting;
const
  SRC =
    'unit u;'#13#10 +                                { 1 }
    'interface'#13#10 +                              { 2 }
    'implementation'#13#10 +                         { 3 }
    'procedure P;'#13#10 +                            { 4 }
    'var x: Integer;'#13#10 +                        { 5 }
    'begin'#13#10 +                                  { 6 }
    '  if x > 0 then'#13#10 +                        { 7 }
    '    x := 1'#13#10 +                             { 8  inside the then-branch }
    '  else'#13#10 +                                 { 9 }
    '    x := 2;'#13#10 +                            { 10 }
    '  x := 3;'#13#10 +                              { 11  outside the if entirely }
    'end;'#13#10 +                                   { 12 }
    'end.'#13#10;                                    { 13 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  { starts inside the then-branch (line 8), ends after the if statement (line 11) }
  Reason:= RefuseFor(SRC, 8, 11, 'NewMeth', Edits);
  Check('crosses-nesting: refuses', Reason <> '');
  Check('crosses-nesting: reason mentions nesting levels',
    Pos('selection crosses nesting levels', Reason) > 0);
  Check('crosses-nesting: nil edits', Edits = nil);
end;

{ Regression: two statements on ONE line -> the line-to-statement mapping is
  ambiguous; a naive first-match pick would silently DROP the trailing
  sibling from the run. Must refuse, never guess. }
procedure TestSameLineSiblings;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P;'#13#10 +                      { 4 }
    'var x, y: Integer;'#13#10 +               { 5 }
    'begin'#13#10 +                            { 6 }
    '  x := 1; y := 2;'#13#10 +                { 7  TWO statements share this line }
    '  x := 3;'#13#10 +                        { 8 }
    'end;'#13#10 +                             { 9 }
    'end.'#13#10;                              { 10 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  { selecting line 7 alone: which of the two statements is meant? refuse }
  Reason:= RefuseFor(SRC, 7, 7, 'NewMeth', Edits);
  Check('same-line-siblings: refuses', Reason <> '');
  Check('same-line-siblings: reason mentions shared line',
    Pos('multiple statements share a line in the selection', Reason) > 0);
  Check('same-line-siblings: nil edits', Edits = nil);

  { selecting lines 7-8 hits the same ambiguity at the start boundary }
  Reason:= RefuseFor(SRC, 7, 8, 'NewMeth', Edits);
  Check('same-line-siblings: [7..8] also refuses',
    Pos('multiple statements share a line in the selection', Reason) > 0);
end;

{ Sanity: a clean, safe, whole-statement single-routine selection with no
  escaping control flow now SYNTHESIZES (Task 4) rather than refusing. Here the
  run defines x (dead after -> internal) and y (read after -> the single
  output), reads nothing upward-exposed -> a function returning y with x as a
  local. Asserts a non-refuse, non-empty edit set (exact text is pinned by the
  dedicated synthesis fixtures below). }
procedure TestSafeSelectionSynthesizes;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P;'#13#10 +                      { 4 }
    'var'#13#10 +                              { 5 }
    '  x: Integer;'#13#10 +                    { 6 }
    '  y: Integer;'#13#10 +                    { 7 }
    'begin'#13#10 +                            { 8 }
    '  x := 1;'#13#10 +                        { 9 }
    '  y := x + 1;'#13#10 +                    { 10 }
    '  Writeln(y);'#13#10 +                    { 11 }
    'end;'#13#10 +                             { 12 }
    'end.'#13#10;                              { 13 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  Reason:= RefuseFor(SRC, 9, 10, 'NewMeth', Edits);
  Check('safe-selection: no refuse (synthesizes)', Reason = '');
  Check('safe-selection: non-empty edits', Length(Edits) > 0);
end;

{ ===========================================================================
  Task 3: variable classification (ClassifyVars)
  =========================================================================== }

{ (a) run reads param `a`, computes local `t`; nothing the run defines is
  live after it (the routine ends right after) -> Inputs = [a], OutputIdx=-1,
  Internals = [t]. }
procedure TestClassifyInputOnlyNoOutput;
const
  SRC =
    'unit u;'#13#10 +                             { 1 }
    'interface'#13#10 +                           { 2 }
    'implementation'#13#10 +                      { 3 }
    'procedure P(a: Integer);'#13#10 +             { 4 }
    'var t: Integer;'#13#10 +                     { 5 }
    'begin'#13#10 +                               { 6 }
    '  t := a + 1;'#13#10 +                       { 7 }
    '  Writeln(t);'#13#10 +                       { 8 }
    'end;'#13#10 +                                { 9 }
    'end.'#13#10;                                 { 10 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  V:= ClassifyFor(SRC, 7, 8, Names);
  Check('classify-a: no refuse', V.Refuse = '');
  Check('classify-a: Inputs contains a', ContainsVarName(V.Inputs, Names, 'a'));
  Check('classify-a: Inputs count = 1', Length(V.Inputs) = 1);
  Check('classify-a: OutputIdx = -1', V.OutputIdx = -1);
  Check('classify-a: Internals contains t', ContainsVarName(V.Internals, Names, 't'));
  Check('classify-a: OutputIsInput = False', not V.OutputIsInput);
end;

{ (b) run computes local `sum`, used after the run -> OutputIdx=sum. The
  run's only input is the param it reads; Inputs may be empty of `sum` itself
  (sum is a def+output, not an input -- it is never read before being
  defined within the run). }
procedure TestClassifyOutputUsedAfter;
const
  SRC =
    'unit u;'#13#10 +                             { 1 }
    'interface'#13#10 +                           { 2 }
    'implementation'#13#10 +                      { 3 }
    'procedure P(a, b: Integer);'#13#10 +          { 4 }
    'var sum: Integer;'#13#10 +                   { 5 }
    'begin'#13#10 +                               { 6 }
    '  sum := a + b;'#13#10 +                     { 7 }
    '  Writeln(sum);'#13#10 +                     { 8 }
    'end;'#13#10 +                                { 9 }
    'end.'#13#10;                                 { 10 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  { extract only line 7 -- `sum` is live after it (read on line 8, outside
    the run) -> Outputs = defs [sum] INTERSECT live-out [sum] = [sum]. }
  V:= ClassifyFor(SRC, 7, 7, Names);
  Check('classify-b: no refuse', V.Refuse = '');
  Check('classify-b: OutputIdx is sum', (V.OutputIdx >= 0) and (Names[V.OutputIdx] = 'sum'));
  Check('classify-b: Inputs does not contain sum', not ContainsVarName(V.Inputs, Names, 'sum'));
  Check('classify-b: OutputIsInput = False', not V.OutputIsInput);
  Check('classify-b: Internals empty', Length(V.Internals) = 0);
end;

{ (c) `x := x + d;` -- x is read (rhs) before being defined by the SAME
  statement, and live after (read on the following line) -> x is both an
  Input (upward-exposed use) and the Output (def INTERSECT live-out) ->
  OutputIsInput = True. Inputs also contains d. }
procedure TestClassifyInOutSameVar;
const
  SRC =
    'unit u;'#13#10 +                             { 1 }
    'interface'#13#10 +                           { 2 }
    'implementation'#13#10 +                      { 3 }
    'procedure P(d: Integer);'#13#10 +             { 4 }
    'var x: Integer;'#13#10 +                     { 5 }
    'begin'#13#10 +                               { 6 }
    '  x := 1;'#13#10 +                           { 7 }
    '  x := x + d;'#13#10 +                       { 8 }
    '  Writeln(x);'#13#10 +                       { 9 }
    'end;'#13#10 +                                { 10 }
    'end.'#13#10;                                 { 11 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  { extract only line 8: `x` is upward-exposed (read on the rhs, no prior def
    inside the run) AND live-out (read on line 9) -> in+out single var. }
  V:= ClassifyFor(SRC, 8, 8, Names);
  Check('classify-c: no refuse', V.Refuse = '');
  Check('classify-c: OutputIdx is x', (V.OutputIdx >= 0) and (Names[V.OutputIdx] = 'x'));
  Check('classify-c: OutputIsInput = True', V.OutputIsInput);
  Check('classify-c: Inputs contains x', ContainsVarName(V.Inputs, Names, 'x'));
  Check('classify-c: Inputs contains d', ContainsVarName(V.Inputs, Names, 'd'));
  { the brief requires Inputs "in run order of first use": on the rhs
    `x + d`, x is read before d (left-to-right) -> x at position 0, d at 1 }
  Check('classify-c: Inputs = [x, d] in first-use order',
    (Length(V.Inputs) = 2)
    and (IndexOfVarName(V.Inputs, Names, 'x') = 0)
    and (IndexOfVarName(V.Inputs, Names, 'd') = 1));
  Check('classify-c: Internals empty', Length(V.Internals) = 0);
end;

{ (d) run defines two locals, BOTH live after -> 2 values would need to
  escape the extracted method; Extract Method supports only a single Result,
  so this must refuse rather than guess which one to return. }
procedure TestClassifyTwoOutputsRefuses;
const
  SRC =
    'unit u;'#13#10 +                             { 1 }
    'interface'#13#10 +                           { 2 }
    'implementation'#13#10 +                      { 3 }
    'procedure P(a: Integer);'#13#10 +             { 4 }
    'var x, y: Integer;'#13#10 +                  { 5 }
    'begin'#13#10 +                               { 6 }
    '  x := a + 1;'#13#10 +                       { 7 }
    '  y := a + 2;'#13#10 +                       { 8 }
    '  Writeln(x + y);'#13#10 +                   { 9 }
    'end;'#13#10 +                                { 10 }
    'end.'#13#10;                                 { 11 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  V:= ClassifyFor(SRC, 7, 8, Names);
  Check('classify-d: refuses', V.Refuse <> '');
  Check('classify-d: reason mentions 2 values escape', Pos('2 values escape', V.Refuse) > 0);
end;

{ (e) an Input's declared type is unknown (empty TypeText) -- an inline
  `var t := ...` local has no recorded type text (TRoutineVarTable.Build
  never infers one for inline decls) -- so if a LATER run reads it as an
  upward-exposed use, Extract Method cannot synthesize a typed parameter for
  it and must refuse rather than guess the type. }
procedure TestClassifyUnknownTypeRefuses;
const
  SRC =
    'unit u;'#13#10 +                             { 1 }
    'interface'#13#10 +                           { 2 }
    'implementation'#13#10 +                      { 3 }
    'procedure P;'#13#10 +                         { 4 }
    'begin'#13#10 +                               { 5 }
    '  var t := 1;'#13#10 +                       { 6  inline decl -- TypeText = '' }
    '  Writeln(t);'#13#10 +                       { 7  run: upward-exposed use of t }
    'end;'#13#10 +                                { 8 }
    'end.'#13#10;                                 { 9 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  V:= ClassifyFor(SRC, 7, 7, Names);
  Check('classify-e: refuses', V.Refuse <> '');
  Check('classify-e: reason mentions unknown type', Pos('unknown type', V.Refuse) > 0);
end;

{ (f) COMPOUND-TAIL live-out: the run's LAST statement is an if/else whose
  branches live in separate CFG blocks. u := a + 1 is a must-defined local
  consumed only inside the run; t is assigned in BOTH branches (must-def on
  every path) and read after the selection -> the single output. Expected:
  Inputs = [a, c, b] (first-use order: a on line 7, condition c on line 8,
  b on line 11 -- u is read on line 9 but AFTER its own def, so not an
  input, and t is only written, never upward-exposed), OutputIdx = t,
  OutputIsInput = False, Internals = [u]. Also locks in that the live-out
  boundary excludes INTERIOR liveness: values only live BETWEEN run items
  (u and b are live after the condition, inside the run) must not leak into
  live-out and wrongly become outputs. }
procedure TestClassifyCompoundTailIfElse;
const
  SRC =
    'unit u;'#13#10 +                                 { 1 }
    'interface'#13#10 +                               { 2 }
    'implementation'#13#10 +                          { 3 }
    'procedure P(a, b: Integer; c: Boolean);'#13#10 +  { 4 }
    'var t, u: Integer;'#13#10 +                      { 5 }
    'begin'#13#10 +                                   { 6 }
    '  u := a + 1;'#13#10 +                           { 7  run start }
    '  if c then'#13#10 +                             { 8  compound tail }
    '    t := u'#13#10 +                              { 9 }
    '  else'#13#10 +                                  { 10 }
    '    t := b;'#13#10 +                             { 11  run end }
    '  Writeln(t);'#13#10 +                           { 12  t read after -> output }
    'end;'#13#10 +                                    { 13 }
    'end.'#13#10;                                     { 14 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  V:= ClassifyFor(SRC, 7, 11, Names);
  Check('classify-f: no refuse', V.Refuse = '');
  Check('classify-f: OutputIdx is t',
    (V.OutputIdx >= 0) and (V.OutputIdx < Length(Names)) and (Names[V.OutputIdx] = 't'));
  Check('classify-f: OutputIsInput = False', not V.OutputIsInput);
  Check('classify-f: Inputs = [a, c, b] in first-use order',
    (Length(V.Inputs) = 3)
    and (IndexOfVarName(V.Inputs, Names, 'a') = 0)
    and (IndexOfVarName(V.Inputs, Names, 'c') = 1)
    and (IndexOfVarName(V.Inputs, Names, 'b') = 2));
  Check('classify-f: t not an Input', not ContainsVarName(V.Inputs, Names, 't'));
  Check('classify-f: Internals = [u]',
    (Length(V.Internals) = 1) and ContainsVarName(V.Internals, Names, 'u'));
end;

{ (g) a var assigned only inside ONE branch of the run's compound tail and
  DEAD afterwards (never read anywhere else in the routine) is a plain
  Internal: a may-def that does not escape. Nothing the run defines is live
  after -> OutputIdx = -1. Expected: Inputs = [c, a] (condition first),
  Internals = [v]. }
procedure TestClassifyBranchLocalDeadIsInternal;
const
  SRC =
    'unit u;'#13#10 +                                 { 1 }
    'interface'#13#10 +                               { 2 }
    'implementation'#13#10 +                          { 3 }
    'procedure P(a: Integer; c: Boolean);'#13#10 +     { 4 }
    'var v: Integer;'#13#10 +                         { 5 }
    'begin'#13#10 +                                   { 6 }
    '  if c then'#13#10 +                             { 7  run start (single if statement) }
    '    v := a;'#13#10 +                             { 8  run end -- v assigned on one path only }
    '  Writeln(a);'#13#10 +                           { 9  v NOT read after -> dead -> not an output }
    'end;'#13#10 +                                    { 10 }
    'end.'#13#10;                                     { 11 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  V:= ClassifyFor(SRC, 7, 8, Names);
  Check('classify-g: no refuse', V.Refuse = '');
  Check('classify-g: OutputIdx = -1', V.OutputIdx = -1);
  Check('classify-g: Internals = [v]',
    (Length(V.Internals) = 1) and ContainsVarName(V.Internals, Names, 'v'));
  Check('classify-g: Inputs = [c, a] in first-use order',
    (Length(V.Inputs) = 2)
    and (IndexOfVarName(V.Inputs, Names, 'c') = 0)
    and (IndexOfVarName(V.Inputs, Names, 'a') = 1));
end;

{ (h) a var assigned on only SOME paths through the run (one branch of an
  if without else) but read AFTER the selection: on the unassigned path the
  caller's old value survives, i.e. pass-through in/out semantics that v1's
  single-Result synthesis does not support -> must REFUSE (mentioning the
  conditional assignment), never silently classify it as a plain output. }
procedure TestClassifyConditionalEscapeRefuses;
const
  SRC =
    'unit u;'#13#10 +                                 { 1 }
    'interface'#13#10 +                               { 2 }
    'implementation'#13#10 +                          { 3 }
    'procedure P(a: Integer; c: Boolean);'#13#10 +     { 4 }
    'var v: Integer;'#13#10 +                         { 5 }
    'begin'#13#10 +                                   { 6 }
    '  v := 0;'#13#10 +                               { 7  v defined BEFORE the run }
    '  if c then'#13#10 +                             { 8  run start }
    '    v := a;'#13#10 +                             { 9  run end -- v assigned on one path only }
    '  Writeln(v);'#13#10 +                           { 10  v read after -> escapes conditionally }
    'end;'#13#10 +                                    { 11 }
    'end.'#13#10;                                     { 12 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  V:= ClassifyFor(SRC, 8, 9, Names);
  Check('classify-h: refuses', V.Refuse <> '');
  Check('classify-h: reason mentions conditionally assigned',
    Pos('conditionally assigned', V.Refuse) > 0);
end;

{ (i) CARRY-OVER (Task 3 review): the run ENDS on a try-finally whose try body
  assigns the escaping var. The optimistic try-finally must-def model treats a
  var assigned in the try body as must-defined downstream (code after the try
  only runs on normal completion; an exception propagates out of the routine).
  Here v is assigned in the try body and read after the run -> a valid single
  output, NOT a conditionally-assigned refuse. Pins that model before synthesis
  relies on it. }
procedure TestClassifyTryFinallyTailMustDef;
const
  SRC =
    'unit u;'#13#10 +                                 { 1 }
    'interface'#13#10 +                               { 2 }
    'implementation'#13#10 +                          { 3 }
    'procedure P(a: Integer);'#13#10 +                 { 4 }
    'var v: Integer;'#13#10 +                         { 5 }
    'begin'#13#10 +                                   { 6 }
    '  try'#13#10 +                                   { 7  run start (single try statement) }
    '    v := a + 1;'#13#10 +                         { 8 }
    '  finally'#13#10 +                               { 9 }
    '    Writeln(''done'');'#13#10 +                  { 10 }
    '  end;'#13#10 +                                  { 11  run end }
    '  Writeln(v);'#13#10 +                           { 12  v read after -> escapes }
    'end;'#13#10 +                                    { 13 }
    'end.'#13#10;                                     { 14 }
var
  V: TExtractVars;
  Names: TArray<string>;
begin
  { extract the whole try-finally (lines 7-11): v is assigned in the try body,
    must-defined downstream by the optimistic model, and live after -> output. }
  V:= ClassifyFor(SRC, 7, 11, Names);
  Check('classify-i: no refuse (optimistic try-finally must-def)', V.Refuse = '');
  Check('classify-i: OutputIdx is v',
    (V.OutputIdx >= 0) and (V.OutputIdx < Length(Names)) and (Names[V.OutputIdx] = 'v'));
  Check('classify-i: OutputIsInput = False', not V.OutputIsInput);
  Check('classify-i: Inputs contains a', ContainsVarName(V.Inputs, Names, 'a'));
end;

{ ===========================================================================
  Task 4: method synthesis + edit emission (Build)
  =========================================================================== }

{ Write ASource to a temp .pas, call Build over [AFromLine..AToLine], APPLY the
  returned edits IN PLACE (TTextEditApplier reads/writes the file), and read the
  edited source back. AReason = the refuse reason ('' on success). On refuse the
  file is returned unchanged. Mirrors RefuseFor's temp-file / parse-cache
  discipline. }
function SynthFor(const ASource: string; AFromLine, AToLine: Integer;
  const ANewName: string; out AReason: string): string;
var
  P: string;
  Edits: TArray<TTextEdit>;
begin
  P:= TPath.Combine(TPath.GetTempPath, 'em_synth_' + TPath.GetGUIDFileName + '.pas');
  TFile.WriteAllText(P, ASource, TEncoding.ANSI);
  TAstParseCache.Clear;
  try
    Edits:= TExtractMethodRefactoring.Build(P, AFromLine, AToLine, ANewName, AReason);
    if (AReason = '') and (Length(Edits) > 0) then
      TTextEditApplier.Apply(Edits, False);
    Result:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(P));
  finally
    TAstParseCache.Clear;
    if TFile.Exists(P) then TFile.Delete(P);
  end;
end;

{ (a) 0-output procedure extraction (free routine). Inputs = [a], no output,
  internal local t. The new proc is inserted BEFORE the caller; the moved
  local t is removed from the caller (emptying its var section -> the `var`
  line goes too); the run is replaced with the call `Extracted(a);`. }
procedure TestSynth0OutputProc;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P(a: Integer);'#13#10 +          { 4 }
    'var t: Integer;'#13#10 +                  { 5 }
    'begin'#13#10 +                            { 6 }
    '  t := a + 1;'#13#10 +                    { 7 }
    '  Writeln(t);'#13#10 +                    { 8 }
    'end;'#13#10 +                             { 9 }
    'end.'#13#10;                              { 10 }
  EXPECTED =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Extracted(a: Integer);'#13#10 +
    'var'#13#10 +
    '  t: Integer;'#13#10 +
    'begin'#13#10 +
    '  t := a + 1;'#13#10 +
    '  Writeln(t);'#13#10 +
    'end;'#13#10 +
    ''#13#10 +
    'procedure P(a: Integer);'#13#10 +
    'begin'#13#10 +
    '  Extracted(a);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Reason, Got: string;
begin
  Got:= SynthFor(SRC, 7, 8, 'Extracted', Reason);
  Check('synth-0out: no refuse', Reason = '');
  Check('synth-0out: edited source matches', Got = EXPECTED);
  if Got <> EXPECTED then begin Writeln('--- GOT ---'); Writeln(Got); Writeln('--- EXPECTED ---'); Writeln(EXPECTED); end;
end;

{ (b) 1-output function (free routine). Inputs = [a, b], Output = sum (a local,
  not an input) -> return type Integer, sum declared as a new-method local,
  `Result := sum;` appended. Call site is `sum := Compute(a, b);`; sum stays in
  the caller's var section (still read after the run). }
procedure TestSynth1OutputFunction;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P(a, b: Integer);'#13#10 +       { 4 }
    'var sum: Integer;'#13#10 +                { 5 }
    'begin'#13#10 +                            { 6 }
    '  sum := a + b;'#13#10 +                  { 7 }
    '  Writeln(sum);'#13#10 +                  { 8 }
    'end;'#13#10 +                             { 9 }
    'end.'#13#10;                              { 10 }
  EXPECTED =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function Compute(a, b: Integer): Integer;'#13#10 +
    'var'#13#10 +
    '  sum: Integer;'#13#10 +
    'begin'#13#10 +
    '  sum := a + b;'#13#10 +
    '  Result := sum;'#13#10 +
    'end;'#13#10 +
    ''#13#10 +
    'procedure P(a, b: Integer);'#13#10 +
    'var sum: Integer;'#13#10 +
    'begin'#13#10 +
    '  sum := Compute(a, b);'#13#10 +
    '  Writeln(sum);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Reason, Got: string;
begin
  Got:= SynthFor(SRC, 7, 7, 'Compute', Reason);
  Check('synth-1out: no refuse', Reason = '');
  Check('synth-1out: edited source matches', Got = EXPECTED);
  if Got <> EXPECTED then begin Writeln('--- GOT ---'); Writeln(Got); Writeln('--- EXPECTED ---'); Writeln(EXPECTED); end;
end;

{ (c) in+out single var (free routine). x is both upward-exposed (read on the
  rhs before any def in the run) and live-out -> OutputIsInput. x becomes a
  value parameter (Delphi value params are assignable), `Result := x;` is
  appended, and the call site is `x := Bump(x, d);`. No new-method locals. }
procedure TestSynthInOutSingleVar;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P(d: Integer);'#13#10 +          { 4 }
    'var x: Integer;'#13#10 +                  { 5 }
    'begin'#13#10 +                            { 6 }
    '  x := 1;'#13#10 +                        { 7 }
    '  x := x + d;'#13#10 +                    { 8 }
    '  Writeln(x);'#13#10 +                    { 9 }
    'end;'#13#10 +                             { 10 }
    'end.'#13#10;                              { 11 }
  EXPECTED =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'function Bump(x, d: Integer): Integer;'#13#10 +
    'begin'#13#10 +
    '  x := x + d;'#13#10 +
    '  Result := x;'#13#10 +
    'end;'#13#10 +
    ''#13#10 +
    'procedure P(d: Integer);'#13#10 +
    'var x: Integer;'#13#10 +
    'begin'#13#10 +
    '  x := 1;'#13#10 +
    '  x := Bump(x, d);'#13#10 +
    '  Writeln(x);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Reason, Got: string;
begin
  Got:= SynthFor(SRC, 8, 8, 'Bump', Reason);
  Check('synth-inout: no refuse', Reason = '');
  Check('synth-inout: edited source matches', Got = EXPECTED);
  if Got <> EXPECTED then begin Writeln('--- GOT ---'); Writeln(Got); Writeln('--- EXPECTED ---'); Writeln(EXPECTED); end;
end;

{ (d) internal-local move with survivors. t is an internal moved into the new
  method; keep is used outside the run and must stay in the caller. Only t's
  own `declVar` line is deleted; the `var` keyword and `keep` survive. }
procedure TestSynthInternalLocalMove;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P(a: Integer);'#13#10 +          { 4 }
    'var'#13#10 +                              { 5 }
    '  t: Integer;'#13#10 +                    { 6 }
    '  keep: Integer;'#13#10 +                 { 7 }
    'begin'#13#10 +                            { 8 }
    '  keep := 5;'#13#10 +                     { 9 }
    '  t := a + 1;'#13#10 +                    { 10 }
    '  Writeln(t);'#13#10 +                    { 11 }
    '  Writeln(keep);'#13#10 +                 { 12 }
    'end;'#13#10 +                             { 13 }
    'end.'#13#10;                              { 14 }
  EXPECTED =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Inner(a: Integer);'#13#10 +
    'var'#13#10 +
    '  t: Integer;'#13#10 +
    'begin'#13#10 +
    '  t := a + 1;'#13#10 +
    '  Writeln(t);'#13#10 +
    'end;'#13#10 +
    ''#13#10 +
    'procedure P(a: Integer);'#13#10 +
    'var'#13#10 +
    '  keep: Integer;'#13#10 +
    'begin'#13#10 +
    '  keep := 5;'#13#10 +
    '  Inner(a);'#13#10 +
    '  Writeln(keep);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Reason, Got: string;
begin
  Got:= SynthFor(SRC, 10, 11, 'Inner', Reason);
  Check('synth-internal-move: no refuse', Reason = '');
  Check('synth-internal-move: edited source matches', Got = EXPECTED);
  if Got <> EXPECTED then begin Writeln('--- GOT ---'); Writeln(Got); Writeln('--- EXPECTED ---'); Writeln(EXPECTED); end;
end;

{ (e) method extraction into a class with a private section. The new method's
  declaration goes into the private declSection; its implementation goes AFTER
  the enclosing method's end; qualified with the owner class name. }
procedure TestSynthMethodIntoPrivate;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'type'#13#10 +                             { 3 }
    '  TFoo = class'#13#10 +                   { 4 }
    '  private'#13#10 +                        { 5 }
    '    FBar: Integer;'#13#10 +               { 6 }
    '  public'#13#10 +                         { 7 }
    '    procedure Go(a: Integer);'#13#10 +    { 8 }
    '  end;'#13#10 +                           { 9 }
    'implementation'#13#10 +                   { 10 }
    'procedure TFoo.Go(a: Integer);'#13#10 +   { 11 }
    'var t: Integer;'#13#10 +                  { 12 }
    'begin'#13#10 +                            { 13 }
    '  t := a + 1;'#13#10 +                    { 14 }
    '  Writeln(t);'#13#10 +                    { 15 }
    'end;'#13#10 +                             { 16 }
    'end.'#13#10;                              { 17 }
  EXPECTED =
    'unit u;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '  private'#13#10 +
    '    FBar: Integer;'#13#10 +
    '    procedure Helper(a: Integer);'#13#10 +
    '  public'#13#10 +
    '    procedure Go(a: Integer);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Go(a: Integer);'#13#10 +
    'begin'#13#10 +
    '  Helper(a);'#13#10 +
    'end;'#13#10 +
    ''#13#10 +
    'procedure TFoo.Helper(a: Integer);'#13#10 +
    'var'#13#10 +
    '  t: Integer;'#13#10 +
    'begin'#13#10 +
    '  t := a + 1;'#13#10 +
    '  Writeln(t);'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Reason, Got: string;
begin
  Got:= SynthFor(SRC, 14, 15, 'Helper', Reason);
  Check('synth-method: no refuse', Reason = '');
  Check('synth-method: edited source matches', Got = EXPECTED);
  if Got <> EXPECTED then begin Writeln('--- GOT ---'); Writeln(Got); Writeln('--- EXPECTED ---'); Writeln(EXPECTED); end;
end;

{ (f) name collision -> Build refuses. The class already declares a member named
  'Go'; extracting a new method also called 'Go' would collide -> refuse, no
  edits. }
procedure TestSynthCollisionRefuses;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'type'#13#10 +                             { 3 }
    '  TFoo = class'#13#10 +                   { 4 }
    '  private'#13#10 +                        { 5 }
    '    FBar: Integer;'#13#10 +               { 6 }
    '  public'#13#10 +                         { 7 }
    '    procedure Go(a: Integer);'#13#10 +    { 8 }
    '  end;'#13#10 +                           { 9 }
    'implementation'#13#10 +                   { 10 }
    'procedure TFoo.Go(a: Integer);'#13#10 +   { 11 }
    'var t: Integer;'#13#10 +                  { 12 }
    'begin'#13#10 +                            { 13 }
    '  t := a + 1;'#13#10 +                    { 14 }
    '  Writeln(t);'#13#10 +                    { 15 }
    'end;'#13#10 +                             { 16 }
    'end.'#13#10;                              { 17 }
var
  Reason, Got: string;
begin
  { new name 'Go' already exists as a member of TFoo }
  Got:= SynthFor(SRC, 14, 15, 'Go', Reason);
  Check('synth-collision: refuses', Reason <> '');
  Check('synth-collision: reason mentions already exists', Pos('already exists', Reason) > 0);
  Check('synth-collision: source unchanged', Got = SRC);
end;

{ (g) method extraction where the class has NO private section -> Build refuses
  rather than guess where to put the declaration. }
procedure TestSynthNoPrivateSectionRefuses;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'type'#13#10 +                             { 3 }
    '  TFoo = class'#13#10 +                   { 4 }
    '  public'#13#10 +                         { 5 }
    '    procedure Go(a: Integer);'#13#10 +    { 6 }
    '  end;'#13#10 +                           { 7 }
    'implementation'#13#10 +                   { 8 }
    'procedure TFoo.Go(a: Integer);'#13#10 +   { 9 }
    'var t: Integer;'#13#10 +                  { 10 }
    'begin'#13#10 +                            { 11 }
    '  t := a + 1;'#13#10 +                    { 12 }
    '  Writeln(t);'#13#10 +                    { 13 }
    'end;'#13#10 +                             { 14 }
    'end.'#13#10;                              { 15 }
var
  Reason, Got: string;
begin
  Got:= SynthFor(SRC, 12, 13, 'Helper', Reason);
  Check('synth-no-private: refuses', Reason <> '');
  Check('synth-no-private: reason mentions private section', Pos('private section', Reason) > 0);
  Check('synth-no-private: source unchanged', Got = SRC);
end;

{ (h) an Internal to move shares a multi-variable declaration line
  (`var x, y: Integer;`) with a var that stays. v1 does not rewrite/split a
  shared declaration line, so Build refuses rather than corrupt it. }
procedure TestSynthMultiVarSplitRefuses;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P;'#13#10 +                      { 4 }
    'var x, y: Integer;'#13#10 +               { 5  x internal, y output -> shared line }
    'begin'#13#10 +                            { 6 }
    '  x := 1;'#13#10 +                        { 7 }
    '  y := x + 1;'#13#10 +                    { 8 }
    '  Writeln(y);'#13#10 +                    { 9 }
    'end;'#13#10 +                             { 10 }
    'end.'#13#10;                              { 11 }
var
  Reason, Got: string;
begin
  Got:= SynthFor(SRC, 7, 8, 'NewMeth', Reason);
  Check('synth-multivar-split: refuses', Reason <> '');
  Check('synth-multivar-split: reason mentions multi-variable', Pos('multi-variable', Reason) > 0);
  Check('synth-multivar-split: source unchanged', Got = SRC);
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestSpansTwoRoutines;
    TestCutsStatement;
    TestGotoRoutine;
    TestContainsExit;
    TestEscapingBreak;
    TestCrossesNesting;
    TestSameLineSiblings;
    TestSafeSelectionSynthesizes;
    TestClassifyInputOnlyNoOutput;
    TestClassifyOutputUsedAfter;
    TestClassifyInOutSameVar;
    TestClassifyTwoOutputsRefuses;
    TestClassifyUnknownTypeRefuses;
    TestClassifyCompoundTailIfElse;
    TestClassifyBranchLocalDeadIsInternal;
    TestClassifyConditionalEscapeRefuses;
    TestClassifyTryFinallyTailMustDef;
    TestSynth0OutputProc;
    TestSynth1OutputFunction;
    TestSynthInOutSingleVar;
    TestSynthInternalLocalMove;
    TestSynthMethodIntoPrivate;
    TestSynthCollisionRefuses;
    TestSynthNoPrivateSectionRefuses;
    TestSynthMultiVarSplitRefuses;
  except
    on Ex: Exception do begin Writeln('EXCEPTION ', Ex.ClassName, ': ', Ex.Message); Inc(GFail); end;
  end;

  Writeln('');
  Writeln(Format('extractmethod-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
