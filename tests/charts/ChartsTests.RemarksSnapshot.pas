unit ChartsTests.RemarksSnapshot;

(* Cases for DRagLint.Charts.Remarks and DRagLint.Charts.Snapshot (spec S1a-S1c, F1,
  F2, S3b): finding and replacing ONE remarks block without touching a byte outside it,
  and the snapshot folder, its names and the 20-per-routine auto retention.

  Fixtures live in tests\charts\fixtures\remarks (TwoBlocks.pas: block 1 is lines 9-15,
  block 2 is lines 18-24, both indented two spaces; NoTrailingNewline.pas: the block is
  lines 6-12 and the file ends without a line end; NotAReport.pas: a remarks block with no
  header sentence). Every test that writes works in its own temp folder, removed in
  TearDown. The UTF-8-with-BOM unit is written by the test itself so the repo stays ASCII.

  PS trap handled: file names and stamps compare ordinally here; PowerShell's -eq and
  Sort-Object on strings are case-insensitive / culture-aware, so no test relies on them. *)

interface

uses
  System.SysUtils, DUnitX.TestFramework;

type
  [TestFixture]
  TRemarksSnapshotTests = class
  private
    FTemp: string;
    procedure CheckMiddleReplace(pEnc: TEncoding; const pEol: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure FindsTheBlockAroundTheCaretOnly;
    [Test] procedure RefusesALineOutsideABlock;
    [Test] procedure RefusesABlockThatIsNotAReport;
    [Test] procedure ReplaceKeepsIndentAndOtherBlocks;
    [Test] procedure LastBlockWithoutTrailingNewline;
    [Test] procedure Utf8BomIsPreservedByteForByte;
    [Test] procedure AnsiHighByteOutsideBlockIsUntouched;
    [Test] procedure Utf8WithoutBomIsKeptWithoutBom;
    [Test] procedure LfOnlyFileStaysLfOnly;
    [Test] procedure NegativeKeepDoesNotRaiseAndZeroRemovesAll;
    [Test] procedure SaveOlderThanTheNewestTwentyReturnsFalse;
    [Test] procedure SnapshotNameMatchesF2;
    [Test] procedure ReportsDirKeyOverridesDefault;
    [Test] procedure DefaultIsProjectFolderDragLintReports;
    [Test] procedure AutoKeepsTwentyOldestRemovedFirst;
    [Test] procedure LatestAutoPicksNewestStamp;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.DateUtils,
  DRagLint.Charts.ReportHeader, DRagLint.Charts.Remarks, DRagLint.Charts.Snapshot;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  FIXTURE_DIR = 'tests\charts\fixtures';
  FIXTURE_PROBE = 'remarks\TwoBlocks.pas';
  CRLF = #13#10;
  NEW_BLOCK = '/// <remarks>' + CRLF + '/// Replaced sentence line.' + CRLF + '/// </remarks>' + CRLF;
  BLOCK2_START = 18;
  BLOCK2_END = 24;
  BLOCK2_CARET = 20;
  LINE_OUTSIDE = 16;
  LINE_BETWEEN = 17;
  LINE_PAST_END = 999;
  LAST_START = 6;
  LAST_END = 12;
  NOT_REPORT_CARET = 7;
  KEEP_TWENTY = 20;
  FILES_BEFORE = 22;
  DAY_MINUTES = 1440;
  EACUTE = #$E9;
  CODEPAGE_ANSI = 1252;
  LF = #10;
  SINGLE_FILE = 1;
  NEGATIVE_KEEP = -SINGLE_FILE;
  AFTERNOON_STAMP = '2026-10-10T14:32:00';
  MORNING_STAMP = '2026-10-10T09:05:00';
  BASE_STAMP = '2026-10-01T00:00:00';
  BOM_FIRST_BYTE = $EF;
  FIRST_KEPT = 3;
  NEWER = 5;
  OTHER_TARGET_NEWEST = 9;

{ The fixture folder: $DRAGLINT_REPO_ROOT, else the first ancestor of the current
  directory that holds it (the Adapters convention). '' when not found. }
function FixtureDir: string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(TPath.Combine(Root, FIXTURE_DIR), FIXTURE_PROBE)) then
    Exit(TPath.Combine(Root, FIXTURE_DIR));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(TPath.Combine(Dir, FIXTURE_DIR), FIXTURE_PROBE)) then
      Exit(TPath.Combine(Dir, FIXTURE_DIR));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function Fixture(const pName: string): string;
