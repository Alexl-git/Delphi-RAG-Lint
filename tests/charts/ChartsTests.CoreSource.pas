unit ChartsTests.CoreSource;

{ Cases for DRagLint.Charts.Source, the freshness-gated source reader ported from
  charts\src\Emit-Common.ps1 (Get-IndexedFileShas, Test-SourceFresh,
  Get-StrippedSourceLines, Get-SourceContext). The stripping and context cases
  read the fixture tests\charts\fixtures\source\Sample.pas and need no index; the
  freshness cases run against the FROZEN clone charts\scratch\db\DL-drag-lint.sqlite
  -- never a live index -- and pass with 'clone missing' when it is absent. }

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.Index, DRagLint.Charts.Source;

type
  [TestFixture]
  TCoreSourceTests = class
  private
    FIndex : TChartsIndex;
    FReader: TSourceReader;
    FTemp  : string;
    function OpenClone: Boolean;
    function SampleLines: TArray<string>;
  public
    [TearDown] procedure TearDown;
    [Test] procedure StrippingKeepsLineAndColumnGeometry;
    [Test] procedure StringsCommentsDirectivesBecomeSpaces;
    [Test] procedure ContextSplitsBeforeTokenAfter;
    [Test] procedure PrevLineSkipsBlanks;
    [Test] procedure StaleFileGivesStaleResultNotText;
    [Test] procedure FreshFileMatchesIndexSha;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Hash, System.Generics.Collections;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLONE_REL = 'charts\scratch\db\DL-drag-lint.sqlite';
  SAMPLE_REL = 'tests\charts\fixtures\source\Sample.pas';
  { Sample.pas: 25 lines and a final CRLF, which -split "\r?\n" turns into a 26th, empty element }
  SAMPLE_COUNT = 26;
  LINE_IMPLEMENTATION = 7;
  LINE_IFDEF = 9;
  LINE_CONST = 10;
  LINE_BRACE_STRING = 17;
  LINE_COMMENT_OPEN = 18;
  LINE_COMMENT_CLOSE = 19;
  LINE_WRITELN = 22;
  LINE_END = 23;
  { the second Writeln on line 22: 1-based column and length (end_col - start_col) }
  WRITELN_COL = 28;
  WRITELN_LEN = 7;
  // '  Writeln(S);' then the 14 blanked columns of the trailing brace comment and its spaces
  WRITELN_GAP = 14;
  { '     spans two lines *) ' -- 23 comment columns and the space after them }
  CLOSE_LEAD = 24;
  { the blanked 'it''s' (7 columns) and the space before it }
  ITS_GAP = 8;
  { the blanked 'debug' (7 columns) and the space before it }
  DEBUG_GAP = 8;
  // the blanked '{' (3 columns) and the space before it
  BRACE_GAP = 4;
  { the blanked '//' (4 columns) }
  SLASH_GAP = 4;
  { the blanked ' trailing ' comment (12 columns) and the spaces on both sides }
  TRAILING_GAP = 14;
  NO_SUCH_LINE = 99;
  { a ref placed on 'a' inside the open comment of line 18 }
  COMMENT_COL = 6;
  COMMENT_LEN = 1;

function FindUp(const pRel: string): string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, pRel)) then
    Exit(TPath.Combine(Root, pRel));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, pRel)) then
      Exit(TPath.Combine(Dir, pRel));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

{ The message of the EChartsIndex pAction raises; '' when it raises nothing. }
function RaisedMessage(const pAction: TProc): string;
begin
  Result:= '';
  try
    pAction;
  except
    on E: EChartsIndex do Result:= E.Message;
  end;
end;

function TCoreSourceTests.OpenClone: Boolean;
begin
  var Clone:= FindUp(CLONE_REL);
  Result:= Clone <> '';
  if not Result then
  begin
    Assert.Pass('clone missing');
    Exit;
  end;
  FIndex:= TChartsIndex.Create(Clone);
  FReader:= TSourceReader.Create(FIndex);
end;

function TCoreSourceTests.SampleLines: TArray<string>;
begin
  var Sample:= FindUp(SAMPLE_REL);
  Assert.IsTrue(Sample <> '', SAMPLE_REL + ' not found from ' + GetCurrentDir);
  if FReader = nil then
    FReader:= TSourceReader.Create(nil);
  Result:= FReader.StrippedSourceLines(Sample);
end;

