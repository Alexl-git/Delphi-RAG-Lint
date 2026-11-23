program FbConnStringTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.53 lane FBFIX -- console tests for DRagLint.Sql.FbConnString (the refused --connection keys) and for the
  live Firebird schema reader. Part A is pure. Part B needs a SCRATCH Firebird database (the runner makes one with a
  private embedded engine and puts its connection string in DL_TEST_FB_CONNECTION): it prints a SKIP line when the
  variable is missing, and the runner turns a SKIP into a FAIL whenever an embedded engine is available.
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. }

uses
  System.SysUtils,
  System.Classes,
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
  DRagLint.Sql.FbConnString in '..\..\src\sql\DRagLint.Sql.FbConnString.pas',
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.FbImport in '..\..\src\sql\DRagLint.FieldRepo.FbImport.pas',
  DRagLint.FieldRepo.FbSchemaRead in '..\..\src\sql\DRagLint.FieldRepo.FbSchemaRead.pas';

const
  SECRET = 'Zq7s3cr3tPw';
  DB_PASSWORD = 'masterkey';

var
  GPass: Integer = 0;
  GFail: Integer = 0;

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

{ The message of the exception pProc raises, '' when none; pClass gets its class name. }
function Raised(pProc: TProc; out pClass: string): string;
begin
  Result := '';
  pClass := '';
  try
    pProc;
  except
    on E: Exception do
    begin
      Result := E.Message;
      pClass := E.ClassName;
    end;
  end;
end;

procedure TestRefusedKeys;
var
  VKey, VClass, VMsg, VCase: string;
  VCases: TArray<string>;
