program FbImportTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.52 lane TTB -- console tests for DRagLint.FieldRepo.FbImport.
  No Firebird: sources are TFDMemTable. Output: one PASS / FAIL line per check,
  then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Variants,
  System.IOUtils,
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
  DRagLint.FieldRepo.FbImport in '..\..\src\sql\DRagLint.FieldRepo.FbImport.pas';

const
  SAMPLE_ROWS = 3;
  SAMPLE_BYTE = 7;
  EXTRA_FIELD_LEN = 20;

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
  GSeq: Integer = 0;

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

{ Runs pProc and returns the exception message raised, '' when none; pClass gets the class name. }
function RaisedMsg(pProc: TProc; out pClass: string): string;
begin
  Result := '';
  pClass := '';
  try
    pProc;
  except
    on E: Exception do
    begin
      pClass := E.ClassName;
      Result := E.Message;
    end;
  end;
end;

function NewRepo: TFDConnection;
var
  Path: string;
begin
  Inc(GSeq);
  Path := TPath.Combine(GDir, Format('r%d.dlrepo', [GSeq]));
  CreateRepository(Path);
  Result := OpenRepository(Path, False);
end;

function ColFt(const pCol: TRepoColumn): TFieldType;
begin
  case pCol.Kind of
    rckString: Result := ftWideString;
    rckInteger: Result := ftInteger;
    rckSmallint: Result := ftSmallint;
    rckBoolean: Result := ftBoolean;
    rckText: Result := ftWideMemo;
  else
    Result := ftBytes;
  end;
end;

{ Mem table with one field per column of pTable; pSkip names a column to leave out,
  pExtra an extra ftString field to add. }
function MakeSource(const pTable: TRepoTable; const pSkip, pExtra: string): TFDMemTable;
var
  Col: TRepoColumn;
  Size: Integer;
begin
  Result := TFDMemTable.Create(nil);
  Result.FormatOptions.StrsTrim := False;
  for Col in pTable.Columns do
  begin
    if SameText(Col.Name, pSkip) then
      Continue;
    Size := 0;
    if Col.Kind = rckString then
      Size := Col.MaxLen
    else if Col.Kind = rckByte then
      Size := 1;
    Result.FieldDefs.Add(Col.Name, ColFt(Col), Size);
  end;
  if pExtra <> '' then
    Result.FieldDefs.Add(pExtra, ftString, EXTRA_FIELD_LEN);
  Result.CreateDataSet;
end;

{ Appends a FIELDS_INFO row: the two key columns, every boolean True, every other field NULL. }
procedure AddKeyRow(pSrc: TFDMemTable; const pTab, pFld: string);
var
  I: Integer;
begin
  pSrc.Append;
  for I := 0 to pSrc.FieldCount - 1 do
    if pSrc.Fields[I].DataType = ftBoolean then
      pSrc.Fields[I].AsBoolean := True;
  pSrc.FieldByName('TABLE_NAME').AsWideString := pTab;
  pSrc.FieldByName('FIELD_NAME').AsWideString := pFld;
  pSrc.Post;
end;

function Scalar(pConn: TFDConnection; const pSql: string; const pArgs: array of Variant): Variant;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := pConn;
    Q.FormatOptions.StrsTrim := False;
    Q.Open(pSql, pArgs);
    Result := Q.Fields[0].Value;
  finally
    Q.Free;
  end;
end;

procedure TestBasicCopy;
var
  Conn: TFDConnection;
  Src: TFDMemTable;
  Tab: TRepoTable;
  N: Integer;
