program ConstGenTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.53 lane FR-CONSTGEN -- console tests for DRagLint.FieldRepo.ConstGen (spec section 7).
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M"; exit 0 only when fail=0.
  Fixtures: tests\fixtures\fieldrepo\ (golden, edge, golden_v2) and constgen\golden_expected.pas.
  `ConstGenTests.exe --emit <fixture> <unit name> <out.pas> [memtable]` writes a generated unit
  (the runner's compile + round-trip proof and the golden regeneration use it). }

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Types,
  System.StrUtils,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.TextBackup in '..\..\src\sql\DRagLint.FieldRepo.TextBackup.pas',
  DRagLint.FieldRepo.ConstGen in '..\..\src\sql\DRagLint.FieldRepo.ConstGen.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
  GFix: string;
  GRepoSeq: Integer = 0;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

procedure CheckEq(const pName, pGot, pWant: string);
begin
  Check(pName, pGot = pWant, 'got [' + pGot + '] want [' + pWant + ']');
end;

function Fixture(const pName: string): string;
begin
  Result := TPath.Combine(GFix, pName);
end;

{ A fresh repository of the given schema version, filled from a backup fixture ('' = empty). }
function RepoFrom(const pFixture: string; pVersion: Integer): TFDConnection;
var
  vPath: string;
begin
  Inc(GRepoSeq);
  vPath := TPath.Combine(GDir, 'r' + IntToStr(GRepoSeq) + '.dlrepo');
  CreateRepository(vPath, pVersion);
  Result := OpenRepository(vPath, False);
  if pFixture <> '' then
    RestoreRepository(Result, Fixture(pFixture), False);
end;

function RaisedClass(pProc: TProc): string;
begin
  Result := '';
  try
    pProc;
  except
    on E: Exception do
      Result := E.ClassName;
  end;
end;

function Opts(const pUnit: string; pMem: Boolean; const pTables: TArray<string> = nil): TConstGenOptions;
begin
  Result := Default(TConstGenOptions);
  Result.UnitName := pUnit;
  Result.SourceName := 'golden';
  Result.MemTable := pMem;
  Result.Tables := pTables;
end;

function ReadAll(const pFile: string): string;
begin
  Result := TFile.ReadAllText(pFile, TEncoding.ASCII);
end;

function MaxLineLen(const pText: string): Integer;
var
  vL: TStringList;
  vI: Integer;
begin
  Result := 0;
  vL := TStringList.Create;
  try
    vL.Text := pText;
    for vI := 0 to vL.Count - 1 do
      if Length(vL[vI]) > Result then
        Result := Length(vL[vI]);
  finally
    vL.Free;
  end;
end;

function IsCleanAscii(const pText: string): Boolean;
var
  vI: Integer;
begin
  Result := True;
  for vI := 1 to Length(pText) do
  begin
    if pText[vI] > #126 then
      Exit(False);
    if (pText[vI] < ' ') and (pText[vI] <> #13) and (pText[vI] <> #10) then
      Exit(False);
    if (pText[vI] = #10) and ((vI = 1) or (pText[vI - 1] <> #13)) then
      Exit(False);
    if (pText[vI] = #13) and ((vI = Length(pText)) or (pText[vI + 1] <> #10)) then
      Exit(False);
  end;
end;

procedure TestLiteral;
var
  vS: string;
  vI, vPieces: Integer;
begin
  CheckEq('1a empty', PasStringLiteral(''), '''''');
  CheckEq('1b plain', PasStringLiteral('abc'), '''abc''');
  CheckEq('1c quote doubled', PasStringLiteral('it''s'), '''it''''s''');
  CheckEq('1d CR', PasStringLiteral('a' + #13 + 'b'), '''a''#13''b''');
  CheckEq('1e LF', PasStringLiteral('a' + #10 + 'b'), '''a''#10''b''');
  CheckEq('1f CRLF', PasStringLiteral('a' + #13#10 + 'b'), '''a''#13#10''b''');
  CheckEq('1g tab', PasStringLiteral(#9), '#9');
  CheckEq('1h 0x7F', PasStringLiteral('x' + #127), '''x''#127');
  CheckEq('1i e-acute', PasStringLiteral(#$E9), '#233');
  CheckEq('1j only a quote', PasStringLiteral(''''), '''''''''');
  vS := StringOfChar('a', 450);
  vPieces := Length(PasStringLiteral(vS).Split([' +' + #13#10]));
  Check('1k 450 chars -> 3 pieces', vPieces = 3, IntToStr(vPieces));
  Check('1l no line over 250 (450 chars)', MaxLineLen(PasStringLiteral(vS)) <= 250);
  vS := '';
  for vI := 1 to 300 do
    vS := vS + #$20AC;
  Check('1m 300 escapes: no line over 250', MaxLineLen(PasStringLiteral(vS)) <= 250);
  vS := '';
  for vI := 1 to 300 do
    vS := vS + 'a''';
  Check('1n 300 quotes: no line over 250', MaxLineLen(PasStringLiteral(vS)) <= 250);
  CheckEq('1o continuation indent', PasStringLiteral(StringOfChar('a', 450), '  ').Split([#13#10])[1].Substring(0, 3), '  ''');
end;

procedure TestOptions;
var
  vC: TFDConnection;
begin
  vC := RepoFrom('golden.dlrepo.txt', 1);
  try
    Check('2a refused DL_META', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', False, ['DL_META'])); end) = 'EConstGenError');
    Check('2b refused DL_EXCEPTIONS', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', False, ['DL_EXCEPTIONS'])); end) = 'EConstGenError');
    Check('2c refused DL_GENERATORS', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', False, ['DL_GENERATORS'])); end) = 'EConstGenError');
    Check('2d unknown table', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', False, ['NOPE'])); end) = 'EConstGenError');
    Check('2e unit not identifier', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('1bad', False)); end) = 'EConstGenError');
    Check('2f unit with dot', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('a.b', False)); end) = 'EConstGenError');
    Check('2g count dry run', Length(CountConstRows(vC, Opts('U', False))) = 4);
    Check('2h positive control: a good name passes', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('uFieldRegistry', False)); end) = '');
  finally
    vC.Free;
  end;
end;

procedure TestGolden;
var
  vC: TFDConnection;
  vText, vText2, vMem: string;
begin
  vC := RepoFrom('golden.dlrepo.txt', 1);
  try
    vText := GenRepoConstUnit(vC, Opts('uFieldRegistry', False));
    vText2 := GenRepoConstUnit(vC, Opts('uFieldRegistry', False));
    CheckEq('3a golden unit equals the expected file byte for byte', vText, ReadAll(Fixture('constgen\golden_expected.pas')));
    Check('3b deterministic: two runs identical', vText = vText2);
    Check('3c 7-bit ASCII + CRLF only', IsCleanAscii(vText));
    Check('3d no line over 250', MaxLineLen(vText) <= 250, IntToStr(MaxLineLen(vText)));
    Check('3e null companion for a column holding a NULL', Pos('DISPLAY_LABELIsNull: Boolean;', vText) > 0);
    Check('3f no companion for a never-NULL column', Pos('    TABLE_NAMEIsNull', vText) = 0);
    Check('3g row count const', Pos('DL_FIELDS_INFO_ROW_COUNT = 6;', vText) > 0);
    Check('3h array bounds', Pos('DL_FIELDS_INFO_ROWS: array[0..5] of TDL_FIELDS_INFORow', vText) > 0);
    Check('3i FIB name const', Pos('DL_FIELDS_INFO_FIB_NAME = ''FIB$FIELDS_INFO'';', vText) > 0);
    Check('3j default memtable off: no FireDAC', (Pos('FireDAC', vText) = 0) and (Pos('Fill', vText) = 0));
    vMem := GenRepoConstUnit(vC, Opts('uFieldRegistry', True));
    Check('3l memtable: Fill declared', Pos('procedure FillDlFieldsInfo(pTable: TFDMemTable);', vMem) > 0);
    Check('3m memtable: FieldDefs with FIB sizes', Pos('pTable.FieldDefs.Add(''TABLE_NAME'', ftWideString, DL_FIELDS_INFO_TABLE_NAME_SIZE);', vMem) > 0);
    Check('3n memtable: memo type', Pos('pTable.FieldDefs.Add(''DOC_SUMMARY'', ftWideMemo);', vMem) > 0);
    Check('3o memtable: null guard', Pos('if not pRow.DISPLAY_LABELIsNull then', vMem) > 0);
    Check('3p memtable unit is ASCII + CRLF', IsCleanAscii(vMem));
    Check('3q table subset: only the asked table', Pos('TDL_ENUMVALUESRow', GenRepoConstUnit(vC, Opts('U', False, ['DL_ERROR_MESSAGES']))) = 0);
  finally
    vC.Free;
  end;
end;

procedure TestEmptyTable;
var
  vC: TFDConnection;
  vText: string;
begin
  vC := RepoFrom('edge.dlrepo.txt', 1);
  try
    vText := GenRepoConstUnit(vC, Opts('U', True));
    Check('3k empty table: count 0 and no array', (Pos('DL_ENUMVALUES_ROW_COUNT = 0;', vText) > 0) and (Pos('DL_ENUMVALUES_ROWS', vText) = 0));
    Check('3r empty table: Fill creates the dataset without a loop', Pos('for I := Low(DL_ENUMVALUES_ROWS)', vText) = 0);
    Check('3s edge values: trailing space, tab, e-acute escaped', (Pos('#9', vText) > 0) and (Pos('#233', vText) > 0) and (Pos('''ab ''', vText) > 0));
  finally
    vC.Free;
  end;
end;

procedure TestLongValue;
var
  vC: TFDConnection;
  vQ: TFDQuery;
  vText: string;
begin
  vC := RepoFrom('', 1);
  try
    vQ := TFDQuery.Create(nil);
    try
      vQ.Connection := vC;
      vQ.SQL.Text := 'INSERT INTO "DL_DATASETS_INFO" ("DS_ID","SELECT_SQL") VALUES (7, :s)';
      vQ.Params[0].AsString := StringOfChar('x', 450) + #13#10 + 'it''s ' + #$E9;
      vQ.ExecSQL;
    finally
      vQ.Free;
    end;
    vText := GenRepoConstUnit(vC, Opts('U', False, ['DL_DATASETS_INFO']));
    Check('4a long text value: no line over 250', MaxLineLen(vText) <= 250, IntToStr(MaxLineLen(vText)));
    Check('4b long text value: escapes present', (Pos('#13#10', vText) > 0) and (Pos('#233', vText) > 0) and (Pos('it''''s', vText) > 0));
    Check('4c long text value: pieces joined by +', Pos(' +' + #13#10, vText) > 0);
  finally
    vC.Free;
  end;
end;

procedure TestV2;
var
  vC: TFDConnection;
  vText: string;
begin
  vC := RepoFrom('golden_v2.txt', 2);
  try
    vText := GenRepoConstUnit(vC, Opts('uFieldRegistry', True));
    Check('5a v2: CALC_BODY column in the record', Pos('CALC_BODY: string;', vText) > 0);
    Check('5b v2: CALC_BODY field def', Pos('pTable.FieldDefs.Add(''CALC_BODY'', ftWideMemo);', vText) > 0);
    Check('5c v2: DL_LAYOUT_EVENTS never generated', Pos('DL_LAYOUT_EVENTS', vText) = 0);
    Check('5d v2: ASCII + CRLF', IsCleanAscii(vText));
    Check('5e v2 deterministic', vText = GenRepoConstUnit(vC, Opts('uFieldRegistry', True)));
  finally
    vC.Free;
  end;
end;

{ --emit <fixture> <unit> <out.pas> [memtable]: writes the unit; schema version from the fixture's first line. }
procedure Emit;
var
  vVer: Integer;
  vC: TFDConnection;
begin
  vVer := BackupFileVersion(ParamStr(2));
  vC := RepoFrom('', vVer);
  try
    RestoreRepository(vC, ParamStr(2), False);
    TFile.WriteAllText(ParamStr(4), GenRepoConstUnit(vC, Opts(ParamStr(3), SameText(ParamStr(5), 'memtable'))), TEncoding.ASCII);
  finally
    vC.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-CG-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(GDir);
  GFix := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\fixtures\fieldrepo'));
  try
    if SameText(ParamStr(1), '--emit') then
      Emit
    else
    begin
      TestLiteral;
      TestOptions;
      TestGolden;
      TestEmptyTable;
      TestLongValue;
      TestV2;
    end;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  if TDirectory.Exists(GDir) then
    TDirectory.Delete(GDir, True);
  if not SameText(ParamStr(1), '--emit') then
    Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    Halt(1);
end.
