program BackupTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.54 lane ALTERBK -- console tests of the database backup (rulings R9 / R10).
  M = the manifest and the purge on plain files. H = which hosts count as this machine. L = the backup on a SCRATCH
  Firebird database this program creates with a private embedded engine (folder in DL_TEST_FB_EMBED; its firebird.conf
  allows no remote provider). Output: PASS / FAIL / SKIP lines, then "SUMMARY pass=N fail=M". Exit 0 only when fail=0. }

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.DateUtils,
  System.SyncObjs,
  System.Variants,
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
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.IBBase,
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
  DRagLint.Core.JsonFile in '..\..\src\core\DRagLint.Core.JsonFile.pas',
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.DbProvider in '..\..\src\sql\DRagLint.FieldRepo.DbProvider.pas',
  DRagLint.FieldRepo.DbProviderFb in '..\..\src\sql\DRagLint.FieldRepo.DbProviderFb.pas',
  DRagLint.FieldRepo.FbImport in '..\..\src\sql\DRagLint.FieldRepo.FbImport.pas',
  DRagLint.FieldRepo.BackupManifest in '..\..\src\sql\DRagLint.FieldRepo.BackupManifest.pas',
  DRagLint.FieldRepo.FbBackup in '..\..\src\sql\DRagLint.FieldRepo.FbBackup.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
  GFbLink: TFDPhysFBDriverLink;

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

{ The message of the exception pProc raises; '' = none. }
function Failure(const pProc: TProc): string;
begin
  Result := '';
  try
    pProc();
  except
    on E: Exception do
      Result := E.ClassName + ' ' + E.Message;
  end;
end;

{ ---- M: manifest and purge ---- }

function MakeEntry(const pName, pDatabase: string; pAgeHours: Integer; pVerified: TFrBackupVerified): TFrBackupEntry;
begin
  Result.FileName := TPath.Combine(GDir, pName);
  TFile.WriteAllText(Result.FileName, 'backup ' + pName);
  Result.Database := pDatabase;
  Result.Size := TFile.GetSize(Result.FileName);
  Result.ModifiedUtc := TFile.GetLastWriteTimeUtc(Result.FileName);
  Result.CreatedUtc := IncHour(EncodeDate(2026, 11, 23), -pAgeHours);
  Result.Verified := pVerified;
end;

function Actions(const pItems: TArray<TFrPurgeItem>): string;
var
  vItem: TFrPurgeItem;
begin
  Result := '';
  for vItem in pItems do
    Result := Result + (if Result = '' then '' else ' ') + ExtractFileName(vItem.Entry.FileName) + '=' + PURGE_ACTION_NAMES[vItem.Action];
end;

procedure TestManifest;
var
  vManifest, vBroken, vText: string;
  vA: TFrBackupEntry;
  vRead: TArray<TFrBackupEntry>;
  vTaken, vDone: TEvent;
  vHolder: TThread;
