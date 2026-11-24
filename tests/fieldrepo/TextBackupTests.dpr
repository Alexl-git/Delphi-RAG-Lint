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

{ Creates a fresh repository file of the given schema version (default 1: the 1.52 goldens
  are `#DLREPO 1` and stay byte-identical) and returns an open read-write connection. }
function NewRepo(pVersion: Integer = 1): TFDConnection;
var
  vPath: string;
begin
  Inc(GRepoSeq);
  vPath := TPath.Combine(GDir, 'r' + IntToStr(GRepoSeq) + '.dlrepo');
  CreateRepository(vPath, pVersion);
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
    for vT in RepoTablesFor(1) do
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

{ FR-MODEL task 3: #DLREPO 2, the v1/v2 restore matrix, the missing-file version. }
procedure TestV2;
var
  vV1, vV2: TFDConnection;
  vOut, vMsg: string;
  vWant, vGot: TBytes;
  vCls: string;
  vNull: Boolean;
  vPath: string;
begin
  vV2 := NewRepo(2);
  try
    RestoreRepository(vV2, Fixture('golden_v2.txt'), False);
    vOut := TPath.Combine(GDir, 'out-golden_v2.txt');
    BackupRepository(vV2, vOut);
    vWant := TFile.ReadAllBytes(Fixture('golden_v2.txt'));
    vGot := TFile.ReadAllBytes(vOut);
    Check('20a golden_v2.txt round trip is byte-identical', BytesEqual(vWant, vGot), FirstDiff(vWant, vGot));
    Check('20b CALC_BODY restored', ScalarStr(vV2,
      'SELECT "CALC_BODY" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''TOTAL''', vNull) = '{{TOTAL}} := {{AMOUNT}} * 2;');
    Check('20c exception row restored', ScalarStr(vV2, 'SELECT "REASON" FROM "DL_EXCEPTIONS"', vNull) = 'legacy width');
  finally
    vV2.Free;
  end;

  vV2 := NewRepo(2);
  try
    RestoreRepository(vV2, Fixture('golden.dlrepo.txt'), False);
    vOut := TPath.Combine(GDir, 'v1-in-v2.txt');
    BackupRepository(vV2, vOut);
    vGot := TFile.ReadAllBytes(vOut);
    vWant := TFile.ReadAllBytes(Fixture('golden.dlrepo.txt'));
    Check('21a #DLREPO 1 restores into a v2 repository (rows present)',
      ScalarStr(vV2, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO"', vNull) = '6');
    Check('21b the v2 backup of it is the v1 backup with #DLREPO 2, CALC_BODY absent and two empty trailers',
      TEncoding.ASCII.GetString(vGot) = '#DLREPO 2' + Copy(TEncoding.ASCII.GetString(vWant), Length('#DLREPO 1') + 1, MaxInt)
        + '#end DL_LAYOUT_EVENTS 0' + #13#10 + '#end DL_EXCEPTIONS 0' + #13#10 + '#end DL_DOMAINS 0' + #13#10 + '#end DL_CONSTRAINTS 0' + #13#10 + '#end DL_CONSTRAINT_COLUMNS 0' + #13#10 + '#end DL_GENERATORS 0' + #13#10);
    Check('21c CALC_BODY is NULL after a v1 restore',
      ScalarStr(vV2, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "CALC_BODY" IS NOT NULL', vNull) = '0');
    Check('21d schema-2 tables are empty after a v1 restore',
      (ScalarStr(vV2, 'SELECT COUNT(*) FROM "DL_EXCEPTIONS"', vNull) = '0')
      and (ScalarStr(vV2, 'SELECT COUNT(*) FROM "DL_LAYOUT_EVENTS"', vNull) = '0'));
    Check('21e trailers of the two new tables are present and empty',
      (Pos('#end DL_LAYOUT_EVENTS 0' + #13#10 + '#end DL_EXCEPTIONS 0' + #13#10 + '#end DL_DOMAINS 0' + #13#10 + '#end DL_CONSTRAINTS 0' + #13#10 + '#end DL_CONSTRAINT_COLUMNS 0' + #13#10 + '#end DL_GENERATORS 0' + #13#10, TEncoding.ASCII.GetString(vGot)) > 0));
  finally
    vV2.Free;
  end;

  { a v1 repository's backup is still byte-identical to the v1 golden (the existing test 2 pins it
    too; this is the explicit v1 side of the matrix) }
  vV1 := NewRepo(1);
  try
    RestoreRepository(vV1, Fixture('golden.dlrepo.txt'), False);
    vOut := TPath.Combine(GDir, 'v1-out.txt');
    BackupRepository(vV1, vOut);
    vWant := TFile.ReadAllBytes(Fixture('golden.dlrepo.txt'));
    vGot := TFile.ReadAllBytes(vOut);
    Check('22a v1 repository still writes the v1 golden byte-identically', BytesEqual(vWant, vGot), FirstDiff(vWant, vGot));
    vCls := RaisedClass(procedure begin RestoreRepository(vV1, Fixture('golden_v2.txt'), True); end);
    Check('22b #DLREPO 2 into a v1 repository is refused with ERepoError', vCls = 'ERepoError', vCls);
    vMsg := '';
    try
      RestoreRepository(vV1, Fixture('golden_v2.txt'), True);
    except
      on E: Exception do
        vMsg := E.Message;
    end;
    Check('22c the refusal says "migrate first" and "does not match"',
      vMsg.Contains('migrate first') and vMsg.Contains('does not match'), vMsg);
    Check('22d the refused restore changed nothing (still 6 field rows)',
      ScalarStr(vV1, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO"', vNull) = '6');
  finally
    vV1.Free;
  end;

  Check('23a BackupFileVersion of the v1 golden is 1', BackupFileVersion(Fixture('golden.dlrepo.txt')) = 1);
  Check('23b BackupFileVersion of the v2 golden is 2', BackupFileVersion(Fixture('golden_v2.txt')) = 2);
  vPath := TPath.Combine(GDir, 'notmagic.txt');
  TFile.WriteAllText(vPath, 'hello' + #13#10, TEncoding.ASCII);
  Check('23c BackupFileVersion of a file without the magic line is 0 (control)', BackupFileVersion(vPath) = 0);

  { EVCOLS: #DLREPO 3 }
  vV2 := NewRepo(3);
  try
    RestoreRepository(vV2, Fixture('golden_v3.txt'), False);
    vOut := TPath.Combine(GDir, 'out-golden_v3.txt');
    BackupRepository(vV2, vOut);
    vWant := TFile.ReadAllBytes(Fixture('golden_v3.txt'));
    vGot := TFile.ReadAllBytes(vOut);
    Check('25a golden_v3.txt round trip is byte-identical', BytesEqual(vWant, vGot), FirstDiff(vWant, vGot));
    Check('25b an event column restored', ScalarStr(vV2, 'SELECT "ONGETTEXT_BODY" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''AMOUNT''', vNull)
      = 'if {{AMOUNT}}.IsNull then'#13#10'  Text := '''';');
    Check('25c an unbound grid column has no table', (ScalarStr(vV2, 'SELECT COUNT(*) FROM "DL_GRID_COLUMNS" WHERE "TABLE_NAME" IS NULL AND "FIELD_NAME" IS NULL', vNull) = '1'));
    RestoreRepository(vV2, Fixture('golden_v2.txt'), True);
    vOut := TPath.Combine(GDir, 'out-v2-in-v3.txt');
    BackupRepository(vV2, vOut);
    Check('25d #DLREPO 2 restores into a v3 repository: the v2 text with #DLREPO 3, schema_version 3 and an empty DL_GRID_COLUMNS',
      TEncoding.ASCII.GetString(TFile.ReadAllBytes(vOut)) = TEncoding.ASCII.GetString(TFile.ReadAllBytes(Fixture('golden_v2.txt'))).Replace('#DLREPO 2', '#DLREPO 3').Replace('META_VALUE=2', 'META_VALUE=3')
        + '#end DL_GRID_COLUMNS 0' + #13#10);
    RestoreRepository(vV2, Fixture('golden.dlrepo.txt'), True);
    Check('25e #DLREPO 1 restores into a v3 repository', ScalarStr(vV2, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO"', vNull) = '6');
  finally
    vV2.Free;
  end;
  vV2 := NewRepo(2);
  try
    vMsg := '';
    try
      RestoreRepository(vV2, Fixture('golden_v3.txt'), True);
    except
      on E: Exception do
        vMsg := E.Message;
    end;
    Check('25f #DLREPO 3 into a v2 repository is refused: migrate first', vMsg.Contains('migrate first'), vMsg);
  finally
    vV2.Free;
  end;
  vV2 := NewRepo(3);
  try
    vV2.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" VALUES (''f'',''v'',''c'',NULL,NULL,0)');
    vCls := RaisedClass(procedure begin RestoreRepository(vV2, Fixture('golden.dlrepo.txt'), False); end);
    Check('25g restore without replace refuses when only DL_GRID_COLUMNS holds rows', vCls = 'ERepoError', vCls);
  finally
    vV2.Free;
  end;
  Check('25h BackupFileVersion of the v3 golden is 3', BackupFileVersion(Fixture('golden_v3.txt')) = 3);

  { restore into a v2 repository that already holds exception rows needs replace }
  vV2 := NewRepo(2);
  try
    vV2.ExecSQL('INSERT INTO "DL_EXCEPTIONS" ("RULE_ID","REASON") VALUES (''r1'',''x'')');
    vCls := RaisedClass(procedure begin RestoreRepository(vV2, Fixture('golden.dlrepo.txt'), False); end);
    Check('24a restore without replace refuses when only DL_EXCEPTIONS holds rows', vCls = 'ERepoError', vCls);
    RestoreRepository(vV2, Fixture('golden.dlrepo.txt'), True);
    Check('24b with replace the exception rows are replaced (restored empty)',
      ScalarStr(vV2, 'SELECT COUNT(*) FROM "DL_EXCEPTIONS"', vNull) = '0');
  finally
    vV2.Free;
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
    TestV2;
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
