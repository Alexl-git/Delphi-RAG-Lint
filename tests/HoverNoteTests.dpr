program HoverNoteTests;

{$APPTYPE CONSOLE}

{ Lane 1.54.1 HOVERNOTE: the status strip's hover note and progress, driven
  outside the IDE (tests\plugin\run_v1541_HOVERNOTE.ps1).

  T = token under a position   N = note texts      C = pointer column
  M = empty-answer memo        S = strip texts     L = strip layout }
uses
  System.SysUtils,
  DragLint.Plugin.HoverNote in '..\src\delphi-plugin\DragLint.Plugin.HoverNote.pas';

const
  { rows: 0 unit, 1 blank, 2-3 block comment, 4 code, 5 code, 6 directive, 7-9 multi-line string, 10 tail }
  SRC =
    'unit Demo;'#13#10 +
    '   '#13#10 +
    '{ first DoExport'#13#10 +
    '  second line }'#13#10 +
    'function DoExport(const A: Integer): string; override;'#13#10 +
    '  X := ''it''''s text'' + #13 + $FF + 1.5E+3; // tail note'#13#10 +
    '{$IFDEF WIN64} for I:= 1..9 do Y:= &begin;'#13#10 +
    '  S:= '''''''#13#10 +
    '    body ''quoted'' word'#13#10 +
    '    '''''';'#13#10 +
    'end.';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
  begin
    Inc(GPass);
    Writeln('PASS  ', AName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName, '  ', ADetail);
  end;
end;

procedure TokenIs(const AName: string; ARow, ACol: Integer; AKind: TDLTokenKind; const AText: string);
var
  T: TDLToken;
begin
  T:= DLTokenInText(SRC, ARow, ACol);
  Check(AName, (T.Kind = AKind) and (T.Text = AText), Format('got %s "%s" %d..%d', [DLTokenKindName(T.Kind), T.Text, T.Start0, T.End0]));
end;

procedure TestTokens;
var
  T: TDLToken;
begin
  TokenIs('T1 keyword at column 0'                     , 0, 0 , htkKeyword , 'unit');
  TokenIs('T2 identifier'                              , 0, 6 , htkIdent   , 'Demo');
  TokenIs('T3 blank row'                               , 1, 1 , htkBlank   , '');
  TokenIs('T4 word in a block comment'                 , 2, 10, htkInComment, 'DoExport');
  TokenIs('T5 second row of a block comment'           , 3, 3 , htkInComment, 'second');
  TokenIs('T6 the SAME name in code is an identifier'  , 4, 12, htkIdent   , 'DoExport');
  TokenIs('T7 reserved type word'                      , 4, 38, htkKeyword , 'string');
  TokenIs('T8 directive word'                          , 4, 47, htkDirective, 'override');
  TokenIs('T9 two-character operator'                  , 5, 5 , htkOperator, ':=');
  TokenIs('T10 word in a string with a doubled quote'  , 5, 14, htkInString, 'text');
  TokenIs('T11 operator after the string'              , 5, 20, htkOperator, '+');
  TokenIs('T12 character constant'                     , 5, 22, htkInString, '#13');
  TokenIs('T13 hex number'                             , 5, 28, htkNumber  , '$FF');
  TokenIs('T14 real number'                            , 5, 36, htkNumber  , '1.5E+3');
  TokenIs('T15 line comment'                           , 5, 46, htkInComment, 'tail');
  TokenIs('T16 blank inside a comment'                 , 5, 44, htkBlank   , '');
  TokenIs('T17 compiler directive'                     , 6, 3 , htkInCompilerDirective, 'IFDEF');
  TokenIs('T18 range start is one digit'               , 6, 23, htkNumber  , '1');
  TokenIs('T19 range operator'                         , 6, 24, htkOperator, '..');
  TokenIs('T20 escaped keyword is an identifier'       , 6, 37, htkIdent   , '&begin');
  TokenIs('T21 word in a multi-line string'            , 8, 11, htkInString, 'quoted');
  TokenIs('T22 code after a multi-line string'         , 10, 1, htkKeyword , 'end');
  TokenIs('T23 past the end of the line'               , 0, 40, htkBlank   , '');
  TokenIs('T24 past the end of the file'               , 971, 0, htkBlank  , '');
  TokenIs('T25 last character of the file'             , 10, 3, htkOperator, '.');
  T:= DLTokenInText(SRC, 4, 12);
  Check('T26 the span is the identifier', (T.Start0 = 9) and (T.End0 = 17), Format('%d..%d', [T.Start0, T.End0]));
  T:= DLTokenInText(SRC, 0, 40);
  Check('T27 the blank past a line starts at its end and has no end', (T.Start0 = 10) and (T.End0 = MaxInt), Format('%d..%d', [T.Start0, T.End0]));
  T:= DLCaretTokenInText(SRC, 4, 17);
  Check('T28 a caret just after a name is on that name', (T.Kind = htkIdent) and (T.Text = 'DoExport'), T.Text);
  Check('T29 control: the POINTER just after it is on the parenthesis', DLTokenInText(SRC, 4, 17).Text = '(');
  Check('T30 empty source', DLTokenInText('', 0, 0).Kind = htkBlank);
end;

procedure NoteIs(const AName: string; ARow, ACol: Integer; const AText: string);
var
  N: string;
begin
  N:= DLEmptyAnswerNote(DLTokenInText(SRC, ARow, ACol));
  Check(AName, N = AText, N);
end;

procedure TestNotes;
var
  Long: TDLToken;
begin
  NoteIs('N1 identifier'        , 4, 12 , 'drag-lint: ''DoExport'' is not indexed');
  NoteIs('N2 keyword'           , 4, 0  , 'drag-lint: ''function'' (keyword)');
  NoteIs('N3 comment'           , 2, 10 , 'drag-lint: ''DoExport'' (in a comment)');
  NoteIs('N4 string'            , 5, 14 , 'drag-lint: ''text'' (in a string)');
  NoteIs('N5 number'            , 5, 28 , 'drag-lint: ''$FF'' (number)');
  NoteIs('N6 operator'          , 5, 5  , 'drag-lint: '':='' (operator)');
  NoteIs('N7 blank row'         , 1, 0  , 'drag-lint: <SPACE> is under the cursor');
  NoteIs('N8 past end of line'  , 0, 99 , 'drag-lint: <SPACE> is under the cursor');
  NoteIs('N9 past end of file'  , 825, 20, 'drag-lint: <SPACE> is under the cursor');
  NoteIs('N10 directive'        , 4, 47 , 'drag-lint: ''override'' (directive)');
  Check('N11 announce names the asked token', DLHoverAnnounceNote(DLTokenInText(SRC, 4, 12)) = 'drag-lint: hover DoExport...',
    DLHoverAnnounceNote(DLTokenInText(SRC, 4, 12)));
  Check('N12 announce of a blank', DLHoverAnnounceNote(DLTokenInText(SRC, 1, 0)) = 'drag-lint: <SPACE> is under the cursor');
  Long     := DLTokenInText(StringOfChar('a', 200), 0, 5);
  Check('N13 a very long token is cut', Length(DLEmptyAnswerNote(Long)) < 110, IntToStr(Length(DLEmptyAnswerNote(Long))));
end;

procedure TestColumns;
var
  C: Integer;
begin
  Check('C1 gutter: left of the code', (DLColumnAt(39, 40, 8, 1, C) = hcvGutter) and (C = -1), IntToStr(C));
  Check('C2 first pixel of the code is column 0', (DLColumnAt(40, 40, 8, 1, C) = hcvText) and (C = 0), IntToStr(C));
  Check('C3 last pixel of a cell', (DLColumnAt(47, 40, 8, 1, C) = hcvText) and (C = 0), IntToStr(C));
  Check('C4 column 9', (DLColumnAt(40 + 9 * 8 + 3, 40, 8, 1, C) = hcvText) and (C = 9), IntToStr(C));
  Check('C5 scrolled 20 columns to the right', (DLColumnAt(40 + 9 * 8, 40, 8, 21, C) = hcvText) and (C = 29), IntToStr(C));
  Check('C6 no char width: no cell', (DLColumnAt(100, 40, 0, 1, C) = hcvNoGrid) and (C = -1), IntToStr(C));
  Check('C7 no left column: no cell', (DLColumnAt(100, 40, 8, 0, C) = hcvNoGrid) and (C = -1), IntToStr(C));
end;

procedure TestMemo;
var
  M: TDLEmptyMemo;
  T: TDLToken;
begin
  M.Clear;
  T:= DLTokenInText(SRC, 4, 12);
  Check('M1 nothing remembered', not M.Holds('a.pas', 4, 12, 1));
  M.Remember('a.pas', 4, T, 1);
  Check('M2 the same token is not asked again', M.Holds('A.PAS', 4, 16, 1));
  Check('M3 control: the next token IS asked', not M.Holds('a.pas', 4, 17, 1));
  Check('M4 control: another row IS asked', not M.Holds('a.pas', 5, 12, 1));
  Check('M5 control: another file IS asked', not M.Holds('b.pas', 4, 12, 1));
  Check('M6 an index job finished: asked again', not M.Holds('a.pas', 4, 12, 2));
  M.Clear;
  Check('M7 re-dwell: asked again', not M.Holds('a.pas', 4, 12, 1));
  M.Remember('a.pas', 971, DLTokenInText(SRC, 971, 0), 1);
  Check('M8 past the end of the file is one place', M.Holds('a.pas', 971, 300, 1));
end;

procedure TextsAre(const AName: string; const AJob: TDLStripJob; const ANote, ALeft, AProgress: string);
var
  L, P: string;
begin
  DLStripTexts(AJob, ANote, 'drag-lint: idle', L, P);
  Check(AName, (L = ALeft) and (P = AProgress), Format('left="%s" progress="%s"', [L, P]));
end;

procedure TestStripTexts;
const
  NOTE = 'drag-lint: ''DoExport'' is not indexed';
var
  Idle, Idx, Lint: TDLStripJob;
begin
  Idle := Default(TDLStripJob);
  Idx  := Default(TDLStripJob);
  Idx.Running:= True;
  Idx.IsIndex:= True;
  Idx.Title  := 'Reindex drag-lint';
  Idx.Percent:= 42;
  Idx.Phase  := 'parse';
  Lint       := Idx;
  Lint.IsIndex:= False;
  Lint.Title := 'Lint all';
  TextsAre('S1 idle, no note'                    , Idle, ''  , 'drag-lint: idle', '');
  TextsAre('S2 idle, note'                       , Idle, NOTE, NOTE, '');
  TextsAre('S3 index job + note: both'           , Idx , NOTE, NOTE, 'reindexing... 42% parse');
  TextsAre('S4 index job, no note: as before'    , Idx , ''  , '', 'Reindex drag-lint  42%  parse');
  TextsAre('S5 other job + note: both'           , Lint, NOTE, NOTE, 'Lint all  42%  parse');
  Idx.Percent:= -1;
  TextsAre('S6 index job, unknown percent + note', Idx , NOTE, NOTE, 'reindexing...');
  TextsAre('S7 unknown percent, no note'         , Idx , ''  , '', 'Reindex drag-lint  ...');
  Idx.Beat   := 'files 10/20';
  TextsAre('S8 heartbeat + note'                 , Idx , NOTE, NOTE, 'reindexing... [files 10/20]');
  TextsAre('S9 heartbeat, no note'               , Idx , ''  , '', 'Reindex drag-lint  [files 10/20]');
end;

procedure TestLayout;
var
  L: TDLStripLayout;
  W: Integer;
  Ok: Boolean;
begin
  L:= DLStripLayout(1000, 200, 150, True);
  Check('L1 wide: note, progress, depth and bar all at full width',
    (L.NoteWidth = 200) and (L.ProgressWidth = 150) and (L.DepthWidth = 80) and (L.BarWidth = 150),
    Format('%d %d %d %d', [L.NoteWidth, L.ProgressWidth, L.DepthWidth, L.BarWidth]));
  Check('L2 the progress is NEXT TO the note', L.ProgressLeft = L.NoteLeft + L.NoteWidth + 10, IntToStr(L.ProgressLeft));
  L:= DLStripLayout(500, 400, 150, False);
  Check('L3 narrower: the note is cut first, the progress and the bar are whole',
    (L.NoteWidth > 0) and (L.NoteWidth < 400) and (L.ProgressWidth = 150) and (L.BarWidth = 150),
    Format('%d %d %d', [L.NoteWidth, L.ProgressWidth, L.BarWidth]));
  L:= DLStripLayout(260, 400, 150, True);
  Check('L4 narrow: no note, no bar, the progress text is whole', (L.NoteWidth = 0) and (L.ProgressWidth = 150),
    Format('%d %d %d', [L.NoteWidth, L.ProgressWidth, L.BarWidth]));
  Ok:= True;
  for W:= 100 to 1200 do
  begin
    L:= DLStripLayout(W, 300, 120, True);
    { whatever is shown, nothing overlaps and the progress is there }
    if (L.ProgressWidth <= 0) or (L.ProgressLeft + L.ProgressWidth > L.CancelLeft) then Ok:= False;
    if (L.NoteWidth < 300) and (L.NoteWidth > 0) and (L.ProgressWidth < 120) then Ok:= False;
    if (L.DepthWidth > 0) and (L.ProgressLeft + L.ProgressWidth > L.DepthLeft) then Ok:= False;
    if (L.BarWidth > 0) and (L.DepthWidth > 0) and (L.DepthLeft + L.DepthWidth > L.BarLeft) then Ok:= False;
    if not Ok then Break;
  end;
  Check('L5 100..1200 px: progress always shown, never covered, whole while a cut note is shown', Ok, 'W=' + IntToStr(W));
  L:= DLStripLayout(600, 300, 0, False);
  Check('L6 idle: no progress, no bar, the note whole', (L.ProgressWidth = 0) and (L.BarWidth = 0) and (L.NoteWidth = 300),
    Format('%d %d %d', [L.ProgressWidth, L.BarWidth, L.NoteWidth]));
end;

begin
  TestTokens;
  TestNotes;
  TestColumns;
  TestMemo;
  TestStripTexts;
  TestLayout;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then ExitCode:= 1;
end.
