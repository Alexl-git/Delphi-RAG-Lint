program BackupFormatTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.56 lane BK-Z -- console tests for `repo backup --format text|sql|zip` at the unit level.
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0.
  The proof is a restore round trip PER FORMAT: fill repository A from a fixture, back it up in the
  format, restore into a missing / empty repository B, compare the whole text backup of A and B.
  Negative controls: a corrupt zip, a non-zip file, a zip without the marker and a zip holding a
  foreign file are refused with ERepoBackupFormatError and the target repository stays unchanged. }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Zip,
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
  DRagLint.FieldRepo.SqlBackup in '..\..\src\sql\DRagLint.FieldRepo.SqlBackup.pas',
  DRagLint.FieldRepo.ZipBackup in '..\..\src\sql\DRagLint.FieldRepo.ZipBackup.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
  GFix: string;
  GSeq: Integer = 0;

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

function NewPath: string;
begin
  Inc(GSeq);
  Result := TPath.Combine(GDir, 'r' + IntToStr(GSeq) + '.dlrepo');
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

function SnapshotOfFile(const pPath: string): string;
var
  vC: TFDConnection;
begin
  vC := OpenRepository(pPath, True);
  try
    Result := Snapshot(vC);
  finally
    vC.Free;
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

{ A new repository file filled from a fixture. }
function FilledRepoFile(const pFixture: string): string;
var
  vA: TFDConnection;
begin
  Result := NewPath;
  CreateRepository(Result);
  vA := OpenRepository(Result, False);
  try
    RestoreRepository(vA, TPath.Combine(GFix, pFixture), False);
  finally
    vA.Free;
  end;
end;

procedure TestFormat(const pFormat, pFixture: string);
var
  vSrc, vDst, vFile, vWant: string;
  vA, vB: TFDConnection;
begin
  vSrc := FilledRepoFile(pFixture);
  vWant := SnapshotOfFile(vSrc);
  Check(pFormat + ' ' + pFixture + ': fixture filled the source (positive control)', Length(vWant) > 500, IntToStr(Length(vWant)) + ' chars');
  vFile := TPath.Combine(GDir, 'bk-' + IntToStr(GSeq) + '.' + pFormat);
  vDst := NewPath;
  if pFormat = 'zip' then
  begin
    BackupRepositoryZip(vSrc, vFile);
    Check('zip: the archive exists and is a valid zip', TFile.Exists(vFile) and TZipFile.IsValid(vFile));
    RestoreRepositoryZip(vFile, vDst, False);
  end
  else
  begin
    vA := OpenRepository(vSrc, True);
    try
      if pFormat = 'sql' then
        BackupRepositorySql(vA, vFile)
      else
        BackupRepository(vA, vFile);
    finally
      vA.Free;
    end;
    CreateRepository(vDst);
    vB := OpenRepository(vDst, False);
    try
      if pFormat = 'sql' then
        RestoreRepositorySql(vB, vFile, False)
      else
        RestoreRepository(vB, vFile, False);
    finally
      vB.Free;
    end;
  end;
  Check(pFormat + ' ' + pFixture + ': restored repository equals the source (whole text backup)', SnapshotOfFile(vDst) = vWant);
end;

procedure TestZipRefusals;
var
  vSrc, vTarget, vBad, vBefore, vGood, vFresh: string;
  vZip: TZipFile;
  vBytes: TBytes;