begin
  Result:= TPath.Combine(TPath.Combine(FixtureDir, 'remarks'), pName);
  Assert.IsTrue(TFile.Exists(Result), 'fixture missing: ' + Result);
end;

function BytesEqual(const pA, pB: TBytes): Boolean;
begin
  Result:= (Length(pA) = Length(pB)) and ((Length(pA) = 0) or CompareMem(@pA[0], @pB[0], Length(pA)));
end;

procedure TRemarksSnapshotTests.Setup;
begin
  FTemp:= TPath.Combine(TPath.GetTempPath, 'drag-lint-charts-rs-' + TGUID.NewGuid.ToString);
  ForceDirectories(FTemp);
end;

procedure TRemarksSnapshotTests.TearDown;
begin
  if (FTemp <> '') and TDirectory.Exists(FTemp) then
    TDirectory.Delete(FTemp, True);
end;

procedure TRemarksSnapshotTests.FindsTheBlockAroundTheCaretOnly;
begin
  var Lines:= TFile.ReadAllLines(Fixture('TwoBlocks.pas'));
  var Block: TRemarksBlock;
  var Why: string;
  Assert.IsTrue(FindRemarksBlockAt(Lines, BLOCK2_CARET, Block, Why), Why);
  Assert.AreEqual(BLOCK2_START, Block.StartLine);
  Assert.AreEqual(BLOCK2_END, Block.EndLine);
  Assert.AreEqual('  ', Block.Indent);
  Assert.AreEqual(BLOCK2_END - BLOCK2_START + 1, Integer(Length(Block.Lines)));
  Assert.IsTrue(Block.Lines[1].Contains('who-calls'), 'block 2, not block 1');
  Assert.IsFalse(Block.Lines[1].Contains('who-writes'));
  // The tags themselves lie inside their own block.
  Assert.IsTrue(FindRemarksBlockAt(Lines, BLOCK2_START, Block, Why), Why);
  Assert.AreEqual(BLOCK2_END, Block.EndLine);
  Assert.IsTrue(FindRemarksBlockAt(Lines, BLOCK2_END, Block, Why), Why);
  Assert.AreEqual(BLOCK2_START, Block.StartLine);
end;

procedure TRemarksSnapshotTests.RefusesALineOutsideABlock;
begin
  var Lines:= TFile.ReadAllLines(Fixture('TwoBlocks.pas'));
  var Block: TRemarksBlock;
  var Why: string;
  Assert.IsFalse(FindRemarksBlockAt(Lines, LINE_OUTSIDE, Block, Why));
  Assert.AreEqual('line 16 is not inside a /// <remarks> block', Why);
  // A '///' line between two blocks (block 2's summary) is outside both.
  Assert.IsFalse(FindRemarksBlockAt(Lines, LINE_BETWEEN, Block, Why));
  Assert.AreEqual('line 17 is not inside a /// <remarks> block', Why);
  Assert.IsFalse(FindRemarksBlockAt(Lines, LINE_PAST_END, Block, Why));
  Assert.AreEqual('line 999 is not inside a /// <remarks> block', Why);
  Assert.IsFalse(FindRemarksBlockAt(Lines, 0, Block, Why));
end;

procedure TRemarksSnapshotTests.RefusesABlockThatIsNotAReport;
begin
  var Block: TRemarksBlock;
  var Why: string;
  var Header: TReportHeader;
  // S1b: the block is found, but it does not hold a drag-lint report.
  Assert.IsTrue(FindRemarksBlockAt(TFile.ReadAllLines(Fixture('NotAReport.pas')), NOT_REPORT_CARET, Block, Why), Why);
  Assert.IsFalse(RemarksBlockIsReport(Block, Header));
  // ... and a real report block is accepted.
  Assert.IsTrue(FindRemarksBlockAt(TFile.ReadAllLines(Fixture('TwoBlocks.pas')), BLOCK2_CARET, Block, Why), Why);
  Assert.IsTrue(RemarksBlockIsReport(Block, Header));
  Assert.AreEqual('who-calls', Header.QuestionId);
  Assert.AreEqual('TFoo.Two', Header.Target);
