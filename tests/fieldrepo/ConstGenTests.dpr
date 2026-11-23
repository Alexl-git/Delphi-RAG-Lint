program ConstGenTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.53 lane FR-CONSTGEN -- console tests for DRagLint.FieldRepo.ConstGen, ConstDataModule and ConstMark (spec section 7).
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M"; exit 0 only when fail=0.
  Fixtures: tests\fixtures\fieldrepo\ (golden, edge, golden_v2) and constgen\golden_expected.pas.
  `ConstGenTests.exe --emit <fixture> <unit name> <out.pas>` writes a generated constant unit
  (the golden regeneration uses it). }

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
  DRagLint.FieldRepo.ConstMark in '..\..\src\sql\DRagLint.FieldRepo.ConstMark.pas',
  DRagLint.FieldRepo.ConstGen in '..\..\src\sql\DRagLint.FieldRepo.ConstGen.pas',
  DRagLint.FieldRepo.ConstDataModule in '..\..\src\sql\DRagLint.FieldRepo.ConstDataModule.pas';

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

function Opts(const pUnit: string; const pTables: TArray<string> = nil): TConstGenOptions;
begin
  Result := Default(TConstGenOptions);
  Result.UnitName := pUnit;
  Result.SourceName := 'golden';
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
    Check('2a refused DL_META', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', ['DL_META'])); end) = 'EConstGenError');
    Check('2b refused DL_EXCEPTIONS', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', ['DL_EXCEPTIONS'])); end) = 'EConstGenError');
    Check('2c refused DL_GENERATORS', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', ['DL_GENERATORS'])); end) = 'EConstGenError');
    Check('2d unknown table', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('U', ['NOPE'])); end) = 'EConstGenError');
    Check('2e unit not identifier', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('1bad')); end) = 'EConstGenError');
    Check('2f unit with dot', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('a.b')); end) = 'EConstGenError');
    Check('2g count dry run', Length(CountConstRows(vC, Opts('U'))) = 4);
    Check('2h positive control: a good name passes', RaisedClass(procedure begin GenRepoConstUnit(vC, Opts('uFieldRegistry')); end) = '');
  finally
    vC.Free;
  end;
end;

procedure TestGolden;
var
  vC: TFDConnection;
  vText, vText2: string;
begin
  vC := RepoFrom('golden.dlrepo.txt', 1);
  try
    vText := GenRepoConstUnit(vC, Opts('uFieldRegistry'));
    vText2 := GenRepoConstUnit(vC, Opts('uFieldRegistry'));
    CheckEq('3a golden unit equals the expected file byte for byte', vText, ReadAll(Fixture('constgen\golden_expected.pas')));
    Check('3b deterministic: two runs identical', vText = vText2);
    Check('3c 7-bit ASCII + CRLF only', IsCleanAscii(vText));
    Check('3d no line over 250', MaxLineLen(vText) <= 250, IntToStr(MaxLineLen(vText)));
    Check('3e null companion for a column holding a NULL', Pos('DISPLAY_LABELIsNull: Boolean;', vText) > 0);
    Check('3f no companion for a never-NULL column', Pos('    TABLE_NAMEIsNull', vText) = 0);
    Check('3g row count const', Pos('DL_FIELDS_INFO_ROW_COUNT = 6;', vText) > 0);
    Check('3h array bounds', Pos('DL_FIELDS_INFO_ROWS: array[0..5] of TDL_FIELDS_INFORow', vText) > 0);
    Check('3i FIB name const', Pos('DL_FIELDS_INFO_FIB_NAME = ''FIB$FIELDS_INFO'';', vText) > 0);
    Check('3j the constant unit needs no FireDAC and has no fill code', (Pos('FireDAC', vText) = 0) and (Pos('procedure', vText) = 0));
    Check('3q table subset: only the asked table', Pos('TDL_ENUMVALUESRow', GenRepoConstUnit(vC, Opts('U', ['DL_ERROR_MESSAGES']))) = 0);
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
    vText := GenRepoConstUnit(vC, Opts('U'));
    Check('3k empty table: count 0 and no array', (Pos('DL_ENUMVALUES_ROW_COUNT = 0;', vText) > 0) and (Pos('DL_ENUMVALUES_ROWS', vText) = 0));
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
    vText := GenRepoConstUnit(vC, Opts('U', ['DL_DATASETS_INFO']));
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
    vText := GenRepoConstUnit(vC, Opts('uFieldRegistry'));
    Check('5a v2: CALC_BODY column in the record', Pos('CALC_BODY: string;', vText) > 0);
    Check('5c v2: DL_LAYOUT_EVENTS never generated', Pos('DL_LAYOUT_EVENTS', vText) = 0);
    Check('5d v2: ASCII + CRLF', IsCleanAscii(vText));
    Check('5e v2 deterministic', vText = GenRepoConstUnit(vC, Opts('uFieldRegistry')));
  finally
    vC.Free;
  end;