begin
  vSrc := FilledRepoFile('golden.dlrepo.txt');
  vGood := TPath.Combine(GDir, 'good.zip');
  BackupRepositoryZip(vSrc, vGood);
  vTarget := FilledRepoFile('edge.dlrepo.txt');
  vBefore := SnapshotOfFile(vTarget);
  Check('zip: restore onto an existing repository without replace is refused',
    RaisedClass(procedure begin RestoreRepositoryZip(vGood, vTarget, False); end) = 'ERepoError');
  Check('zip: ... and the repository is unchanged', SnapshotOfFile(vTarget) = vBefore);
  vBad := TPath.Combine(GDir, 'truncated.zip');
  vBytes := TFile.ReadAllBytes(vGood);
  SetLength(vBytes, Length(vBytes) div 2);
  TFile.WriteAllBytes(vBad, vBytes);
  Check('zip: a truncated archive -> ERepoBackupFormatError',
    RaisedClass(procedure begin RestoreRepositoryZip(vBad, vTarget, True); end) = 'ERepoBackupFormatError');
  Check('zip: ... and the repository is unchanged', SnapshotOfFile(vTarget) = vBefore);
  vBad := TPath.Combine(GDir, 'garbage.zip');
  TFile.WriteAllText(vBad, 'this is not a zip file at all');
  Check('zip: a non-zip file -> ERepoBackupFormatError',
    RaisedClass(procedure begin RestoreRepositoryZip(vBad, vTarget, True); end) = 'ERepoBackupFormatError');
  Check('zip: a missing archive -> ERepoError',
    RaisedClass(procedure begin RestoreRepositoryZip(TPath.Combine(GDir, 'nope.zip'), vTarget, True); end) = 'ERepoError');
  vBad := TPath.Combine(GDir, 'nomarker.zip');
  vZip := TZipFile.Create;
  try
    vZip.Open(vBad, zmWrite);
    vZip.Add(vSrc, 'repository.sqlite');
    vZip.Close;
  finally
    vZip.Free;
  end;
  Check('zip: a zip without the marker entry -> ERepoBackupFormatError',
    RaisedClass(procedure begin RestoreRepositoryZip(vBad, vTarget, True); end) = 'ERepoBackupFormatError');
  vBad := TPath.Combine(GDir, 'foreign.zip');
  vZip := TZipFile.Create;
  try
    vZip.Open(vBad, zmWrite);
    vZip.Add(TEncoding.ASCII.GetBytes('DLREPO-ZIP 1' + #13#10), 'DLREPO-ZIP.txt');
    vZip.Add(TEncoding.ASCII.GetBytes('not a sqlite file, just text padding padding padding'), 'repository.sqlite');
    vZip.Close;
  finally
    vZip.Free;
  end;
  Check('zip: a marked zip whose repository entry is not a repository -> ERepoBackupFormatError',
    RaisedClass(procedure begin RestoreRepositoryZip(vBad, vTarget, True); end) = 'ERepoBackupFormatError');
  Check('zip: ... and the repository is still unchanged', SnapshotOfFile(vTarget) = vBefore);
  vFresh := TPath.Combine(GDir, 'fresh.dlrepo');
  Check('zip: a failed restore into a missing path leaves no file',
    (RaisedClass(procedure begin RestoreRepositoryZip(TPath.Combine(GDir, 'garbage.zip'), vFresh, False); end) = 'ERepoBackupFormatError')
    and not TFile.Exists(vFresh));
  Check('zip: with replace the good archive restores over the repository',
    RaisedClass(procedure begin RestoreRepositoryZip(vGood, vTarget, True); end) = '');
  Check('zip: ... and it now equals the golden source', SnapshotOfFile(vTarget) = SnapshotOfFile(vSrc));
  Check('zip: no temp file left beside the target', not TFile.Exists(vTarget + '.restoring.zip-tmp'));
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-BKZ-' + IntToStr(GetCurrentProcessId));
  if TDirectory.Exists(GDir) then
    TDirectory.Delete(GDir, True);
  TDirectory.CreateDirectory(GDir);
  GFix := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\fixtures\fieldrepo'));
  try
    TestFormat('text', 'golden.dlrepo.txt');
    TestFormat('sql', 'golden.dlrepo.txt');
    TestFormat('zip', 'golden.dlrepo.txt');
    TestFormat('text', 'edge.dlrepo.txt');
    TestFormat('sql', 'edge.dlrepo.txt');
    TestFormat('zip', 'edge.dlrepo.txt');
    TestZipRefusals;
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