begin
  vManifest := TPath.Combine(GDir, 'list\db-backups.json');
  Check('M1 a missing list is empty', Length(ReadBackupManifest(vManifest)) = 0);
  vA := MakeEntry('m1.fbk', 'C:\db\A.FDB', 1, fbvFull);
  AddToBackupManifest(vManifest, vA);
  AddToBackupManifest(vManifest, MakeEntry('m2.fbk', 'C:\db\A.FDB', 0, fbvFailed));
  vRead := ReadBackupManifest(vManifest);
  Check('M2 round trip', (Length(vRead) = 2) and (vRead[0].FileName = vA.FileName) and (vRead[0].Database = vA.Database) and (vRead[0].Size = vA.Size) and
    (vRead[0].Verified = fbvFull) and (vRead[1].Verified = fbvFailed) and SameDateTime(vRead[0].CreatedUtc, vA.CreatedUtc) and (BackupFileState(vRead[0]) = ffsMatch));
  TFile.AppendAllText(vRead[1].FileName, 'x');
  Check('M3 another size = changed', BackupFileState(vRead[1]) = ffsChanged);
  TFile.SetLastWriteTimeUtc(vA.FileName, IncSecond(vA.ModifiedUtc, 1));
  Check('M3b same size, another date = changed', BackupFileState(vRead[0]) = ffsChanged);
  TFile.SetLastWriteTimeUtc(vA.FileName, vA.ModifiedUtc);
  Check('M3c control: date put back = ok', BackupFileState(vRead[0]) = ffsMatch);
  TFile.Delete(vA.FileName);
  Check('M3d gone = missing', BackupFileState(vRead[0]) = ffsMissing);
  vBroken := TPath.Combine(GDir, 'broken.json');
  for vText in ['not json', '{"backups":5}', '{"backups":[{"file":"x"}]}', '{"backups":[{"file":"x","database":"d","size":1,"modified_utc":"2026-01-01T00:00:00.000Z",' +
    '"created_utc":"2026-01-01T00:00:00.000Z","verified":"maybe"}]}'] do
  begin
    TFile.WriteAllText(vBroken, vText);
    Check('M4 a malformed list is refused and kept: ' + Copy(vText, 1, 30), Failure(procedure begin AddToBackupManifest(vBroken, vA) end).Contains('not readable') and
      (TFile.ReadAllText(vBroken) = vText));
  end;
  { another thread stands for another process: a mutex belongs to a thread }
  vTaken := TEvent.Create(nil, True, False, '');
  vDone := TEvent.Create(nil, True, False, '');
  vHolder := TThread.CreateAnonymousThread(procedure
    var
      vLock: TMutex;
    begin
      vLock := TMutex.Create(nil, True, BackupManifestLockName(vManifest));
      vTaken.SetEvent;
      vDone.WaitFor(INFINITE);
      vLock.Release;
      vLock.Free;
    end);
  vHolder.FreeOnTerminate := False;
  vHolder.Start;
  try
    vTaken.WaitFor(INFINITE);
    Check('M5 a locked list is an error, not a lost entry', Failure(procedure begin AddToBackupManifest(vManifest, vA) end).Contains('in use'));
  finally
    vDone.SetEvent;
    vHolder.WaitFor;
    vHolder.Free;
    vTaken.Free;
    vDone.Free;
  end;
  AddToBackupManifest(vManifest, vA);
  Check('M5c control: unlocked it takes the entry', Length(ReadBackupManifest(vManifest)) = 3);
end;

procedure TestPurge;
var
  vManifest, vForeign, vBefore: string;
  vEntries: TArray<TFrBackupEntry>;
  vItems: TArray<TFrPurgeItem>;
  vFiles: Integer;
  vHeld: TFileStream;

  procedure Save;
  var
    vEntry: TFrBackupEntry;
  begin
    if TFile.Exists(vManifest) then
      TFile.Delete(vManifest);
    for vEntry in vEntries do
      AddToBackupManifest(vManifest, vEntry);
  end;

