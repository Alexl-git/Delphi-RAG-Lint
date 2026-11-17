program TextBackupTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.52 lane TTC -- console tests for DRagLint.FieldRepo.TextBackup.
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M".
  Exit code 0 only when fail=0. Contract: design section 8 (rules 1-8) and plan C1-C3.
  Fixtures: tests\fixtures\fieldrepo\ (golden, edge, bad_*_L<n>). }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Types,
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
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
  DRagLint.FieldRepo.TextBackup in '..\..\src\sql\DRagLint.FieldRepo.TextBackup.pas';

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
    if pDetail = '' then
      Writeln('PASS ', pName)
    else
      Writeln('PASS ', pName, ' (', pDetail, ')');
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

procedure CheckEq(const pName, pGot, pWant: string);
var
  vI: Integer;
  vS: string;
begin
  vS := '';
  for vI := 1 to Length(pGot) do
    vS := vS + IntToHex(Ord(pGot[vI]), 2) + ' ';
  Check(pName, pGot = pWant, 'got ' + vS + 'want len ' + IntToStr(Length(pWant)));
end;

function Fixture(const pName: string): string;
begin
  Result := TPath.Combine(GFix, pName);
end;

{ Creates a fresh repository file and returns an open read-write connection. }
function NewRepo: TFDConnection;
var
  vPath: string;
begin
  Inc(GRepoSeq);
  vPath := TPath.Combine(GDir, 'r' + IntToStr(GRepoSeq) + '.dlrepo');
  CreateRepository(vPath);
  Result := OpenRepository(vPath, False);
end;

function RepoFilePath(pConn: TFDConnection): string;
begin
  Result := pConn.Params.Values['Database'];
end;

function BytesEqual(const pA, pB: TBytes): Boolean;
begin
  Result := (Length(pA) = Length(pB)) and ((Length(pA) = 0) or CompareMem(@pA[0], @pB[0], Length(pA)));
end;

function FirstDiff(const pA, pB: TBytes): string;
var
  vI, vLine: Integer;
begin
  vLine := 1;
  for vI := 0 to Min(Length(pA), Length(pB)) - 1 do
  begin
    if pA[vI] <> pB[vI] then
      Exit('first difference at byte ' + IntToStr(vI) + ' (line ' + IntToStr(vLine) + ')');
    if pA[vI] = 10 then
      Inc(vLine);
  end;
  Result := 'length ' + IntToStr(Length(pA)) + ' vs ' + IntToStr(Length(pB));
end;

{ Runs pProc and returns the exception class name raised, '' when none. }
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

function Snapshot(pConn: TFDConnection): string;
var
  vL: TStringList;
begin
  vL := TStringList.Create;
  try
    BackupRepositoryToStrings(pConn, vL);
    vL.LineBreak := #13#10;
    Result := vL.Text;
  finally
    vL.Free;
  end;
end;

function ScalarStr(pConn: TFDConnection; const pSql: string; out pIsNull: Boolean): string;
var
  vQ: TFDQuery;
begin
  vQ := TFDQuery.Create(nil);
  try
    vQ.Connection := pConn;
    vQ.FormatOptions.StrsTrim := False;
    vQ.SQL.Text := pSql;
    vQ.Open;
    pIsNull := vQ.Fields[0].IsNull;
    Result := vQ.Fields[0].AsString;
  finally
    vQ.Free;
  end;
end;

procedure TestEscape;
var
  vAll, vEsc: string;
  vC: Integer;
  vPrintable: Boolean;
  vI: Integer;
