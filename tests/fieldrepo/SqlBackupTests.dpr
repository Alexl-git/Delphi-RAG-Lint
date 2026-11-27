program SqlBackupTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.56 lane BK-Q -- console tests for DRagLint.FieldRepo.SqlBackup (`repo backup --format sql`).
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0.
  The proof is a full round trip: fill repository A from a text fixture, SQL-backup A, restore into an
  EMPTY repository B, compare every table's rows (row counts AND the whole text backup of A and B). }

uses
  Winapi.Windows,
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
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.TextBackup in '..\..\src\sql\DRagLint.FieldRepo.TextBackup.pas',
  DRagLint.FieldRepo.SqlBackup in '..\..\src\sql\DRagLint.FieldRepo.SqlBackup.pas';

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
    Writeln('PASS ', pName, IfThen(pDetail = '', '', ' (' + pDetail + ')'));
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

function NewRepo(pVersion: Integer): TFDConnection;
begin
  Inc(GRepoSeq);
  var vPath := TPath.Combine(GDir, 'r' + IntToStr(GRepoSeq) + '.dlrepo');
  CreateRepository(vPath, pVersion);
  Result := OpenRepository(vPath, False);
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

function TotalRows(pConn: TFDConnection): Integer;
var
  vT: TRepoTable;
begin
  Result := 0;
  for vT in RepoTablesFor(RepoSchemaVersion(pConn)) do
    Inc(Result, RepoRowCount(pConn, vT.Name));
end;

{ Every table of the version has the same row count in both repositories. }
function SameCounts(pA, pB: TFDConnection; out pDetail: string): Boolean;
var
  vT: TRepoTable;
begin
  Result := True;
  pDetail := '';
  for vT in RepoTablesFor(RepoSchemaVersion(pA)) do
    if RepoRowCount(pA, vT.Name) <> RepoRowCount(pB, vT.Name) then
    begin
      Result := False;
      pDetail := vT.Name + ' ' + IntToStr(RepoRowCount(pA, vT.Name)) + ' vs ' + IntToStr(RepoRowCount(pB, vT.Name));
      Exit;
    end;
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

procedure TestRoundTrip(const pFixture: string);
var
  vA, vB: TFDConnection;
  vFile, vDetail: string;
  vBytes: TBytes;
  vI: Integer;
  vAscii: Boolean;
begin
  vA := NewRepo(REPO_SCHEMA_VERSION);
  vB := NewRepo(REPO_SCHEMA_VERSION);
  try
    RestoreRepository(vA, TPath.Combine(GFix, pFixture), False);
    Check(pFixture + ' fixture filled A (positive control)', TotalRows(vA) > 4, IntToStr(TotalRows(vA)) + ' rows');
    Check(pFixture + ' B starts empty', RepoIsEmpty(vB));
    vFile := TPath.Combine(GDir, 'a-' + IntToStr(GRepoSeq) + '.sql');
    BackupRepositorySql(vA, vFile);
    vBytes := TFile.ReadAllBytes(vFile);
    vAscii := True;
    for vI := 0 to High(vBytes) do
      if vBytes[vI] >= $80 then
        vAscii := False;
    Check(pFixture + ' file is 7-bit ASCII', vAscii);
    Check(pFixture + ' file starts with the SQL magic', Pos('-- DLREPO-SQL 5', TEncoding.ASCII.GetString(vBytes, 0, 15)) = 1);
    Check(pFixture + ' file holds DDL and INSERT lines', (Pos('CREATE TABLE ', TEncoding.ASCII.GetString(vBytes)) > 0)
      and (Pos('INSERT INTO ', TEncoding.ASCII.GetString(vBytes)) > 0));
    RestoreRepositorySql(vB, vFile, False);
    Check(pFixture + ' every table has the same row count', SameCounts(vA, vB, vDetail), vDetail);
    Check(pFixture + ' every row equal (whole text backup A = B)', Snapshot(vA) = Snapshot(vB));
    BackupRepositorySql(vB, vFile + '2');
    Check(pFixture + ' backup(restore(F)) = F byte for byte', TFile.ReadAllText(vFile) = TFile.ReadAllText(vFile + '2'));
  finally
    vA.Free;
    vB.Free;
  end;