begin
  vManifest := TPath.Combine(GDir, 'purge.json');
  vForeign := TPath.Combine(GDir, 'foreign.fbk');
  TFile.WriteAllText(vForeign, 'not in the list');
  vEntries := [MakeEntry('a1.fbk', 'A', 1, fbvQuick), MakeEntry('a2.fbk', 'A', 2, fbvQuick), MakeEntry('a3.fbk', 'A', 3, fbvFull), MakeEntry('a4.fbk', 'A', 4, fbvFull),
    MakeEntry('b1.fbk', 'B', 9, fbvFull), MakeEntry('a0.fbk', 'A', 0, fbvFailed)];
  Check('P1 keep 1: newest, the newest verified one, per database; a failed one never counts',
    Actions(PlanBackupPurge(vEntries, 1)) = 'a0.fbk=delete a1.fbk=keep a2.fbk=delete a3.fbk=keep a4.fbk=delete b1.fbk=keep', Actions(PlanBackupPurge(vEntries, 1)));
  Check('P2 keep 3', Actions(PlanBackupPurge(vEntries, 3)) = 'a0.fbk=delete a1.fbk=keep a2.fbk=keep a3.fbk=keep a4.fbk=delete b1.fbk=keep', Actions(PlanBackupPurge(vEntries, 3)));
  Check('P3 keep 0 is refused', Failure(procedure begin PlanBackupPurge(vEntries, 0) end).Contains('--keep'));
  Save;
  vBefore := TFile.ReadAllText(vManifest);
  vItems := PurgeBackups(vManifest, 1, False);
  Check('P4 a dry run deletes nothing and keeps the list', (Length(vItems) = 6) and TFile.Exists(vEntries[1].FileName) and (TFile.ReadAllText(vManifest) = vBefore));
  { a2 was modified, a4 is gone, a3 (the newest verified) was modified: the next verified one must then stay }
  TFile.WriteAllText(vEntries[1].FileName, 'edited by somebody');
  TFile.AppendAllText(vEntries[2].FileName, '!');
  vItems := PurgeBackups(vManifest, 1, False);
  Check('P5 a modified file is skipped and does not count as the newest verified one',
    Actions(vItems) = 'a0.fbk=delete a1.fbk=keep a2.fbk=skip a3.fbk=skip a4.fbk=keep b1.fbk=keep', Actions(vItems));
  vItems := PurgeBackups(vManifest, 1, True);
  Check('P6 apply deletes only what the plan said', not TFile.Exists(vEntries[5].FileName) and TFile.Exists(vEntries[0].FileName) and TFile.Exists(vEntries[1].FileName) and
    TFile.Exists(vEntries[2].FileName) and TFile.Exists(vEntries[3].FileName) and TFile.Exists(vEntries[4].FileName), Actions(vItems));
  Check('P6b a file that is not in the list is never touched', TFile.Exists(vForeign));
  Check('P6c the deleted entry left the list, the skipped ones stay in it', Length(ReadBackupManifest(vManifest)) = 5);
  { a deletion that fails }
  vEntries := [MakeEntry('c1.fbk', 'C', 1, fbvFull), MakeEntry('c2.fbk', 'C', 2, fbvFull), MakeEntry('c3.fbk', 'C', 3, fbvFull)];
  Save;
  TFile.Delete(vEntries[2].FileName);
  vHeld := TFileStream.Create(vEntries[1].FileName, fmOpenRead or fmShareDenyWrite);
  try
    vItems := PurgeBackups(vManifest, 1, True);
  finally
    vHeld.Free;
  end;
  Check('P7 a file in use stays, its entry too; the entry of a missing file goes', (Actions(vItems) = 'c1.fbk=keep c2.fbk=delete c3.fbk=forget') and (vItems[1].Error <> '') and
    TFile.Exists(vEntries[1].FileName) and (Length(ReadBackupManifest(vManifest)) = 2), Actions(vItems) + ' ' + vItems[1].Error);
  vItems := PurgeBackups(vManifest, 1, True);
  Check('P7c control: released it is deleted', not TFile.Exists(vEntries[1].FileName) and (Length(ReadBackupManifest(vManifest)) = 1));
  Check('P8 the total counts only files that are as recorded', (TotalBackupSize(vEntries, vFiles) = vEntries[0].Size) and (vFiles = 1));
end;

{ ---- H: hosts ---- }

procedure TestHosts;

  procedure Host(const pConnection, pExpect: string);
  begin
    Check('H ' + pConnection + ' -> "' + pExpect + '"', RemoteFbHost(pConnection) = pExpect, RemoteFbHost(pConnection));
  end;