end;

procedure Exec(pConn: TFDConnection; const pSql: string);
begin
  if pConn.ExecSQL(pSql) < 0 then
    raise Exception.Create('no row changed: ' + pSql);
end;

function DefaultMarks(pConn: TFDConnection): TArray<TConstTableMark>;
begin
  Result := ConstTableMarks(pConn, SelectConstTables(pConn, Opts('U')));
end;

{ Names of the tables whose hash differs between two mark lists of the same selection. }
function Changed(const pA, pB: TArray<TConstTableMark>): string;
var
  vI: Integer;
begin
  Result := '';
  for vI := 0 to High(pA) do
    if pA[vI].Hash <> pB[vI].Hash then
      Result := Result + pA[vI].Table + ';';
end;

procedure TestMark;
var
  vA, vB: TFDConnection;
  vBase: TArray<TConstTableMark>;
  vParsed: TConstUnitMark;
begin
  vA := RepoFrom('golden_v2.txt', 2);
  vB := RepoFrom('golden_v2.txt', 2);
  try
    vBase := DefaultMarks(vA);
    Check('6a four marks, 64 hex digits', (Length(vBase) = 4) and (Length(vBase[0].Hash) = 64));
    CheckEq('6b same content in another repository file: no table differs', Changed(vBase, DefaultMarks(vB)), '');
    Exec(vB, 'UPDATE "DL_META" SET "META_VALUE" = ''x'' WHERE "META_KEY" = ''nothing''');
    Exec(vB, 'INSERT INTO "DL_META" ("META_KEY","META_VALUE") VALUES (''imported_at_utc'',''2026-01-01'')');
    Exec(vB, 'DELETE FROM "DL_EXCEPTIONS"');
    Exec(vB, 'DELETE FROM "DL_LAYOUT_EVENTS"');
    CheckEq('6c DL_META and tables that are not generated do not count', Changed(vBase, DefaultMarks(vB)), '');
    Exec(vB, 'UPDATE "DL_ENUMVALUES" SET "ESTRING" = "ESTRING" || ''!'' WHERE "EORDER" = (SELECT MIN("EORDER") FROM "DL_ENUMVALUES")');
    CheckEq('6d a changed row: exactly its table differs', Changed(vBase, DefaultMarks(vB)), 'DL_ENUMVALUES;');
    Check('6e the overall hash differs too', ConstMarkHash(vBase) <> ConstMarkHash(DefaultMarks(vB)));
    Exec(vB, 'UPDATE "DL_DATASETS_INFO" SET "CONDITIONS" = NULL WHERE "CONDITIONS" IS NOT NULL');
    Exec(vB, 'UPDATE "DL_DATASETS_INFO" SET "CONDITIONS" = ''''');
    CheckEq('6f NULL and empty text are different content', Changed(vBase, DefaultMarks(vB)), 'DL_DATASETS_INFO;DL_ENUMVALUES;');
    vParsed := ParseConstMark(GenRepoConstUnit(vA, Opts('uFieldRegistry')));
    Check('6g the unit carries the mark in its header and as a constant', (vParsed.Overall = ConstMarkHash(vBase)) and (vParsed.ConstValue = vParsed.Overall));
    Check('6h the header names every table with its hash', (Length(vParsed.Tables) = 4) and (Changed(vBase, vParsed.Tables) = '') and (vParsed.Tables[0].Rows = 7));
    Check('6i a constant unit has no form hash', vParsed.FormHash = '');
    Check('6j a source without a mark parses to none', ParseConstMark('unit a;'#13#10'interface'#13#10'end.').Overall = '');
  finally
    vA.Free;
    vB.Free;
  end;
  vA := RepoFrom('golden.dlrepo.txt', 1);
  vB := RepoFrom('golden.dlrepo.txt', 1);
  try
    Exec(vB, 'ALTER TABLE "DL_FIELDS_INFO" ADD COLUMN "CALC_BODY" TEXT');
    vBase := DefaultMarks(vA);
    vBase[0] := ConstTableMarks(vB, [RepoTablesFor(2)[1]])[0];
    CheckEq('6k a new column without data is a change', Changed(vBase, DefaultMarks(vA)), 'DL_FIELDS_INFO;');
  finally
    vA.Free;
    vB.Free;
  end;
end;

function CheckText(const pCheck: TConstCheck): string;
begin
  Result := string.Join(' / ', pCheck.Reasons);
end;

procedure TestCheckUnit;
var
  vC: TFDConnection;
  vUnit, vDm: string;
  vSrc: TConstDataModuleSource;
  vRes: TConstCheck;
begin
  vC := RepoFrom('golden_v2.txt', 2);
  try
    vUnit := TPath.Combine(GDir, 'uFieldRegistry.pas');
    vDm := TPath.Combine(GDir, 'uRegistryDm.pas');
    TFile.WriteAllText(vUnit, GenRepoConstUnit(vC, Opts('uFieldRegistry')), TEncoding.ASCII);
    vSrc := GenRepoDataModule(vC, Opts('uRegistryDm'), 'dmRegistry');
    TFile.WriteAllText(vDm, vSrc.Pas, TEncoding.ASCII);
    TFile.WriteAllText(ChangeFileExt(vDm, '.dfm'), vSrc.Dfm, TEncoding.ASCII);
    Check('8a const unit current', CheckConstUnit(vC, vUnit).State = ccsCurrent, CheckText(CheckConstUnit(vC, vUnit)));
    Check('8b data module current', CheckConstUnit(vC, vDm).State = ccsCurrent, CheckText(CheckConstUnit(vC, vDm)));
    TFile.SetLastWriteTime(vUnit, EncodeDate(2001, 1, 1));
    TFile.WriteAllText(vUnit, ReadAll(vUnit).Replace(#13#10, #10), TEncoding.ASCII);
    TFile.WriteAllText(ChangeFileExt(vDm, '.dfm'), vSrc.Dfm.Replace(#13#10, #10), TEncoding.ASCII);
    Check('8c file time and line ends do not count', (CheckConstUnit(vC, vUnit).State = ccsCurrent) and (CheckConstUnit(vC, vDm).State = ccsCurrent));
    TFile.WriteAllText(ChangeFileExt(vDm, '.dfm'), vSrc.Dfm.Replace('Active = True', 'Active = False'), TEncoding.ASCII);
    vRes := CheckConstUnit(vC, vDm);
    Check('8d an edited form is stale and named', (vRes.State = ccsStale) and (Pos('uRegistryDm.dfm', CheckText(vRes)) > 0), CheckText(vRes));
    TFile.Delete(ChangeFileExt(vDm, '.dfm'));
    Check('8e a missing form is stale', CheckConstUnit(vC, vDm).State = ccsStale);
    TFile.WriteAllText(ChangeFileExt(vDm, '.dfm'), vSrc.Dfm, TEncoding.ASCII);
    Exec(vC, 'UPDATE "DL_FIELDS_INFO" SET "DISPLAY_WIDTH" = 991 WHERE "FIELD_NAME" = ''CITY''');
    vRes := CheckConstUnit(vC, vUnit);
    Check('8f one changed row: the const unit is stale, exactly that table named',
      (vRes.State = ccsStale) and (Length(vRes.Reasons) = 1) and vRes.Reasons[0].StartsWith('DL_FIELDS_INFO:'), CheckText(vRes));
    vRes := CheckConstUnit(vC, vDm);
    Check('8g the data module is stale for the same table', (vRes.State = ccsStale) and (Length(vRes.Reasons) = 1) and vRes.Reasons[0].StartsWith('DL_FIELDS_INFO:'), CheckText(vRes));
    Check('8h missing file is an error', CheckConstUnit(vC, TPath.Combine(GDir, 'nope.pas')).State = ccsError);
    TFile.WriteAllText(vUnit, 'unit uFieldRegistry;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10, TEncoding.ASCII);
    Check('8i a unit without a mark is an error, not current', CheckConstUnit(vC, vUnit).State = ccsError);
    TFile.WriteAllText(vUnit, GenRepoConstUnit(vC, Opts('uFieldRegistry')).Replace('  REPO_CONTENT_HASH = ''', '  REPO_CONTENT_HASH = ''0'), TEncoding.ASCII);
    Check('8j header and constant disagree: stale', CheckConstUnit(vC, vUnit).State = ccsStale);
  finally
    vC.Free;
  end;
end;

{ First Content bytes of the form as hex. }
function FirstContentHex(const pDfm: string; pDigits: Integer): string;
var
  vPos: Integer;
begin
  vPos := Pos('Content = {', pDfm) + Length('Content = {');
  Result := Trim(Copy(pDfm, vPos, pDigits + 16)).Substring(0, pDigits);
end;

procedure TestDataModule;
var
  vC: TFDConnection;
  vA, vB: TConstDataModuleSource;
begin
  vC := RepoFrom('golden_v2.txt', 2);
  try
    vA := GenRepoDataModule(vC, Opts('uRegistryDm'), 'dmRegistry');
    vB := GenRepoDataModule(vC, Opts('uRegistryDm'), 'dmRegistry');
    Check('7a deterministic unit and form', (vA.Pas = vB.Pas) and (vA.Dfm = vB.Dfm));
    Check('7b unit and form are ASCII + CRLF', IsCleanAscii(vA.Pas) and IsCleanAscii(vA.Dfm));
    Check('7c class, component per table, form link', (Pos('TdmRegistry = class(TDataModule)', vA.Pas) > 0)
      and (Pos('mtDlFieldsInfo: TFDMemTable;', vA.Pas) > 0) and (Pos('mtDlErrorMessages: TFDMemTable;', vA.Pas) > 0)
      and (Pos('{$R *.dfm}', vA.Pas) > 0) and (Pos('FireDAC.Stan.StorageBin', vA.Pas) > 0));
    Check('7d no fill code in the unit', (Pos('procedure', vA.Pas) = 0) and (Pos('_ROWS', vA.Pas) = 0));
    Check('7e form: field definition with the FIB size', Pos('Name = ''TABLE_NAME'''#13#10'        DataType = ftWideString'#13#10'        Size = 68', vA.Dfm) > 0);
    Check('7f form: memo field and the v2 column', Pos('Name = ''CALC_BODY'''#13#10'        DataType = ftWideMemo', vA.Dfm) > 0);
    Check('7g form: open and read only', (Pos('Active = True', vA.Dfm) > 0) and (Pos('UpdateOptions.EnableUpdate = False', vA.Dfm) > 0));
    CheckEq('7h stream magic ADBS and zeroed header padding', FirstContentHex(vA.Dfm, 8) + '/' + FirstContentHex(vA.Dfm, 16).Substring(12), '41444253/0000');
    Check('7i the header carries the form hash', ParseConstMark(vA.Pas).FormHash = FormTextHash(vA.Dfm));
    Check('7j the mark equals the constant unit''s mark', ParseConstMark(vA.Pas).Overall = ParseConstMark(GenRepoConstUnit(vC, Opts('U'))).Overall);
    Check('7k module name not an identifier', RaisedClass(procedure begin GenRepoDataModule(vC, Opts('U'), '1bad'); end) = 'EConstGenError');
    Check('7l class name equal to the unit name', RaisedClass(procedure begin GenRepoDataModule(vC, Opts('TReg'), 'Reg'); end) = 'EConstGenError');
    Check('7m refused table', RaisedClass(procedure begin GenRepoDataModule(vC, Opts('U', ['DL_META']), 'dm'); end) = 'EConstGenError');
    Check('7n table subset', Pos('mtDlFieldsInfo', GenRepoDataModule(vC, Opts('U', ['DL_ENUMVALUES']), 'dm').Dfm) = 0);
  finally
    vC.Free;
  end;
end;

{ --emit <fixture> <unit> <out.pas>: writes the unit; schema version from the fixture's first line. }
procedure Emit;
var
  vVer: Integer;
  vC: TFDConnection;
begin
  vVer := BackupFileVersion(ParamStr(2));
  vC := RepoFrom('', vVer);
  try
    RestoreRepository(vC, ParamStr(2), False);
    TFile.WriteAllText(ParamStr(4), GenRepoConstUnit(vC, Opts(ParamStr(3))), TEncoding.ASCII);
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
      TestMark;
      TestDataModule;
      TestCheckUnit;
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