procedure TCoreSourceTests.TearDown;
begin
  FreeAndNil(FReader);
  FreeAndNil(FIndex);
  if FTemp <> '' then
    DeleteFile(FTemp);
  FTemp:= '';
end;

procedure TCoreSourceTests.StrippingKeepsLineAndColumnGeometry;
begin
  var Stripped:= SampleLines;
  var Raw:= TFile.ReadAllText(FindUp(SAMPLE_REL), TEncoding.ASCII).Replace(#13#10, #10).Split([#10]);
  Assert.AreEqual(SAMPLE_COUNT, Integer(Length(Stripped)));
  Assert.AreEqual(Integer(Length(Raw)), Integer(Length(Stripped)));
  for var K:= 0 to High(Raw) do
    Assert.AreEqual(Length(Raw[K]), Length(Stripped[K]), 'line ' + IntToStr(K + 1));
  Assert.AreEqual('', Stripped[SAMPLE_COUNT - 1]);
  { cached per read path: the second call answers the same lines }
  Assert.AreEqual(Stripped[LINE_WRITELN - 1], SampleLines[LINE_WRITELN - 1]);
end;

procedure TCoreSourceTests.StringsCommentsDirectivesBecomeSpaces;
begin
  var L:= SampleLines;
  // the IFDEF directive is blanked, not evaluated
  Assert.AreEqual('', Trim(L[LINE_IFDEF - 1]));
  Assert.AreEqual('const Mode =' + StringOfChar(' ', DEBUG_GAP) + ';', L[LINE_CONST - 1]);
  { '{' is a string (leftmost match wins), so the // comment after it is still a comment }
  Assert.AreEqual('  S:=' + StringOfChar(' ', BRACE_GAP) + ';', TrimRight(L[LINE_BRACE_STRING - 1]));
  { the two-line (* *) blanks only non-newline characters: both lines survive, blank where it covered }
  Assert.AreEqual('', Trim(L[LINE_COMMENT_OPEN - 1]));
  Assert.AreEqual(StringOfChar(' ', CLOSE_LEAD) + 'S:= S +' + StringOfChar(' ', ITS_GAP) + ';',
    L[LINE_COMMENT_CLOSE - 1]);
  Assert.AreEqual('  Writeln(S);' + StringOfChar(' ', TRAILING_GAP) + 'Writeln(' + StringOfChar(' ', SLASH_GAP) + ');',
    L[LINE_WRITELN - 1]);
end;

procedure TCoreSourceTests.ContextSplitsBeforeTokenAfter;
begin
  var C:= TSourceReader.ContextOfLines('X.pas', SampleLines, LINE_WRITELN, WRITELN_COL, WRITELN_LEN, 1);
  Assert.AreEqual('X.pas', C.Path);
  Assert.AreEqual(LINE_WRITELN, C.Line);
  Assert.IsFalse(C.Stale);
  Assert.AreEqual('  Writeln(S);' + StringOfChar(' ', WRITELN_GAP), C.Before);
  Assert.AreEqual('Writeln', C.Token);
  Assert.AreEqual('(' + StringOfChar(' ', SLASH_GAP) + ');', C.After);
  Assert.AreEqual(1, Integer(Length(C.Following)));
  Assert.AreEqual('end;', C.Following[0]);
  { columns clamp to the line, as [Math]::Min/Max did: column 0 and a negative length give an empty token }
  var Clamped:= TSourceReader.ContextOfLines('X.pas', SampleLines, LINE_END, 0, -1);
  Assert.AreEqual('', Clamped.Before);
  Assert.AreEqual('', Clamped.Token);
  Assert.AreEqual('end;', Clamped.After);
  Assert.AreEqual(0, Integer(Length(Clamped.Following)));
  { a ref inside a comment reads a blank token }
  Assert.AreEqual('', Trim(TSourceReader.ContextOfLines('X.pas', SampleLines, LINE_COMMENT_OPEN, COMMENT_COL, COMMENT_LEN).Token));
  Assert.AreEqual('Get-SourceContext: line 99 is outside X.pas (26 lines) although the file is fresh',
    RaisedMessage(procedure begin TSourceReader.ContextOfLines('X.pas', SampleLines, NO_SUCH_LINE, 1, 1); end));
end;

procedure TCoreSourceTests.PrevLineSkipsBlanks;
begin
  var L:= SampleLines;
  { lines 20-21 are empty: the previous non-blank line is 19, trimmed }
  var C:= TSourceReader.ContextOfLines('X.pas', L, LINE_WRITELN, 1, 1);
  Assert.AreEqual(LINE_COMMENT_CLOSE, C.PrevLineNo);
  Assert.AreEqual('S:= S +' + StringOfChar(' ', ITS_GAP) + ';', C.PrevLine);
  { line 18 is all comment once stripped, so it is blank too }
  C:= TSourceReader.ContextOfLines('X.pas', L, LINE_COMMENT_CLOSE, 1, 1);
  Assert.AreEqual(LINE_BRACE_STRING, C.PrevLineNo);
  Assert.AreEqual('S:=' + StringOfChar(' ', BRACE_GAP) + ';', C.PrevLine);
  { a blanked directive is blank: line 10's previous is 'implementation' on line 7 }
  C:= TSourceReader.ContextOfLines('X.pas', L, LINE_CONST, 1, 1);
  Assert.AreEqual(LINE_IMPLEMENTATION, C.PrevLineNo);
  Assert.AreEqual('implementation', C.PrevLine);
  C:= TSourceReader.ContextOfLines('X.pas', L, 1, 1, 1);
  Assert.AreEqual(0, C.PrevLineNo);
  Assert.AreEqual('', C.PrevLine);
end;

procedure TCoreSourceTests.StaleFileGivesStaleResultNotText;
begin
  if not OpenClone then Exit;
  var Rows:= FIndex.Query('SELECT path FROM files ORDER BY id LIMIT 1');
  try
    var Indexed:= Rows[0].S('path');
    { a modified copy: the override target cannot hash to the indexed sha }
    FTemp:= TPath.Combine(TPath.GetTempPath, 'charts-stale-' + IntToStr(TThread.CurrentThread.ThreadID) + '.pas');
    TFile.WriteAllText(FTemp, 'unit Changed;' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    { -SourceOverride keys match case-insensitively }
    FReader.AddOverride(UpperCase(Indexed), FTemp);
    Assert.IsFalse(FReader.SourceFresh(Indexed));
    var C:= FReader.SourceContext(Indexed, 1, 1, 1, 1);
    Assert.IsTrue(C.Stale);
    Assert.AreEqual(Indexed, C.Path);
    Assert.AreEqual(1, C.Line);
    Assert.AreEqual('', C.Token);
    Assert.AreEqual('', C.Before);
    Assert.AreEqual('', C.After);
    Assert.AreEqual('', C.PrevLine);
    Assert.AreEqual(0, C.PrevLineNo);
    Assert.AreEqual(0, Integer(Length(C.Following)));
  finally
    Rows.Free;
  end;
  { a path the index does not hold is a caller bug, not a staleness verdict }
  Assert.StartsWith('Test-SourceFresh: No\Such\File.pas is not a file of this index (',
    RaisedMessage(procedure begin FReader.SourceFresh('No\Such\File.pas'); end));
  { the database named is the clone SQLite reports for 'main' (PRAGMA database_list) }
  Assert.EndsWith('DL-drag-lint.sqlite)',
    RaisedMessage(procedure begin FReader.SourceFresh('No.pas'); end));
end;

procedure TCoreSourceTests.FreshFileMatchesIndexSha;
begin
  if not OpenClone then Exit;
  var Rows:= FIndex.Query('SELECT path, sha256 FROM files ORDER BY id');
  try
    Assert.AreEqual(Integer(Rows.Count), Integer(FReader.IndexedFileShas.Count));
    var Fresh:= '';
    for var R in Rows do
      if TFile.Exists(R.S('path')) and SameText(THashSHA2.GetHashStringFromFile(R.S('path')), R.S('sha256')) then
      begin
        Fresh:= R.S('path');
        Break;
      end;
    if Fresh = '' then
    begin
      Assert.Pass('every file of the clone differs from disk');
      Exit;
    end;
    Assert.IsTrue(FReader.SourceFresh(Fresh));
    { the indexed-path keys are case-insensitive, like the PS hashtable }
    Assert.IsTrue(FReader.SourceFresh(LowerCase(Fresh)));
    var C:= FReader.SourceContext(Fresh, 1, 1, 0);
    Assert.IsFalse(C.Stale);
    { an override to a missing file is stale, not an error }
    FReader.AddOverride(Fresh, TPath.Combine(TPath.GetTempPath, 'charts-no-such-file.pas'));
    Assert.IsFalse(FReader.SourceFresh(Fresh));
  finally
    Rows.Free;
  end;
end;

end.