begin
  CheckEq('1a backslash', EscapeRepoValue('a\b', False), 'a\\b');
  CheckEq('1b CR', EscapeRepoValue('a' + #13, False), 'a\r');
  CheckEq('1c TAB', EscapeRepoValue('a' + #9 + 'b', False), 'a\tb');
  CheckEq('1d LF', EscapeRepoValue('a' + #10 + 'b', False), 'a\u000Ab');
  CheckEq('1e e-acute', EscapeRepoValue(#$E9, False), '\' + 'u00E9');
  CheckEq('1f 0x7F', EscapeRepoValue(#$7F, False), '\u007F');
  CheckEq('1g trailing space', EscapeRepoValue('ab ', False), 'ab\' + 'u0020');
  CheckEq('1h inner space kept (positive control)', EscapeRepoValue('a b', False), 'a b');
  CheckEq('1i pipe and bracket raw in a value', EscapeRepoValue('x|y]', False), 'x|y]');
  CheckEq('1j pipe and bracket escaped in a header', EscapeRepoValue('x|y]', True), 'x\' + 'u007Cy\' + 'u005D');
  CheckEq('1k empty', EscapeRepoValue('', False), '');
  Check('1l unescape pairs', (UnescapeRepoValue('a\\b\r\t\' + 'u00e9\' + 'u00E9') = 'a\b' + #13 + #9 + #$E9 + #$E9));
  Check('1m bad escape raises with LineNo 0',
    RaisedClass(procedure begin UnescapeRepoValue('a\qb'); end) = 'ERepoBackupFormatError');
  Check('1n short \u raises',
    RaisedClass(procedure begin UnescapeRepoValue('a\u12'); end) = 'ERepoBackupFormatError');
  Check('1o raw non-printable raises',
    RaisedClass(procedure begin UnescapeRepoValue('a' + #$E9); end) = 'ERepoBackupFormatError');
  vAll := '';
  for vC := 0 to $2FF do
    vAll := vAll + Char(vC);
  Check('1p round trip 0..0x2FF (value)', UnescapeRepoValue(EscapeRepoValue(vAll, False)) = vAll);
  Check('1q round trip 0..0x2FF (header)', UnescapeRepoValue(EscapeRepoValue(vAll, True)) = vAll);
  vEsc := EscapeRepoValue(vAll, False);
  vPrintable := True;
  for vI := 1 to Length(vEsc) do
    if (vEsc[vI] < ' ') or (vEsc[vI] > '~') then
      vPrintable := False;
  Check('1r escaped text is printable ASCII only', vPrintable);
end;

procedure TestGoldenAndEdge(const pName: string);
var
  vConn: TFDConnection;
  vOut: string;
  vWant, vGot: TBytes;
begin
  vConn := NewRepo;
  try
    RestoreRepository(vConn, Fixture(pName), False);
    vOut := TPath.Combine(GDir, 'out-' + pName);
    BackupRepository(vConn, vOut);
    vWant := TFile.ReadAllBytes(Fixture(pName));
    vGot := TFile.ReadAllBytes(vOut);
    Check('2 ' + pName + ' round trip is byte-identical', BytesEqual(vWant, vGot),
      FirstDiff(vWant, vGot) + '; ' + IntToStr(Length(vGot)) + ' bytes');
    Check('2 ' + pName + ' no .tmp file left behind', not TFile.Exists(vOut + '.tmp'));
  finally
    vConn.Free;
  end;
end;

procedure TestValues;
var
  vConn: TFDConnection;
  vNull: Boolean;
  vS: string;
  vBase: string;
begin
  vConn := NewRepo;
  try
    RestoreRepository(vConn, Fixture('edge.dlrepo.txt'), False);
    vBase := 'SELECT %s FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME"=''T|1]'' AND "FIELD_NAME"=''F1''';
    ScalarStr(vConn, Format(vBase, ['"DISPLAY_LABEL"']), vNull);
    Check('3a omitted column is NULL', vNull);
    vS := ScalarStr(vConn, Format(vBase, ['"DISPLAY_FORMAT"']), vNull);
    Check('3b empty string is "" and not NULL', (not vNull) and (vS = ''));
    vS := ScalarStr(vConn, Format(vBase, ['"EDIT_FORMAT"']), vNull);
    Check('3c trailing space kept', vS = 'ab ');
    vS := ScalarStr(vConn, Format(vBase, ['"DEFAULTVAL"']), vNull);
    Check('3d tab kept', vS = 'x' + #9 + 'y');
    vS := ScalarStr(vConn, Format(vBase, ['"FIELD_AS_TYPE"']), vNull);
    Check('3e ? restored', vS = #$E9);
    vS := ScalarStr(vConn, Format(vBase, ['"VAR_TYPE"']), vNull);
    Check('3f backslash kept', vS = 'a\b');
    vS := ScalarStr(vConn, Format(vBase, ['"DOC_SUMMARY"']), vNull);
    Check('3g TEXT ending in LF keeps the LF', vS = 'line1' + #10);
    vS := ScalarStr(vConn, Format(vBase, ['"DOC_REMARKS"']), vNull);
    Check('3h TEXT with CRLF keeps CR LF', vS = 'a' + #13 + #10 + 'b');
    vS := ScalarStr(vConn, 'SELECT "SELECT_SQL" FROM "DL_DATASETS_INFO" WHERE "DS_ID"=7', vNull);
    Check('3i empty TEXT is "" and not NULL', (not vNull) and (vS = ''));
    vS := ScalarStr(vConn, 'SELECT "UPDATE_SQL" FROM "DL_DATASETS_INFO" WHERE "DS_ID"=7', vNull);
    Check('3j TEXT line with trailing space', vS = 'ends with ' + #10 + 'x');
    vS := ScalarStr(vConn, 'SELECT count(*) FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME"=''T|1]''', vNull);
    Check('3k key holding | and ] restored (2 rows)', vS = '2');
    vS := ScalarStr(vConn, 'SELECT count(*) FROM "DL_ENUMVALUES"', vNull);
    Check('3l empty table stays empty (positive control: DL_ERROR_MESSAGES has 1)',
      (vS = '0') and (ScalarStr(vConn, 'SELECT count(*) FROM "DL_ERROR_MESSAGES"', vNull) = '1'));
  finally
    vConn.Free;
  end;
  vConn := NewRepo;
  try
    RestoreRepository(vConn, Fixture('golden.dlrepo.txt'), False);
    vS := ScalarStr(vConn, 'SELECT "SELECT_SQL" FROM "DL_DATASETS_INFO" WHERE "DS_ID"=1', vNull);
    Check('3m CRLF SQL text exact', vS = 'SELECT A, B' + #13#10 + 'FROM AREAOFINTEREST' + #13#10 + 'WHERE A = 1');
    vS := ScalarStr(vConn, 'SELECT "SELECT_SQL" FROM "DL_DATASETS_INFO" WHERE "DS_ID"=2', vNull);
    Check('3n LF SQL text exact', vS = 'SELECT 1' + #10 + 'FROM T' + #10 + 'ORDER BY 1');
  finally
    vConn.Free;
  end;
end;

procedure TestStability;
var
  vA, vB: TFDConnection;
  vT: TRepoTable;
  vKeys, vSql: string;
  vK: TRepoColumn;
  vP1, vP2: string;
  vB1, vB2, vB3: TBytes;
begin
  vA := NewRepo;
  vB := NewRepo;
  try
    RestoreRepository(vA, Fixture('golden.dlrepo.txt'), False);
    vP1 := TPath.Combine(GDir, 'stab1.txt');
    vP2 := TPath.Combine(GDir, 'stab2.txt');
    BackupRepository(vA, vP1);
    BackupRepository(vA, vP2);
    vB1 := TFile.ReadAllBytes(vP1);
    vB2 := TFile.ReadAllBytes(vP2);
    Check('4a two backups give identical bytes', BytesEqual(vB1, vB2));
    vB.ExecSQL('ATTACH DATABASE ''' + RepoFilePath(vA) + ''' AS src');
    for vT in RepoTables do
    begin
      vKeys := '';
      for vK in vT.PkColumns do
        vKeys := vKeys + IfThen(vKeys = '', '', ', ') + QuoteRepoIdent(vK.Name) + ' DESC';
      vB.ExecSQL('DELETE FROM main.' + QuoteRepoIdent(vT.Name));
      vSql := 'INSERT INTO main.' + QuoteRepoIdent(vT.Name) + ' SELECT * FROM src.' + QuoteRepoIdent(vT.Name) + ' ORDER BY ' + vKeys;
      vB.ExecSQL(vSql);
    end;
    vB.ExecSQL('DETACH DATABASE src');
    BackupRepository(vB, TPath.Combine(GDir, 'stab3.txt'));
    vB3 := TFile.ReadAllBytes(TPath.Combine(GDir, 'stab3.txt'));
    Check('4b rows inserted in reverse key order give identical bytes', BytesEqual(vB1, vB3),
      FirstDiff(vB1, vB3));
  finally
    vB.Free;
    vA.Free;
  end;
end;

procedure TestHygiene;
var
  vConn: TFDConnection;
  vB: TBytes;
  vI: Integer;
  vHigh, vBadLf: Boolean;
  vLast: string;
  vText: string;
begin
  vConn := NewRepo;
  try
    RestoreRepository(vConn, Fixture('edge.dlrepo.txt'), False);
    BackupRepository(vConn, TPath.Combine(GDir, 'hyg.txt'));
    vB := TFile.ReadAllBytes(TPath.Combine(GDir, 'hyg.txt'));
    vHigh := False;
    vBadLf := False;
    for vI := 0 to High(vB) do
    begin
      if vB[vI] >= $80 then
        vHigh := True;
      if (vB[vI] = 10) and ((vI = 0) or (vB[vI - 1] <> 13)) then
        vBadLf := True;
    end;
    Check('5a no byte >= 0x80', not vHigh);
    Check('5b no LF without CR', not vBadLf);
    Check('5c no BOM', (Length(vB) > 0) and (vB[0] = Ord('#')));
    SetLength(vText, Length(vB));
    for vI := 0 to High(vB) do
      vText[vI + 1] := Char(vB[vI]);
    vLast := '#end DL_ERROR_MESSAGES 1' + #13#10;
    Check('5d ends with the last trailer + CRLF',
      (Length(vText) >= Length(vLast)) and (Copy(vText, Length(vText) - Length(vLast) + 1, MaxInt) = vLast));
    Check('5e first line is the magic line', Copy(vText, 1, 11) = '#DLREPO 1' + #13#10);
  finally
    vConn.Free;
  end;
end;

procedure TestBad;
var
  vFiles: TStringDynArray;
  vF, vName, vBefore, vAfter, vMsg: string;
  vConn: TFDConnection;
  vWant, vGot: Integer;
  vM: TMatch;
  vCount: Integer;
begin
  vFiles := TDirectory.GetFiles(GFix, 'bad_*.dlrepo.txt');
  vCount := 0;
  for vF in vFiles do
  begin
    vName := ExtractFileName(vF);
    vM := TRegEx.Match(vName, '_L(\d+)\.dlrepo\.txt$');
    if not vM.Success then
    begin
      Check('6 ' + vName + ' has _L<n> in its name', False);
      Continue;
    end;
    vWant := StrToInt(vM.Groups[1].Value);
    vConn := NewRepo;
    try
      RestoreRepository(vConn, Fixture('golden.dlrepo.txt'), False);
      vBefore := Snapshot(vConn);
      vGot := -1;
      vMsg := '';
      try
        RestoreRepository(vConn, vF, True);
        vMsg := 'no exception';
      except
        on E: ERepoBackupFormatError do
        begin
          vGot := E.LineNo;
          vMsg := E.Message;
        end;
        on E: Exception do
          vMsg := E.ClassName + ': ' + E.Message;
      end;
      vAfter := Snapshot(vConn);
      Check('6 ' + vName + ' fails at line ' + IntToStr(vWant), vGot = vWant, vMsg);
      Check('6 ' + vName + ' leaves the repository unchanged', vBefore = vAfter);
      Inc(vCount);
    finally
      vConn.Free;
    end;
  end;
  Check('6 at least 15 bad fixtures were found', vCount >= 15, IntToStr(vCount) + ' files');
  vConn := NewRepo;
  try
    Check('6 positive control: golden restores with pReplace',
      RaisedClass(procedure begin RestoreRepository(vConn, Fixture('golden.dlrepo.txt'), True); end) = '');
  finally
    vConn.Free;
  end;
end;

procedure TestReplace;
var
  vConn: TFDConnection;
  vNull: Boolean;
  vBefore: string;
begin
  vConn := NewRepo;
  try
    RestoreRepository(vConn, Fixture('edge.dlrepo.txt'), False);
    vBefore := Snapshot(vConn);
    Check('7a non-empty without pReplace raises ERepoError',
      RaisedClass(procedure begin RestoreRepository(vConn, Fixture('golden.dlrepo.txt'), False); end) = 'ERepoError');
    Check('7b repository unchanged after the refusal', vBefore = Snapshot(vConn));
    RestoreRepository(vConn, Fixture('golden.dlrepo.txt'), True);
    Check('7c with pReplace succeeds and the old rows are gone',
      ScalarStr(vConn, 'SELECT count(*) FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME"=''T|1]''', vNull) = '0');
    Check('7d new rows present', ScalarStr(vConn, 'SELECT count(*) FROM "DL_FIELDS_INFO"', vNull) = '6');
  finally
    vConn.Free;
  end;
end;

procedure TestDefaultsDoNotLeak;
var
  vConn: TFDConnection;
  vNull: Boolean;
  vLines: TStringList;
begin
  vConn := NewRepo;
  vLines := TStringList.Create;
  try
    vLines.Add('#DLREPO 1');
    vLines.Add('#end DL_META 0');
    vLines.Add('[DL_FIELDS_INFO T|F]');
    vLines.Add('VISIBLE=true');
    vLines.Add('TRIGGERED=false');
    vLines.Add('BG_COLOR=false');
    vLines.Add('FG_COLOR=false');
    vLines.Add('UNIQUE_FLAG=false');
    vLines.Add('PRIMARY_KEY=false');
    vLines.Add('CUSTOM_TYPE=false');
    vLines.Add('ISCALCULATED=false');
    vLines.Add('ISLOOKUP=false');
    vLines.Add('ISENUM=false');
    vLines.Add('');
    vLines.Add('#end DL_FIELDS_INFO 1');
    vLines.Add('#end DL_DATASETS_INFO 0');
    vLines.Add('#end DL_ENUMVALUES 0');
    vLines.Add('#end DL_ERROR_MESSAGES 0');
    RestoreRepositoryFromStrings(vConn, vLines, False);
    ScalarStr(vConn, 'SELECT "DOC_SUMMARY" FROM "DL_FIELDS_INFO"', vNull);
    Check('8a omitted DOC_SUMMARY restores as NULL, not the default', vNull);
    ScalarStr(vConn, 'SELECT "UI_TAG" FROM "DL_FIELDS_INFO"', vNull);
    Check('8b omitted UI_TAG restores as NULL, not 0', vNull);
    vLines.Delete(3);
    Check('8c a row omitting the NOT NULL column VISIBLE is a format error',
      RaisedClass(procedure begin RestoreRepositoryFromStrings(vConn, vLines, True); end) = 'ERepoBackupFormatError');
  finally
    vLines.Free;
    vConn.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-TTC-' + IntToStr(GetCurrentProcessId));
  if TDirectory.Exists(GDir) then
    TDirectory.Delete(GDir, True);
  TDirectory.CreateDirectory(GDir);
  GFix := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\fixtures\fieldrepo'));
  try
    TestEscape;
    TestGoldenAndEdge('golden.dlrepo.txt');
    TestGoldenAndEdge('edge.dlrepo.txt');
    TestValues;
    TestStability;
    TestHygiene;
    TestBad;
    TestReplace;
    TestDefaultsDoNotLeak;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  if TDirectory.Exists(GDir) then
    TDirectory.Delete(GDir, True);
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    Halt(1);
end.