end;

procedure TRemarksSnapshotTests.ReplaceKeepsIndentAndOtherBlocks;
begin
  var Path:= TPath.Combine(FTemp, 'TwoBlocks.pas');
  TFile.Copy(Fixture('TwoBlocks.pas'), Path);
  var Lines:= TFile.ReadAllLines(Path);
  var Block: TRemarksBlock;
  var Why: string;
  Assert.IsTrue(FindRemarksBlockAt(Lines, BLOCK2_CARET, Block, Why), Why);
  Assert.IsTrue(ReplaceRemarksBlockInFile(Path, Block, NEW_BLOCK, Why), Why);

  var Expected:= '';
  for var I:= 1 to Length(Lines) do
  begin
    if I = BLOCK2_START then
      Expected:= Expected + '  /// <remarks>' + CRLF + '  /// Replaced sentence line.' + CRLF
        + '  /// </remarks>' + CRLF
    else if (I < BLOCK2_START) or (I > BLOCK2_END) then
      Expected:= Expected + Lines[I - 1] + CRLF;
  end;
  Assert.AreEqual(Expected, TFile.ReadAllText(Path, TEncoding.ANSI), 'only the caret block changes');
end;

procedure TRemarksSnapshotTests.LastBlockWithoutTrailingNewline;
begin
  var Path:= TPath.Combine(FTemp, 'NoTrailingNewline.pas');
  TFile.Copy(Fixture('NoTrailingNewline.pas'), Path);
  var Original:= TFile.ReadAllBytes(Path);
  Assert.IsTrue(Original[High(Original)] <> Ord(#10), 'fixture has no final line end');
  var Block: TRemarksBlock;
  var Why: string;
  Assert.IsTrue(FindRemarksBlockAt(TFile.ReadAllLines(Path), LAST_START + 1, Block, Why), Why);
  Assert.AreEqual(LAST_START, Block.StartLine);
  Assert.AreEqual(LAST_END, Block.EndLine);
  Assert.IsTrue(ReplaceRemarksBlockInFile(Path, Block, NEW_BLOCK, Why), Why);

  var Prefix:= '';
  var Lines:= TFile.ReadAllLines(Fixture('NoTrailingNewline.pas'));
  for var I:= 1 to LAST_START - 1 do
    Prefix:= Prefix + Lines[I - 1] + CRLF;
  var Expected:= Prefix + '/// <remarks>' + CRLF + '/// Replaced sentence line.' + CRLF + '/// </remarks>';
  Assert.AreEqual(Expected, TFile.ReadAllText(Path, TEncoding.ANSI), 'no newline appended');
end;

procedure TRemarksSnapshotTests.Utf8BomIsPreservedByteForByte;
begin
  var Path:= TPath.Combine(FTemp, 'Utf8Bom.pas');
  var Text:= TFile.ReadAllText(Fixture('TwoBlocks.pas'), TEncoding.ANSI);
  Text:= StringReplace(Text, 'procedure One;', 'const S = ''caf' + EACUTE + ''';', []);
  var Enc:= TUTF8Encoding.Create(True);
  try
    TFile.WriteAllText(Path, Text, Enc);
    var Block: TRemarksBlock;
    var Why: string;
    Assert.IsTrue(FindRemarksBlockAt(TFile.ReadAllLines(Path, Enc), BLOCK2_CARET, Block, Why), Why);
    Assert.IsTrue(ReplaceRemarksBlockInFile(Path, Block, NEW_BLOCK, Why), Why);

    var Expected:= '';
    var Orig:= Text.Split([CRLF]);
    for var I:= 1 to Length(Orig) - 1 do
    begin
      if I = BLOCK2_START then
        Expected:= Expected + '  /// <remarks>' + CRLF + '  /// Replaced sentence line.' + CRLF
          + '  /// </remarks>' + CRLF
      else if (I < BLOCK2_START) or (I > BLOCK2_END) then
        Expected:= Expected + Orig[I - 1] + CRLF;
    end;
    var Want:= Enc.GetPreamble + Enc.GetBytes(Expected);
    Assert.IsTrue(BytesEqual(Want, TFile.ReadAllBytes(Path)), 'BOM, e-acute and every other byte kept');
  finally
    Enc.Free;
  end;
end;

{ Builds TwoBlocks.pas in pEnc with pEol line ends and an e-acute OUTSIDE the block, replaces
  block 2 (the middle of the file) and requires every byte outside it to be identical. }
procedure TRemarksSnapshotTests.CheckMiddleReplace(pEnc: TEncoding; const pEol: string);
begin
  var Path:= TPath.Combine(FTemp, 'Middle.pas');
  var Lines:= TFile.ReadAllLines(Fixture('TwoBlocks.pas'));
  Lines[LINE_OUTSIDE - 1]:= 'const S = ''caf' + EACUTE + ''';';
  var Orig:= '';
  var Expected:= '';
  for var I:= 1 to Length(Lines) do
  begin
    Orig:= Orig + Lines[I - 1] + pEol;
    if I = BLOCK2_START then
      Expected:= Expected + '  /// <remarks>' + pEol + '  /// Replaced sentence line.' + pEol
        + '  /// </remarks>' + pEol
    else if (I < BLOCK2_START) or (I > BLOCK2_END) then
      Expected:= Expected + Lines[I - 1] + pEol;
  end;
  TFile.WriteAllBytes(Path, pEnc.GetPreamble + pEnc.GetBytes(Orig));
  var Block: TRemarksBlock;
  var Why: string;
  Assert.IsTrue(FindRemarksBlockAt(TFile.ReadAllLines(Path, pEnc), BLOCK2_CARET, Block, Why), Why);
  Assert.IsTrue(ReplaceRemarksBlockInFile(Path, Block, NEW_BLOCK, Why), Why);
  Assert.IsTrue(BytesEqual(pEnc.GetPreamble + pEnc.GetBytes(Expected), TFile.ReadAllBytes(Path)),
    'every byte outside the block is identical');
  Assert.IsFalse(TFile.Exists(Path + '.tmp'), 'temp file is gone');
end;

procedure TRemarksSnapshotTests.AnsiHighByteOutsideBlockIsUntouched;
begin
  // A lone $E9 is invalid UTF-8: the strict decode must refuse it so the file stays ANSI.
  var Enc:= TEncoding.GetEncoding(CODEPAGE_ANSI);
  try
    CheckMiddleReplace(Enc, CRLF);
  finally
    Enc.Free;
  end;
end;

procedure TRemarksSnapshotTests.Utf8WithoutBomIsKeptWithoutBom;
begin
  var Enc:= TUTF8Encoding.Create(False);
  try
    CheckMiddleReplace(Enc, CRLF);
  finally
    Enc.Free;
  end;
  Assert.IsTrue(TFile.ReadAllBytes(TPath.Combine(FTemp, 'Middle.pas'))[0] <> BOM_FIRST_BYTE, 'still no BOM');
end;

procedure TRemarksSnapshotTests.LfOnlyFileStaysLfOnly;
begin
  CheckMiddleReplace(TEncoding.ASCII, LF);
  Assert.IsFalse(TFile.ReadAllText(TPath.Combine(FTemp, 'Middle.pas')).Contains(#13), 'no CR introduced');
end;

procedure TRemarksSnapshotTests.NegativeKeepDoesNotRaiseAndZeroRemovesAll;
begin
  var Auto:= TPath.Combine(FTemp, 'auto');
  ForceDirectories(Auto);
  var Name:= TPath.Combine(Auto, SnapshotFileName('who-writes', 'T', ISO8601ToDate(BASE_STAMP)));
  TFile.WriteAllText(Name, 'x');
  PruneAutoSnapshots(Auto, 'who-writes', 'T', NEGATIVE_KEEP);
  Assert.IsFalse(TFile.Exists(Name), 'negative keep behaves as 0');
  TFile.WriteAllText(Name, 'x');
  PruneAutoSnapshots(Auto, 'who-writes', 'T', 0);
  Assert.IsFalse(TFile.Exists(Name), '0 removes all');
end;

procedure TRemarksSnapshotTests.SaveOlderThanTheNewestTwentyReturnsFalse;
begin
  var Auto:= TPath.Combine(FTemp, 'auto');
  ForceDirectories(Auto);
  var Base:= ISO8601ToDate(BASE_STAMP);
  for var I:= 1 to KEEP_TWENTY do
    TFile.WriteAllText(TPath.Combine(Auto, SnapshotFileName('who-writes', 'T', Base + I / DAY_MINUTES)), 'x');
  var Path: string;
  Assert.IsFalse(SaveSnapshot(FTemp, True, 'who-writes', 'T', 'old', Base, Path), 'retention removed it');
  Assert.AreEqual('', Path);
  Assert.AreEqual(KEEP_TWENTY, Integer(Length(TDirectory.GetFiles(Auto, '*.txt'))));
  // A newer one still succeeds and its path exists.
  Assert.IsTrue(SaveSnapshot(FTemp, True, 'who-writes', 'T', 'new', Base + SINGLE_FILE, Path));
  Assert.IsTrue(TFile.Exists(Path));
end;

procedure TRemarksSnapshotTests.SnapshotNameMatchesF2;
begin
  var When:= ISO8601ToDate(AFTERNOON_STAMP);
  Assert.AreEqual('who-writes--OPERAT.NAME--20261010-1432.txt', SnapshotFileName('who-writes', 'OPERAT.NAME', When));
  Assert.AreEqual('A_-__B', SanitiseTargetForFileName('A -> B'));
  Assert.AreEqual('TFoo.Bar_Baz', SanitiseTargetForFileName('TFoo.Bar<Baz'));
  Assert.AreEqual('path--A_-__B--20261010-0905.txt',
    SnapshotFileName('path', 'A -> B', ISO8601ToDate(MORNING_STAMP)));
end;

procedure TRemarksSnapshotTests.ReportsDirKeyOverridesDefault;
begin
  var Proj:= TPath.Combine(FTemp, 'proj');
  var Home:= TPath.Combine(Proj, '_D-RAG');
  ForceDirectories(Home);
  var Db:= TPath.Combine(Home, 'A.sqlite');
  var Json:= TPath.Combine(Home, 'drag-lint-project.json');
  TFile.WriteAllText(Json, '{ "reportsDir": "..\\reports" }', TEncoding.ASCII);
  // Relative: resolved against the _D-RAG folder, like ownRoots.
  Assert.AreEqual(TPath.Combine(Proj, 'reports'), ResolveSnapshotDir(TPath.Combine(Proj, 'A.dproj'), Db));
  // The same answer when only the project file names the anchor.
  Assert.AreEqual(TPath.Combine(Proj, 'reports'), ResolveSnapshotDir(TPath.Combine(Proj, 'A.dproj'), ''));
  // Absolute: used as is.
  var Abs:= TPath.Combine(FTemp, 'elsewhere');
  TFile.WriteAllText(Json, '{ "reportsDir": "' + StringReplace(Abs, '\', '\\', [rfReplaceAll]) + '" }', TEncoding.ASCII);
  Assert.AreEqual(Abs, ResolveSnapshotDir(TPath.Combine(Proj, 'A.dproj'), Db));
  // A malformed declaration falls back to the default rather than raising.
  TFile.WriteAllText(Json, '{ "reportsDir": ', TEncoding.ASCII);
  Assert.AreEqual(TPath.Combine(Proj, 'drag-lint-reports'), ResolveSnapshotDir(TPath.Combine(Proj, 'A.dproj'), Db));
end;

procedure TRemarksSnapshotTests.DefaultIsProjectFolderDragLintReports;
begin
  var Proj:= TPath.Combine(FTemp, 'proj');
  ForceDirectories(Proj);
  Assert.AreEqual(TPath.Combine(Proj, 'drag-lint-reports'), ResolveSnapshotDir(TPath.Combine(Proj, 'A.dproj'), ''));
  // A _D-RAG folder with no reportsDir key changes nothing.
  ForceDirectories(TPath.Combine(Proj, '_D-RAG'));
  TFile.WriteAllText(TPath.Combine(TPath.Combine(Proj, '_D-RAG'), 'drag-lint-project.json'),
    '{ "ownRoots": ["."] }', TEncoding.ASCII);
  Assert.AreEqual(TPath.Combine(Proj, 'drag-lint-reports'),
    ResolveSnapshotDir(TPath.Combine(Proj, 'A.dproj'), TPath.Combine(TPath.Combine(Proj, '_D-RAG'), 'A.sqlite')));
end;

procedure TRemarksSnapshotTests.AutoKeepsTwentyOldestRemovedFirst;
begin
  var Auto:= TPath.Combine(FTemp, 'auto');
  ForceDirectories(Auto);
  var Base:= ISO8601ToDate(BASE_STAMP);
  for var I:= 0 to FILES_BEFORE - 1 do
    TFile.WriteAllText(TPath.Combine(Auto, SnapshotFileName('who-writes', 'OPERAT.NAME', Base + I / DAY_MINUTES)), 'x');
  // Look-alikes that share the prefix or the target but are not this routine's snapshots.
  var Decoy1:= TPath.Combine(Auto, 'who-writes--OPERAT.NAME--B--20260101-0000.txt');
  var Decoy2:= TPath.Combine(Auto, SnapshotFileName('who-calls', 'OPERAT.NAME', Base));
  TFile.WriteAllText(Decoy1, 'x');
  TFile.WriteAllText(Decoy2, 'x');

  // The 23rd goes through SaveSnapshot(auto), which prunes.
  var Path: string;
  var Newest:= Base + FILES_BEFORE / DAY_MINUTES;
  Assert.IsTrue(SaveSnapshot(FTemp, True, 'who-writes', 'OPERAT.NAME', 'line1' + #10 + 'line2', Newest, Path));
  Assert.AreEqual(TPath.Combine(Auto, SnapshotFileName('who-writes', 'OPERAT.NAME', Newest)), Path);
  Assert.AreEqual('line1' + CRLF + 'line2', TFile.ReadAllText(Path, TEncoding.UTF8), 'CRLF');
  Assert.IsFalse(TFile.ReadAllBytes(Path)[0] = BOM_FIRST_BYTE, 'no BOM');

  var Left:= TDirectory.GetFiles(Auto, 'who-writes--OPERAT.NAME--2*.txt');
  Assert.AreEqual(KEEP_TWENTY, Integer(Length(Left)));
  for var I:= 0 to 2 do
    Assert.IsFalse(TFile.Exists(TPath.Combine(Auto, SnapshotFileName('who-writes', 'OPERAT.NAME', Base + I / DAY_MINUTES))),
      'oldest removed first: ' + IntToStr(I));
  Assert.IsTrue(TFile.Exists(TPath.Combine(Auto, SnapshotFileName('who-writes', 'OPERAT.NAME', Base + FIRST_KEPT / DAY_MINUTES))));
  Assert.IsTrue(TFile.Exists(Decoy1), 'a longer target sharing the prefix is not pruned');
  Assert.IsTrue(TFile.Exists(Decoy2), 'another question is not pruned');
end;

procedure TRemarksSnapshotTests.LatestAutoPicksNewestStamp;
begin
  var Auto:= TPath.Combine(FTemp, 'auto');
  Assert.AreEqual('', LatestAutoSnapshotAnyFormat(Auto, 'who-writes', 'OPERAT.NAME'), 'no folder, none');
  ForceDirectories(Auto);
  Assert.AreEqual('', LatestAutoSnapshotAnyFormat(Auto, 'who-writes', 'OPERAT.NAME'), 'empty folder, none');
  var Base:= ISO8601ToDate(BASE_STAMP);
  // Written newest-first, so file time order is the opposite of stamp order.
  var Newest:= TPath.Combine(Auto, SnapshotFileName('who-writes', 'OPERAT.NAME', Base + NEWER / DAY_MINUTES));
  TFile.WriteAllText(Newest, 'x');
  TFile.WriteAllText(TPath.Combine(Auto, SnapshotFileName('who-writes', 'OPERAT.NAME', Base)), 'x');
  TFile.WriteAllText(TPath.Combine(Auto, SnapshotFileName('who-writes', 'OTHER', Base + OTHER_TARGET_NEWEST / DAY_MINUTES)), 'x');
  Assert.AreEqual(Newest, LatestAutoSnapshotAnyFormat(Auto, 'who-writes', 'OPERAT.NAME'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRemarksSnapshotTests);

end.