begin
  Host('Database=C:\db\x.fdb', '');
  Host('Database=x_alias', '');
  Host('Database=localhost:C:\db\x.fdb', '');
  Host('Database=LocalHost/3051:C:\db\x.fdb', '');
  Host('Server=127.0.0.1;Database=C:\db\x.fdb', '');
  Host('Protocol=TCPIP;Database=C:\db\x.fdb', '');
  Host('Protocol=Local;Database=C:\db\x.fdb', '');
  Host('Database=xnet://C:\db\x.fdb', '');
  Host('Database=inet://localhost:3050/C:\db\x.fdb', '');
  Host('Server=' + GetEnvironmentVariable('COMPUTERNAME') + ';Database=x', '');
  Host('Database=srv:C:\db\x.fdb', 'srv');
  Host('Database=srv/3051:/data/x.fdb', 'srv');
  Host('Server=srv;Database=C:\db\x.fdb', 'srv');
  Host('server = srv/3052 ; Database=C:\db\x.fdb', 'srv');
  Host('Database=inet4://srv:3050/x', 'srv');
  Host('Database=wnet://srv/x', 'wnet');
  Host('Database=\\srv\c$\x.fdb', '\\srv');
  Host('Protocol=NetBEUI;Server=localhost;Database=x', 'NetBEUI');
end;

{ ---- L: live ---- }

function ScratchConn: string;
begin
  Result := 'DriverID=FB;Database=' + TPath.Combine(GDir, 'scratch.fdb') + ';User_Name=SYSDBA;Password=unused';
end;

procedure MakeScratch;
var
  vConn: TFDConnection;
begin
  vConn := TFDConnection.Create(nil);
  try
    vConn.LoginPrompt := False;
    vConn.Params.Text := StringReplace(ScratchConn, ';', sLineBreak, [rfReplaceAll]) + sLineBreak + 'CharacterSet=UTF8' + sLineBreak + 'OpenMode=Create' + sLineBreak +
      'PageSize=8192' + sLineBreak + 'SQLDialect=3';
    vConn.Open;
    vConn.ExecSQL('CREATE TABLE T (ID INTEGER, A VARCHAR(10))');
    vConn.ExecSQL('CREATE VIEW V AS SELECT A FROM T');
    vConn.ExecSQL('INSERT INTO T VALUES (1, ''a'')');
    vConn.ExecSQL('INSERT INTO T VALUES (2, ''b'')');
  finally
    vConn.Free;
  end;
end;

procedure RunSql(const pSql: string);
var
  vConn: TFDConnection;
  vDatabase: string;
begin
  vConn := OpenSourceConnection(ScratchConn, vDatabase);
  try
    vConn.ExecSQL(pSql);
  finally
    vConn.Free;
  end;
end;

function Files(const pDir, pMask: string): Integer;
begin
  Result := if TDirectory.Exists(pDir) then Length(TDirectory.GetFiles(pDir, pMask)) else 0;
end;

procedure TestLive;
var
  vEmbed, vManifest, vDir, vFail, vName: string;
  vReq: TFrBackupRequest;
  vRes: TFrBackupResult;
  vNeed: Int64;
  vHeld: IFrDbProvider;

  function Request(const pSub: string; pVerify: TFrVerifyMode = fvmFull): TFrBackupRequest;
  begin
    Result := Default(TFrBackupRequest);
    Result.Connection := ScratchConn;
    Result.BackupDir := TPath.Combine(GDir, pSub);
    Result.TableName := 'T';
    Result.Verify := pVerify;
    vDir := Result.BackupDir;
  end;

  function Fails: string;
  begin
    Result := Failure(procedure begin BackupFbDatabase(vReq, vManifest) end);
  end;

  function Clean: Boolean;
  begin
    Result := (Files(vDir, 'drag-lint-verify-*') = 0) and (Length(ReadBackupManifest(vManifest)) = 0);
  end;

  procedure Fresh(const pSub: string);
  begin
    vManifest := TPath.Combine(GDir, pSub + '.json');
    vReq := Request(pSub);
  end;