begin
  Conn := NewRepo;
  try
    FindRepoTable('DL_FIELDS_INFO', Tab);
    Src := MakeSource(Tab, '', '');
    try
      AddKeyRow(Src, 'T1', 'F1');
      AddKeyRow(Src, 'T1', 'F2');
      AddKeyRow(Src, 'T2', 'F1');
      Src.First;
      Src.Edit;
      Src.FieldByName('DISPLAY_LABEL').AsWideString := 'Label A';
      Src.Post;
      N := ImportTableFromDataSet(Src, Conn, Tab);
      Check('1a import returns 3', N = SAMPLE_ROWS, IntToStr(N));
      Check('1b RepoRowCount = 3', RepoRowCount(Conn, 'DL_FIELDS_INFO') = SAMPLE_ROWS);
      Check('1c value equal per column',
        Scalar(Conn, 'SELECT "DISPLAY_LABEL" FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME" = ? AND "FIELD_NAME" = ?',
          ['T1', 'F1']) = 'Label A');
      Check('1d key values copied',
        Scalar(Conn, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME" = ?', ['T1']) = 2);
    finally
      Src.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TestNullAndText;
const
  SQL_FMT = 'SELECT "%s" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ?';
var
  Conn: TFDConnection;
  Src: TFDMemTable;
  Tab: TRepoTable;
  V: Variant;
  Multi: string;
begin
  Multi := 'SELECT 1' + #13#10 + 'FROM X' + #13#10 + #13#10 + 'WHERE 1=1';
  Conn := NewRepo;
  try
    FindRepoTable('DL_FIELDS_INFO', Tab);
    Src := MakeSource(Tab, '', '');
    try
      AddKeyRow(Src, 'T1', 'NULLS');
      Src.First;
      Src.Edit;
      Src.FieldByName('DISPLAY_FORMAT').AsWideString := '';
      Src.Post;
      AddKeyRow(Src, 'T1', 'SPACES');
      Src.Last;
      Src.Edit;
      Src.FieldByName('DISPLAY_LABEL').AsWideString := '  ' + #$00E9 + ' x  ';
      Src.FieldByName('DOC_REMARKS').AsWideString := Multi;
      Src.Post;
      ImportTableFromDataSet(Src, Conn, Tab);
      V := Scalar(Conn, Format(SQL_FMT, ['DISPLAY_LABEL']), ['NULLS']);
      Check('2a NULL stays NULL', VarIsNull(V));
      V := Scalar(Conn, Format(SQL_FMT, ['DISPLAY_FORMAT']), ['NULLS']);
      Check('2b empty string stays empty (control: not NULL)', (not VarIsNull(V)) and (VarToStr(V) = ''));
      V := Scalar(Conn, Format(SQL_FMT, ['DISPLAY_LABEL']), ['SPACES']);
      Check('3 spaces and non-ASCII survive', VarToStr(V) = '  ' + #$00E9 + ' x  ', '[' + VarToStr(V) + '] len=' + IntToStr(Length(VarToStr(V))));
      V := Scalar(Conn, Format(SQL_FMT, ['DOC_REMARKS']), ['SPACES']);
      Check('4 multi-line CRLF text byte for byte', VarToStr(V) = Multi);
    finally
      Src.Free;
    end;
  finally
    Conn.Free;
  end;
end;

{ Imports one DL_ENUMVALUES row whose EVALUE field is filled by pSet; returns the stored value. }
function EnumRoundTrip(pFt: TFieldType; pSize: Integer; pSet: TProc<TField>): Variant;
var
  Conn: TFDConnection;
  Src: TFDMemTable;
  Tab: TRepoTable;
  Col: TRepoColumn;
begin
  FindRepoTable('DL_ENUMVALUES', Tab);
  Conn := NewRepo;
  try
    Src := TFDMemTable.Create(nil);
    try
      for Col in Tab.Columns do
        if Col.Name = 'EVALUE' then
          Src.FieldDefs.Add(Col.Name, pFt, pSize)
        else if Col.Kind = rckString then
          Src.FieldDefs.Add(Col.Name, ftWideString, Col.MaxLen)
        else
          Src.FieldDefs.Add(Col.Name, ColFt(Col), 0);
      Src.CreateDataSet;
      Src.Append;
      Src.FieldByName('ENUMTYPE').AsWideString := 'E1';
      Src.FieldByName('EORDER').AsInteger := 1;
      Src.FieldByName('NAME').AsWideString := 'N';
      Src.FieldByName('ESTRING').AsWideString := 'S';
      pSet(Src.FieldByName('EVALUE'));
      Src.Post;
      ImportTableFromDataSet(Src, Conn, Tab);
      Result := Scalar(Conn, 'SELECT "EVALUE" FROM "DL_ENUMVALUES" WHERE "ENUMTYPE" = ?', ['E1']);
    finally
      Src.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TestByteColumn;
var
  V: Variant;
begin
  V := EnumRoundTrip(ftBytes, 1, procedure(pF: TField)
    var
      B: TBytes;
    begin
      SetLength(B, 1);
      B[0] := SAMPLE_BYTE;
      pF.AsBytes := B;
    end);
  Check('5a ftBytes $07 -> 7', (not VarIsNull(V)) and (Integer(V) = SAMPLE_BYTE));
  V := EnumRoundTrip(ftFixedChar, 1, procedure(pF: TField)
    begin
      pF.AsString := #7;
    end);
  Check('5b ftFixedChar #7 -> 7', (not VarIsNull(V)) and (Integer(V) = SAMPLE_BYTE));
  V := EnumRoundTrip(ftBytes, 1, procedure(pF: TField)
    begin
      pF.Clear;
    end);
  Check('5c NULL -> NULL', VarIsNull(V));
end;

procedure TestColumnMismatch;
var
  Conn: TFDConnection;
  Src: TFDMemTable;
  Tab: TRepoTable;
  Cls, Msg: string;
  Extra, Missing: TArray<string>;
begin
  FindRepoTable('DL_FIELDS_INFO', Tab);
  Conn := NewRepo;
  try
    Src := MakeSource(Tab, '', 'NEWCOL');
    try
      AddKeyRow(Src, 'T1', 'F1');
      Msg := RaisedMsg(procedure begin ImportTableFromDataSet(Src, Conn, Tab); end, Cls);
      Check('6a extra NEWCOL raises ERepoError naming it', (Cls = 'ERepoError') and ContainsStr(Msg, 'NEWCOL'), Cls + ' ' + Msg);
      Check('6b target unchanged after extra-column raise', RepoRowCount(Conn, 'DL_FIELDS_INFO') = 0);
    finally
      Src.Free;
    end;
    Src := MakeSource(Tab, 'UI_TAG', '');
    try
      AddKeyRow(Src, 'T1', 'F1');
      Msg := RaisedMsg(procedure begin ImportTableFromDataSet(Src, Conn, Tab); end, Cls);
      Check('6c missing UI_TAG raises ERepoError naming it', (Cls = 'ERepoError') and ContainsStr(Msg, 'UI_TAG'), Cls + ' ' + Msg);
      Check('6d target unchanged after missing-column raise', RepoRowCount(Conn, 'DL_FIELDS_INFO') = 0);
    finally
      Src.Free;
    end;
    Src := MakeSource(Tab, '', '');
    try
      AddKeyRow(Src, 'T1', 'F1');
      Msg := RaisedMsg(procedure begin ImportTableFromDataSet(Src, Conn, Tab); end, Cls);
      Check('6e control: same data without the defect imports', (Msg = '') and (RepoRowCount(Conn, 'DL_FIELDS_INFO') = 1), Cls + ' ' + Msg);
    finally
      Src.Free;
    end;
    { FIB$VERSION in the source is ignored (ruling A4). }
    FindRepoTable('DL_ERROR_MESSAGES', Tab);
    Src := MakeSource(Tab, '', 'FIB$VERSION');
    try
      CheckSourceColumns(Src, Tab, Extra, Missing);
      Check('6f FIB$VERSION in the source is not an extra column',
        (Length(Extra) = 0) and (Length(Missing) = 0));
    finally
      Src.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TestDuplicateKey;
var
  Conn: TFDConnection;
  Src: TFDMemTable;
  Tab: TRepoTable;
  Cls: string;
begin
  FindRepoTable('DL_FIELDS_INFO', Tab);
  Conn := NewRepo;
  try
    Src := MakeSource(Tab, '', '');
    try
      AddKeyRow(Src, 'T1', 'F1');
      AddKeyRow(Src, 'T1', 'F1');
      Conn.StartTransaction;
      try
        RaisedMsg(procedure begin ImportTableFromDataSet(Src, Conn, Tab); end, Cls);
        Check('7a duplicate key raises', Cls <> '', Cls);
      finally
        Conn.Rollback;
      end;
      Check('7b rollback leaves 0 rows', RepoRowCount(Conn, 'DL_FIELDS_INFO') = 0);
    finally
      Src.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TestCheckSourceColumns;
var
  Src: TFDMemTable;
  Tab: TRepoTable;
  Extra, Missing: TArray<string>;
begin
  FindRepoTable('DL_DATASETS_INFO', Tab);
  Src := MakeSource(Tab, '', '');
  try
    CheckSourceColumns(Src, Tab, Extra, Missing);
    Check('8a exact match: two empty arrays', (Length(Extra) = 0) and (Length(Missing) = 0));
  finally
    Src.Free;
  end;
  Src := MakeSource(Tab, 'DS_ID', 'ZZZ');
  try
    CheckSourceColumns(Src, Tab, Extra, Missing);
    Check('8b control: mismatch is reported', (Length(Extra) = 1) and (Extra[0] = 'ZZZ')
      and (Length(Missing) = 1) and (Missing[0] = 'DS_ID'));
  finally
    Src.Free;
  end;
end;

{ FR-SCHEMA grant: the Firebird FIB$ registry has the schema-1 columns, so a v1-shaped source must import cleanly
  into a v2 repository (live `repo import-fb` reported CALC_BODY and the other v2-only columns as missing). }
procedure TestV1SourceIntoV2;
var
  Conn: TFDConnection;
  Src: TFDMemTable;
  V1Tab: TRepoTable;
  N: Integer;
  Msg, Cls: string;
begin
  V1Tab := RepoTablesFor(1)[1];
  Conn := NewRepo;
  try
    Src := MakeSource(V1Tab, '', '');
    try
      AddKeyRow(Src, 'T1', 'F1');
      Msg := RaisedMsg(procedure begin N := ImportSourceDataSet(Src, Conn, 'DL_FIELDS_INFO'); end, Cls);
      Check('9a v1-shaped source imports cleanly into a v2 repository', Msg = '', Cls + ' ' + Msg);
      Check('9b the row landed, v2-only columns are NULL',
        (RepoRowCount(Conn, 'DL_FIELDS_INFO') = 1) and
        VarIsNull(Scalar(Conn, 'SELECT "CALC_BODY" FROM "DL_FIELDS_INFO"', [])) and
        VarIsNull(Scalar(Conn, 'SELECT "DOMAIN_NAME" FROM "DL_FIELDS_INFO"', [])));
      for N := -2 to 2 do
      begin
        Src.EmptyDataSet;
        AddKeyRow(Src, 'T1', 'AL' + IntToStr(N + 2));
        Src.Edit;
        Src.FieldByName('ALIGNMENT').AsInteger := N;
        Src.Post;
        ImportSourceDataSet(Src, Conn, 'DL_FIELDS_INFO');
      end;
      Check('9e ALIGNMENT -2 becomes NULL, -1 / 0 / 1 / 2 are copied (R5)', VarIsNull(Scalar(Conn, 'SELECT "ALIGNMENT" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''AL0''', []))
        and (VarToStr(Scalar(Conn, 'SELECT GROUP_CONCAT("ALIGNMENT") FROM (SELECT "ALIGNMENT" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" LIKE ''AL%'' ORDER BY "FIELD_NAME")', [])) = '-1,0,1,2'));
      Src.EmptyDataSet;
      Msg := RaisedMsg(procedure begin ImportTableFromDataSet(Src, Conn, RepoTablesFor(2)[1]); end, Cls);
      Check('9c control: comparing the same source against the v2 column list reports CALC_BODY missing',
        ContainsStr(Msg, 'CALC_BODY'), Msg);
      Msg := RaisedMsg(procedure begin ImportSourceDataSet(Src, Conn, 'NO_SUCH'); end, Cls);
      Check('9d unknown target table raises ERepoError', Cls = 'ERepoError', Cls + ' ' + Msg);
    finally
      Src.Free;
    end;
  finally
    Conn.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, Format('dl-fieldrepo-TTB-%d', [GetCurrentProcessId]));
  TDirectory.CreateDirectory(GDir);
  try
    TestBasicCopy;
    TestNullAndText;
    TestByteColumn;
    TestColumnMismatch;
    TestDuplicateKey;
    TestCheckSourceColumns;
    TestV1SourceIntoV2;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    ExitCode := 1;
end.