end;

procedure TestOlderScript;
var
  vOld, vNew, vRef: TFDConnection;
  vFile: string;
begin
  vOld := NewRepo(1);
  vNew := NewRepo(REPO_SCHEMA_VERSION);
  vRef := NewRepo(REPO_SCHEMA_VERSION);
  try
    RestoreRepository(vOld, TPath.Combine(GFix, 'golden.dlrepo.txt'), False);
    vFile := TPath.Combine(GDir, 'v1.sql');
    BackupRepositorySql(vOld, vFile);
    Check('v1 script header says 1', Pos('-- DLREPO-SQL 1', TFile.ReadAllText(vFile)) = 1);
    RestoreRepositorySql(vNew, vFile, False);
    RestoreRepository(vRef, TPath.Combine(GFix, 'golden.dlrepo.txt'), False);
    Check('v1 script into a v5 repository = the text restore of the same data (migrated)', Snapshot(vNew) = Snapshot(vRef));
  finally
    vOld.Free;
    vNew.Free;
    vRef.Free;
  end;
end;

procedure TestRefusalsAndBadFiles;
var
  vA, vB: TFDConnection;
  vFile, vBad: string;
  vLines: TStringList;
  vBefore: string;
begin
  vA := NewRepo(REPO_SCHEMA_VERSION);
  vB := NewRepo(REPO_SCHEMA_VERSION);
  vLines := TStringList.Create;
  try
    RestoreRepository(vA, TPath.Combine(GFix, 'golden.dlrepo.txt'), False);
    vFile := TPath.Combine(GDir, 'g.sql');
    BackupRepositorySql(vA, vFile);
    Check('non-empty repository without replace is refused',
      RaisedClass(procedure begin RestoreRepositorySql(vA, vFile, False); end) = 'ERepoError');
    Check('non-empty repository with replace works',
      RaisedClass(procedure begin RestoreRepositorySql(vA, vFile, True); end) = '');
    vBefore := Snapshot(vB);
    vLines.LoadFromFile(vFile);
    vLines.Delete(vLines.Count - 1);
    vBad := TPath.Combine(GDir, 'trunc.sql');
    vLines.SaveToFile(vBad);
    Check('truncated script (last trailer missing) -> ERepoBackupFormatError, B unchanged',
      (RaisedClass(procedure begin RestoreRepositorySql(vB, vBad, False); end) = 'ERepoBackupFormatError')
      and (Snapshot(vB) = vBefore));
    vLines.LoadFromFile(vFile);
    vLines.Insert(vLines.Count - 3, 'DROP TABLE "DL_FIELDS_INFO";');
    vBad := TPath.Combine(GDir, 'drop.sql');
    vLines.SaveToFile(vBad);
    Check('a foreign statement (DROP TABLE) is rejected, never executed',
      (RaisedClass(procedure begin RestoreRepositorySql(vB, vBad, False); end) = 'ERepoBackupFormatError')
      and (RepoRowCount(vB, 'DL_FIELDS_INFO') = 0));
    vBad := TPath.Combine(GDir, 'text.sql');
    TFile.Copy(TPath.Combine(GFix, 'golden.dlrepo.txt'), vBad);
    Check('a text backup given to the SQL restore -> ERepoBackupFormatError',
      RaisedClass(procedure begin RestoreRepositorySql(vB, vBad, False); end) = 'ERepoBackupFormatError');
  finally
    vLines.Free;
    vA.Free;
    vB.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-BKQ-' + IntToStr(GetCurrentProcessId));
  if TDirectory.Exists(GDir) then
    TDirectory.Delete(GDir, True);
  TDirectory.CreateDirectory(GDir);
  GFix := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\fixtures\fieldrepo'));
  try
    TestRoundTrip('golden.dlrepo.txt');
    TestRoundTrip('edge.dlrepo.txt');
    TestOlderScript;
    TestRefusalsAndBadFiles;
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