begin
  vEmbed := GetEnvironmentVariable('DL_TEST_FB_EMBED');
  if (vEmbed = '') or not TFile.Exists(TPath.Combine(vEmbed, 'fbclient.dll')) then
  begin
    Writeln('SKIP L no private embedded Firebird (DL_TEST_FB_EMBED)');
    Exit;
  end;
  Check('L0 the private engine allows no remote provider', TFile.ReadAllText(TPath.Combine(vEmbed, 'firebird.conf')).Contains('Providers = Engine13'));
  GFbLink := TFDPhysFBDriverLink.Create(nil);
  GFbLink.VendorLib := TPath.Combine(vEmbed, 'fbclient.dll');
  MakeScratch;
  { full, with another attachment of this process open, as alter-table has one }
  Fresh('full');
  vHeld := OpenFirebirdProvider(ScratchConn);
  vRes := BackupFbDatabase(vReq, vManifest);
  vHeld := nil;
  vName := ExtractFileName(vRes.Entry.FileName);
  Check('L1 full: the file is there, verified, two relations and two rows compared', TFile.Exists(vRes.Entry.FileName) and (vRes.Entry.Verified = fbvFull) and
    (vRes.Tables = 2) and (vRes.Rows = 2) and (vRes.Leftover = '') and (vRes.Entry.Size = TFile.GetSize(vRes.Entry.FileName)));
  Check('L1b the name carries the database and a timestamp', vName.StartsWith('scratch-', True) and vName.Contains(FormatDateTime('yyyymmdd', Now)) and vName.EndsWith('.fbk'), vName);
  Check('L1c only the backup is left in the folder', (Files(vDir, '*') = 1) and (Files(vDir, 'drag-lint-verify-*') = 0));
  Check('L1d it is recorded', (Length(ReadBackupManifest(vManifest)) = 1) and (BackupFileState(ReadBackupManifest(vManifest)[0]) = ffsMatch) and
    SameText(ExtractFileName(ReadBackupManifest(vManifest)[0].Database), 'scratch.fdb'));
  Check('L1e the source is untouched', TFile.Exists(TPath.Combine(GDir, 'scratch.fdb')));
  vReq.Verify := fvmQuick;
  vReq.TableName := '';
  vRes := BackupFbDatabase(vReq, vManifest);
  Check('L2 quick: written, nothing compared, a second entry', (vRes.Entry.Verified = fbvQuick) and (vRes.Tables = 0) and (vRes.Rows = -1) and (Files(vDir, '*.fbk') = 2) and
    (Length(ReadBackupManifest(vManifest)) = 2));
  vReq.BackupDir := '';
  vRes := BackupFbDatabase(vReq, vManifest);
  Check('L2b no folder given: beside the database', SameText(ExtractFilePath(vRes.Entry.FileName), IncludeTrailingPathDelimiter(GDir)), vRes.Entry.FileName);
  { space }
  Fresh('space');
  vNeed := 0;
  vReq.FreeSpace := function(pDir: string): Int64 begin Result := 0 end;
  vFail := Fails;
  Check('L3 no space: refused before the backup', vFail.Contains('not enough space') and (Files(vDir, '*') = 0) and Clean, vFail);
  vNeed := TFile.GetSize(TPath.Combine(GDir, 'scratch.fdb'));
  vReq.FreeSpace := function(pDir: string): Int64 begin Result := vNeed * 2 end;
  vFail := Fails;
  Check('L3b twice the database is not enough for a restore test', vFail.Contains('--verify quick'), vFail);
  vReq.Verify := fvmQuick;
  Check('L3c control: it is for --verify quick', Fails = '', Fails);
  vReq := Request('space');
  vReq.FreeSpace := function(pDir: string): Int64 begin Result := vNeed * 3 end;
  Check('L3d control: three times is for both', Fails = '', Fails);
  { verification }
  Fresh('rows');
  vReq.BeforeBackup := procedure(pFile: string) begin RunSql('INSERT INTO T VALUES (3, ''c'')') end;
  vFail := Fails;
  Check('L4 another row count: refused, recorded as failed, the temporary database is gone', vFail.Contains('has 3 row(s)') and (Files(vDir, 'drag-lint-verify-*') = 0) and
    (Length(ReadBackupManifest(vManifest)) = 1) and (ReadBackupManifest(vManifest)[0].Verified = fbvFailed), vFail);
  Fresh('list');
  vReq.BeforeBackup := procedure(pFile: string) begin RunSql('CREATE TABLE T2 (ID INTEGER)') end;
  vFail := Fails;
  Check('L4b another table list: refused', vFail.Contains('another table list') and (Files(vDir, 'drag-lint-verify-*') = 0), vFail);
  Fresh('corrupt');
  vReq.AfterBackup := procedure(pFile: string)
    var
      vBytes: TBytes;
    begin
      vBytes := TFile.ReadAllBytes(pFile);
      SetLength(vBytes, Length(vBytes) div 2);
      TFile.WriteAllBytes(pFile, vBytes);
    end;
  vFail := Fails;
  Check('L4c a damaged backup does not restore: refused, the temporary database is gone', vFail.Contains('verification failed') and (Files(vDir, 'drag-lint-verify-*') = 0) and
    (Files(vDir, '*.fdb') = 0), vFail + ' ' + IntToStr(Files(vDir, '*')));
  Fresh('corrupt2');
  vReq.Verify := fvmQuick;
  Check('L4d control: without interference the same request succeeds', Fails = '', Fails);
  vReq := Request('corrupt2');
  Check('L4e and with the restore test', Fails = '', Fails);
  { the backup itself fails }
  Fresh('gone');
  vReq.BeforeBackup := procedure(pFile: string) begin TDirectory.Delete(ExtractFilePath(pFile)) end;
  vFail := Fails;
  Check('L5 Firebird cannot write the file: refused, nothing recorded', (vFail <> '') and not vFail.Contains('verification') and Clean, vFail);
  Fresh('taken');
  vReq.BeforeBackup := procedure(pFile: string) begin TFile.WriteAllText(pFile, 'somebody else''s') end;
  vFail := Fails;
  Check('L5b an existing file is never overwritten', vFail.Contains('exists already') and (TFile.ReadAllText(TDirectory.GetFiles(vDir)[0]) = 'somebody else''s') and Clean, vFail);
  { refusals before anything is opened or written }
  Fresh('refuse');
  vReq.TableName := 'NOPE';
  vFail := Fails;
  Check('L6 an unknown table: refused before the backup', vFail.Contains('NOPE') and (Files(vDir, '*') = 0) and Clean, vFail);
  vReq := Request('refuse');
  vReq.Connection := 'DriverID=FB;Database=srv:C:\x.fdb;User_Name=SYSDBA;Password=pw';
  vFail := Fails;
  Check('L6b another machine: refused', vFail.Contains('not on this machine (srv)') and not vFail.Contains('pw'), vFail);
  vReq.Connection := ScratchConn + ';DropDatabase=Yes';
  Check('L6c DropDatabase in the connection string: refused', Fails.Contains('DropDatabase'));
  vReq := Request('a=b');
  Check('L6d a folder with = in its name: refused', Fails.Contains('"="'));
  vReq := Request('file.txt');
  TFile.WriteAllText(vDir, 'x');
  Check('L6e a folder that is a file: refused', Fails.Contains('is a file'), Fails);
  Fresh('badlist');
  TFile.WriteAllText(vManifest, 'no list');
  Check('L6f a list that cannot be read: refused before the backup', Fails.Contains('not readable') and (Files(vDir, '*') = 0), Fails);
  Check('L7 after all of it the source is still a database with its rows', VarToStr(OpenFirebirdProvider(ScratchConn).ReadScalar('SELECT COUNT(*) FROM T')) = '3');
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-backup-tests-' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(GDir);
  try
    try
      TestManifest;
      TestPurge;
      TestHosts;
      TestLive;
    except
      on E: Exception do
      begin
        Inc(GFail);
        Writeln('FAIL EXCEPTION ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    GFbLink.Free;
    try
      TDirectory.Delete(GDir, True);
    except
      on E: Exception do
        Writeln('note: scratch folder kept: ', GDir);
    end;
  end;
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  ExitCode := if GFail = 0 then 0 else 1;
end.