begin
  { positive control first: a normal string is accepted, so the refusals below cannot be a rule that rejects all }
  Check('A0 normal string accepted', FbForbiddenKey('Database=localhost:C:\x.fdb;User_Name=SYSDBA;Password=' + SECRET + ';DriverID=FB') = '');
  Check('A0b a value that merely contains a key name is accepted',
    FbForbiddenKey('Database=C:\DropDatabase.fdb;Password=OpenMode;CharacterSet=UTF8') = '');
  for VKey in FB_FORBIDDEN_KEYS do
  begin
    Check('A1 ' + VKey + ' refused', FbForbiddenKey('Database=x.fdb;' + VKey + '=Yes') = VKey);
    Check('A1b ' + VKey + ' refused case-insensitively, trimmed', FbForbiddenKey('Database=x.fdb;  ' + UpperCase(VKey) + '  =Yes') = VKey);
    Check('A1c ' + VKey + ' refused as a bare key', FbForbiddenKey('Database=x.fdb;' + LowerCase(VKey)) = VKey);
    Check('A1d ' + VKey + ' refused as the first pair', FbForbiddenKey(VKey + '=Yes;Database=x.fdb') = VKey);
  end;
  VCases := ['Database=x.fdb' + #13#10 + 'DropDatabase=Yes', 'Database=x.fdb' + #10 + 'OpenMode=Create'];
  for VCase in VCases do
    Check('A2 a CR/LF-injected key is refused', FbForbiddenKey(VCase) <> '');
  VMsg := Raised(
    procedure
    begin
      RequireFbConnectionSafe('Database=x.fdb;Password=' + SECRET + ';DropDatabase=Yes');
    end, VClass);
  Check('A3 RequireFbConnectionSafe raises EFbConnStringError naming the key', (VClass = 'EFbConnStringError') and (Pos('DropDatabase', VMsg) > 0), VClass + ': ' + VMsg);
  Check('A4 the message never carries the password', Pos(SECRET, VMsg) = 0, VMsg);
  VMsg := Raised(
    procedure
    begin
      RequireFbConnectionSafe('Database=x.fdb;Password=' + SECRET + ';DriverID=FB');
    end, VClass);
  Check('A5 positive control: a normal string raises nothing', VClass = '', VClass + ': ' + VMsg);
  { OpenSourceConnection must refuse BEFORE it opens: a bogus Database would otherwise give a FireDAC error }
  VMsg := Raised(
    procedure
    var
      VDb: string;
    begin
      OpenSourceConnection('Database=localhost:C:\no\such.fdb;User_Name=SYSDBA;Password=' + SECRET + ';CreateDatabase=Yes', VDb).Free;
    end, VClass);
  Check('A6 OpenSourceConnection refuses CreateDatabase before opening', (VClass = 'EFbConnStringError') and (Pos(SECRET, VMsg) = 0), VClass + ': ' + VMsg);
end;

{ the connection string with its Database value replaced }
function WithDatabase(const pConn, pDb: string): string;
var
  VPair: string;
begin
  Result := '';
  for VPair in pConn.Split([';'], TStringSplitOptions.ExcludeEmpty) do
    if StartsText('Database=', VPair) then
      Result := Result + 'Database=' + pDb + ';'
    else
      Result := Result + VPair + ';';
end;

function FindColumn(const pCols: TArray<TFbColumn>; const pTable, pName: string): TFbColumn;
var
  VCol: TFbColumn;
begin
  for VCol in pCols do
    if SameText(VCol.TableName, pTable) and SameText(VCol.ColumnName, pName) then
      Exit(VCol);
  Result := Default(TFbColumn);
end;

function FindDomain(const pDoms: TArray<TFbDomain>; const pName: string): TFbDomain;
var
  VDom: TFbDomain;
begin
  for VDom in pDoms do
    if SameText(VDom.Name, pName) then
      Exit(VDom);
  Result := Default(TFbDomain);
end;

procedure TestLiveReader(const pConn: string; out pDb: string);
var
  VFb: TFDConnection;
  VSrc: TFbSchemaSources;
  VModel: TFbSchemaModel;
  VCol: TFbColumn;
  VCon: TFbConstraint;
  VDom: TFbDomain;
  VKinds: string;
begin
  VFb := OpenSourceConnection(pConn, pDb);
  try
    VSrc := OpenFbSchemaSources(VFb);
    try
      VModel := ReadSchemaModel(VSrc, 'live', pDb);
    finally
      FreeFbSchemaSources(VSrc);
    end;
  finally
    VFb.Free;
  end;
  Check('B1 live reader: the five queries run on Firebird 4 (no reserved-word alias)', Length(VModel.Columns) = 10, IntToStr(Length(VModel.Columns)));
  VDom := FindDomain(VModel.Domains, 'D_NAME');
  Check('B2 domain D_NAME: VARCHAR(40), CHAR_LENGTH 40, WIN1252, NOT NULL, default',
    (VDom.CharLength = 40) and (VDom.Charset = 'WIN1252') and (VDom.NullFlag = 1) and (Pos('''x''', VDom.DefaultSource) > 0),
    Format('len=%d cs=%s nf=%d def=%s', [VDom.CharLength, VDom.Charset, VDom.NullFlag, VDom.DefaultSource]));
  Check('B2b domain D_POS keeps its CHECK source', Pos('VALUE > 0', FindDomain(VModel.Domains, 'D_POS').CheckSource) > 0);
  VCol := FindColumn(VModel.Columns, 'PARENT', 'CODE');
  Check('B3 CHAR(3) column CODE: character length 3, NOT NULL', (VCol.CharLength = 3) and (VCol.NullFlag = 1));
  Check('B4 INT128 and DECFLOAT domains read',
    (FindColumn(VModel.Columns, 'PARENT', 'BIGV').DomainName = 'D_BIG') and (FindColumn(VModel.Columns, 'PARENT', 'DECV').DomainName = 'D_DEC'));
  VKinds := '';
  for VCon in VModel.Constraints do
    VKinds := VKinds + VCon.Kind + ':' + VCon.Name + ' ';
  Check('B5 PK, UNIQUE, FK and CHECK constraints read',
    (Pos('PK:PK_PARENT', VKinds) > 0) and (Pos('UNIQUE:UQ_CODE', VKinds) > 0) and (Pos('FK:FK_CHILD_PARENT', VKinds) > 0) and (Pos('CHECK:', VKinds) > 0), VKinds);
  VKinds := '';
  for VCon in VModel.Constraints do
    if VCon.Name = 'FK_CHILD_PARENT' then
      VKinds := VCon.DeleteRule + '/' + VCon.UpdateRule + '/' + VCon.RefTable + '/' + string.Join(',', VCon.Columns);
  Check('B6 FK cascade rules, referenced table and key column (the POSITION query)', VKinds = 'CASCADE/SET NULL/PARENT/PID', VKinds);
  Check('B7 generator read', (Length(VModel.Generators) = 1) and (VModel.Generators[0] = 'GEN_X'));
  Check('B8 inline NOT NULL on the column (not the domain) is kept', FindColumn(VModel.Columns, 'PARENT', 'INLN').NullFlag = 1);
  Check('B9 inline DEFAULT on the column is kept', Pos('''abc''', FindColumn(VModel.Columns, 'PARENT', 'INLD').DefaultSource) > 0,
    FindColumn(VModel.Columns, 'PARENT', 'INLD').DefaultSource);
  VCol := FindColumn(VModel.Columns, 'PARENT', 'BIGV');
  Check('B9b a nullable column without a default stays NULL-able with no default', (VCol.NullFlag = 0) and (VCol.DefaultSource = ''));
  VCol := FindColumn(VModel.Columns, 'PARENT', 'NAME');
  Check('B9c a domain NOT NULL and default still reach the column', (Pos('''x''', VCol.DefaultSource) > 0) and (VCol.NullFlag = 1));
end;

{ DropDatabase and friends on a COPY of the scratch database: refused, the file survives, a normal open still works }
procedure TestLiveRefusal(const pConn, pDb: string);
var
  VVictim, VClass, VMsg, VKey, VName: string;
  VSize: Int64;
  VFb: TFDConnection;
begin
  VVictim := TPath.Combine(TPath.GetDirectoryName(pDb), 'victim.fdb');
  TFile.Copy(pDb, VVictim, True);
  VSize := TFile.GetSize(VVictim);
  for VKey in FB_FORBIDDEN_KEYS do
  begin
    VName := VKey;
    VMsg := Raised(
      procedure
      var
        VD: string;
      begin
        OpenSourceConnection(WithDatabase(pConn, VVictim) + VName + '=Yes', VD).Free;
      end, VClass);
    Check('C1 ' + VKey + '=Yes refused on a live database', VClass = 'EFbConnStringError', VClass + ': ' + VMsg);
    Check('C1b the database file survives ' + VKey, TFile.Exists(VVictim) and (TFile.GetSize(VVictim) = VSize));
    Check('C1c the error never echoes the password (' + VKey + ')', Pos(DB_PASSWORD, VMsg) = 0, VMsg);
  end;
  VFb := OpenSourceConnection(WithDatabase(pConn, VVictim), VName);
  try
    Check('C2 positive control: a normal open of the surviving copy reads it', VFb.ExecSQLScalar('SELECT COUNT(*) FROM PARENT') = 0);
  finally
    VFb.Free;
  end;
end;

procedure TestLive;
var
  VConn, VDb: string;
begin
  VConn := GetEnvironmentVariable('DL_TEST_FB_CONNECTION');
  if VConn = '' then
  begin
    Writeln('SKIP B live part: DL_TEST_FB_CONNECTION not set');
    Exit;
  end;
  TestLiveReader(VConn, VDb);
  TestLiveRefusal(VConn, VDb);
end;

begin
  try
    TestRefusedKeys;
    TestLive;
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
