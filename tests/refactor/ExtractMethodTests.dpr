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
  escaping control flow reaches the 'not-yet-implemented' refuse (Tasks 3-4
  fill in synthesis) rather than any of the guard refusals above. }
procedure TestSafeSelectionReachesNotYetImplemented;
const
  SRC =
    'unit u;'#13#10 +                          { 1 }
    'interface'#13#10 +                        { 2 }
    'implementation'#13#10 +                   { 3 }
    'procedure P;'#13#10 +                      { 4 }
    'var x, y: Integer;'#13#10 +               { 5 }
    'begin'#13#10 +                            { 6 }
    '  x := 1;'#13#10 +                        { 7 }
    '  y := x + 1;'#13#10 +                    { 8 }
    '  Writeln(y);'#13#10 +                    { 9 }
    'end;'#13#10 +                             { 10 }
    'end.'#13#10;                              { 11 }
var
  Reason: string;
  Edits: TArray<TTextEdit>;
begin
  Reason:= RefuseFor(SRC, 7, 8, 'NewMeth', Edits);
  Check('safe-selection: reaches not-yet-implemented', Reason = 'not-yet-implemented');
  Check('safe-selection: nil edits (not yet synthesized)', Edits = nil);
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
    TestSafeSelectionReachesNotYetImplemented;
  except
    on Ex: Exception do begin Writeln('EXCEPTION ', Ex.ClassName, ': ', Ex.Message); Inc(GFail); end;
  end;

  Writeln('');
  Writeln(Format('extractmethod-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
