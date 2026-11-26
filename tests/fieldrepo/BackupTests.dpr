program BackupTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.54 lane ALTERBK -- console tests of the database backup (rulings R9 / R10).
  M = the manifest and the purge on plain files. H = which hosts count as this machine. L = the backup on a SCRATCH
  Firebird database this program creates with a private embedded engine (folder in DL_TEST_FB_EMBED; its firebird.conf
  allows no remote provider). Output: PASS / FAIL / SKIP lines, then "SUMMARY pass=N fail=M". Exit 0 only when fail=0. }

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
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
  DRagLint.FieldRepo.ChangeSet in '..\..\src\sql\DRagLint.FieldRepo.ChangeSet.pas',
  DRagLint.FieldRepo.AlterReport in '..\..\src\sql\DRagLint.FieldRepo.AlterReport.pas',
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

procedure MakeJunction(const pLink, pTarget: string);
var
  vInfo: TStartupInfo;
  vProc: TProcessInformation;
  vLine: string;
begin
  vLine := Format('cmd.exe /c mklink /J "%s" "%s" >nul', [pLink, ExcludeTrailingPathDelimiter(pTarget)]);
  UniqueString(vLine);
  vInfo := Default(TStartupInfo);
  vInfo.cb := SizeOf(vInfo);
  Win32Check(CreateProcess(nil, PChar(vLine), nil, nil, False, CREATE_NO_WINDOW, nil, nil, vInfo, vProc));
  WaitForSingleObject(vProc.hProcess, INFINITE);
  CloseHandle(vProc.hThread);
  CloseHandle(vProc.hProcess);
  if not TDirectory.Exists(pLink) then
    raise Exception.Create('no junction: ' + pLink);
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

{ One backup of a database; its folder is the label the checks print. }
function MakeEntry(const pName, pDatabase: string; pAgeHours: Integer; pVerified: TFrBackupVerified): TFrBackupEntry;
begin
  Result := Default(TFrBackupEntry);
  Result.FileName := TPath.Combine(TPath.Combine(GDir, pName), ChangeFileExt(ExtractFileName(pDatabase), '') + '-20261123-101112000.fbk');
  TDirectory.CreateDirectory(ExtractFilePath(Result.FileName));
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
    Result := Result + (if Result = '' then '' else ' ') + ExtractFileName(ExtractFileDir(vItem.Entry.FileName)) + '=' + PURGE_ACTION_NAMES[vItem.Action];
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
  vText := '{"version":2,"backups":[]}';
  TFile.WriteAllText(vBroken, vText);
  Check('M4b a list of a newer version is refused and kept', Failure(procedure begin AddToBackupManifest(vBroken, vA) end).Contains('newer drag-lint') and
    (TFile.ReadAllText(vBroken) = vText));
  TFile.WriteAllText(vBroken, '{"version":1,"backups":[]}');
  Check('M4c control: this version is read', Length(ReadBackupManifest(vBroken)) = 0);
  Check('M4d the lock is one for every Windows session', BackupManifestLockName(vManifest).StartsWith('Global\'));
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
  vManifest, vForeign, vBefore, vFailure: string;
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
  Check('P1 keep 1: the newest one, the newest not failed one, the newest verified one, per database',
    Actions(PlanBackupPurge(vEntries, 1)) = 'a0.fbk=keep a1.fbk=keep a2.fbk=delete a3.fbk=keep a4.fbk=delete b1.fbk=keep', Actions(PlanBackupPurge(vEntries, 1)));
  Check('P2 keep 3: unverified ones do not use up the number of verified ones',
    Actions(PlanBackupPurge(vEntries, 3)) = 'a0.fbk=keep a1.fbk=keep a2.fbk=keep a3.fbk=keep a4.fbk=keep b1.fbk=keep', Actions(PlanBackupPurge(vEntries, 3)));
  vEntries[5].CreatedUtc := IncHour(vEntries[5].CreatedUtc, -8);
  Check('P2b a failed one that is not the newest goes when there is a verified one',
    Actions(PlanBackupPurge(vEntries, 3)) = 'a1.fbk=keep a2.fbk=keep a3.fbk=keep a4.fbk=keep a0.fbk=delete b1.fbk=keep', Actions(PlanBackupPurge(vEntries, 3)));
  vEntries[5].CreatedUtc := IncHour(vEntries[5].CreatedUtc, 8);
  Check('P3 keep 0 is refused', Failure(procedure begin PlanBackupPurge(vEntries, 0) end).Contains('--keep'));
  vEntries[5].CreatedUtc := IncHour(vEntries[5].CreatedUtc, -8);
  Save;
  vBefore := TFile.ReadAllText(vManifest);
  vItems := PurgeBackups(vManifest, 'A', 1, False);
  Check('P4 a dry run deletes nothing and keeps the list', (Length(vItems) = 5) and TFile.Exists(vEntries[1].FileName) and (TFile.ReadAllText(vManifest) = vBefore));
  { a2 was modified, a4 is gone, a3 (the newest verified) was modified: the next verified one must then stay }
  TFile.WriteAllText(vEntries[1].FileName, 'edited by somebody');
  TFile.AppendAllText(vEntries[2].FileName, '!');
  vItems := PurgeBackups(vManifest, 'A', 1, False);
  Check('P5 a modified file is skipped and does not count as the newest verified one',
    Actions(vItems) = 'a1.fbk=keep a2.fbk=skip a3.fbk=skip a4.fbk=keep a0.fbk=delete', Actions(vItems));
  vFailure := Failure(procedure begin PurgeBackups(vManifest, '', 1, True) end);
  Check('P6z without a database an apply is refused and nothing is deleted', vFailure.Contains('--connection') and TFile.Exists(vEntries[5].FileName) and
    (TFile.ReadAllText(vManifest) = vBefore), vFailure);
  vEntries := vEntries + [MakeEntry('b2.fbk', 'B', 10, fbvFull)];
  AddToBackupManifest(vManifest, vEntries[6]);
  vItems := PurgeBackups(vManifest, '', 1, False);
  Check('P6y control: the plan over every database wants that backup of another database, too', Actions(vItems).EndsWith('b1.fbk=keep b2.fbk=delete'), Actions(vItems));
  vItems := PurgeBackups(vManifest, 'a', 1, True);
  Check('P6x M2: the backups of another database stay', TFile.Exists(vEntries[6].FileName) and not Actions(vItems).Contains('b2'), Actions(vItems));
  Check('P6 apply deletes only what the plan said', not TFile.Exists(vEntries[5].FileName) and TFile.Exists(vEntries[0].FileName) and TFile.Exists(vEntries[1].FileName) and
    TFile.Exists(vEntries[2].FileName) and TFile.Exists(vEntries[3].FileName) and TFile.Exists(vEntries[4].FileName), Actions(vItems));
  Check('P6b a file that is not in the list is never touched', TFile.Exists(vForeign));
  Check('P6c the deleted entry left the list, the skipped ones stay in it', Length(ReadBackupManifest(vManifest)) = 6);
  { a deletion that fails }
  vEntries := [MakeEntry('c1.fbk', 'C', 1, fbvFull), MakeEntry('c2.fbk', 'C', 2, fbvFull), MakeEntry('c3.fbk', 'C', 3, fbvFull)];
  Save;
  TFile.Delete(vEntries[2].FileName);
  vHeld := TFileStream.Create(vEntries[1].FileName, fmOpenRead or fmShareDenyWrite);
  try
    vItems := PurgeBackups(vManifest, 'C', 1, True);
  finally
    vHeld.Free;
  end;
  Check('P7 a file in use stays, its entry too; the entry of a missing file goes', (Actions(vItems) = 'c1.fbk=keep c2.fbk=delete c3.fbk=forget') and (vItems[1].Error <> '') and
    TFile.Exists(vEntries[1].FileName) and (Length(ReadBackupManifest(vManifest)) = 2), Actions(vItems) + ' ' + vItems[1].Error);
  vItems := PurgeBackups(vManifest, 'C', 1, True);
  Check('P7c control: released it is deleted', not TFile.Exists(vEntries[1].FileName) and (Length(ReadBackupManifest(vManifest)) = 1));
  Check('P8 the total counts only files that are as recorded', (TotalBackupSize(vEntries, vFiles) = vEntries[0].Size) and (vFiles = 1));
end;

{ M3: the last backup of a database is never purged, whatever its state }
procedure TestPurgeLast;

  procedure Plan(const pName, pExpect: string; const pEntries: TArray<TFrBackupEntry>);
  begin
    Check('Q ' + pName, Actions(PlanBackupPurge(pEntries, 1)) = pExpect, Actions(PlanBackupPurge(pEntries, 1)));
  end;

begin
  Plan('the only backup failed its verification: kept', 'q1=keep', [MakeEntry('q1', 'A', 1, fbvFailed)]);
  Plan('only failed ones: the newest is kept', 'q1=keep q2=delete', [MakeEntry('q1', 'A', 1, fbvFailed), MakeEntry('q2', 'A', 2, fbvFailed)]);
  Plan('no verified one: the newest failed one stays beside the unverified one', 'q1=keep q2=keep q3=delete',
    [MakeEntry('q1', 'A', 1, fbvQuick), MakeEntry('q2', 'A', 2, fbvFailed), MakeEntry('q3', 'A', 3, fbvFailed)]);
  Plan('the newest one is kept though it failed, the last verified one too', 'q1=keep q2=keep q3=delete',
    [MakeEntry('q1', 'A', 1, fbvFailed), MakeEntry('q2', 'A', 2, fbvFull), MakeEntry('q3', 'A', 3, fbvFailed)]);
  Plan('control: an old failed one goes', 'q1=keep q2=delete', [MakeEntry('q1', 'A', 1, fbvFull), MakeEntry('q2', 'A', 2, fbvFailed)]);
end;

function ShortName(const pFile: string): string;
begin
  SetLength(Result, MAX_PATH);
  SetLength(Result, GetShortPathName(PChar(ExtractFileDir(pFile)), PChar(Result), MAX_PATH));
  Result := IncludeTrailingPathDelimiter(Result) + ExtractFileName(pFile);
end;

{ M4: the file is checked again right before it is deleted }
procedure TestPurgeSwap;
var
  vManifest: string;
  vNew, vOld: TFrBackupEntry;
  vSeq: Integer;

  procedure Swapped(const pName: string; const pSwap: TProc<string>; const pExpect: string = 'skip');
  var
    vItems: TArray<TFrPurgeItem>;
    vCalls: Integer;
  begin
    Inc(vSeq);
    vManifest := TPath.Combine(GDir, Format('swap%d.json', [vSeq]));
    vNew := MakeEntry(Format('s%da', [vSeq]), 'S', 1, fbvFull);
    vOld := MakeEntry(Format('s%db', [vSeq]), 'S', 2, fbvFull);
    AddToBackupManifest(vManifest, vNew);
    AddToBackupManifest(vManifest, vOld);
    vCalls := 0;
    vItems := PurgeBackups(vManifest, 'S', 1, True, procedure(pFile: string)
      begin
        Inc(vCalls);
        if Assigned(pSwap) then
          pSwap(pFile);
      end);
    Check('S ' + pName, (vCalls = 1) and (Length(vItems) = 2) and (PURGE_ACTION_NAMES[vItems[1].Action] = pExpect) and (vItems[1].Error = '') and
      (Length(ReadBackupManifest(vManifest)) = (if pExpect = 'skip' then 2 else 1)), Actions(vItems) + ' ' + vItems[1].Reason + ' ' + vItems[1].Error);
  end;

begin
  vSeq := 0;
  Swapped('control: nothing happens in between, the file is deleted', nil, 'delete');
  Check('S1b and gone', not TFile.Exists(vOld.FileName));
  Swapped('other content, another size', procedure(pFile: string) begin TFile.WriteAllText(pFile, 'somebody else''s file') end);
  Check('S2b that file is still there', TFile.ReadAllText(vOld.FileName) = 'somebody else''s file');
  Swapped('same size, another date', procedure(pFile: string) begin TFile.SetLastWriteTimeUtc(pFile, IncMinute(Now, -90)) end);
  Check('S3b still there', TFile.Exists(vOld.FileName));
  Swapped('the file is gone', procedure(pFile: string) begin TFile.Delete(pFile) end);
  Swapped('its folder is now a junction to a folder with a file of that name, size and date',
    procedure(pFile: string)
    var
      vDir: string;
    begin
      vDir := ExtractFileDir(pFile);
      TDirectory.Move(vDir, vDir + '-real');
      MakeJunction(vDir, vDir + '-real');
    end);
  Check('S5b the file behind the junction is still there', TFile.Exists(ExtractFileDir(vOld.FileName) + '-real\' + ExtractFileName(vOld.FileName)));
  RemoveDir(ExtractFileDir(vOld.FileName));
end;

{ Q10 = B (1.55): a backup of a server on another machine is allowed, written on its disk, never restore-tested, never purged }
function MakeAlterBackup(const pVerified: string): TFrAlterBackup;
begin
  Result := Default(TFrAlterBackup);
  Result.FileName := '/srv/x.fbk';
  Result.Verified := pVerified;
  Result.Host := 'srv.invalid';
end;

procedure TestRemote;
const
  REMOTE = 'Server=srv.invalid;Database=C:\x.fdb;User_Name=SYSDBA;Password=pw';
  LOCAL = 'Database=C:\x.fdb;User_Name=SYSDBA;Password=pw';
var
  vKeep, vRemote: TFrBackupEntry;
  vManifest, vText: string;
  vItem: TFrPurgeItem;
  vRead: TArray<TFrBackupEntry>;
  vFiles: Integer;
begin
  Check('Q1 a remote server with the restore test is refused before anything is opened, naming --verify quick',
    RemoteVerifyProblem(REMOTE, fvmFull).Contains('--verify quick') and RemoteVerifyProblem(REMOTE, fvmFull).Contains('srv.invalid'), RemoteVerifyProblem(REMOTE, fvmFull));
  Check('Q1b a remote server with --verify quick, and a local one either way, are not', (RemoteVerifyProblem(REMOTE, fvmQuick) = '') and
    (RemoteVerifyProblem(LOCAL, fvmFull) = '') and (RemoteVerifyProblem(LOCAL, fvmQuick) = '') and
    (RemoteVerifyProblem('Server=' + GetEnvironmentVariable('COMPUTERNAME') + ';Database=C:\x.fdb;User_Name=SYSDBA', fvmFull) = ''));
  Check('Q2 server paths: Windows, Unix, with a folder', (ServerBackupFile('C:\db\A.FDB', '', 'x.fbk') = 'C:\db\x.fbk') and (ServerBackupFile('/srv/db/a.fdb', '', 'x.fbk') = '/srv/db/x.fbk') and
    (ServerBackupFile('C:\db\A.FDB', 'D:\bk\', 'x.fbk') = 'D:\bk\x.fbk') and (ServerBackupFile('/srv/db/a.fdb', '/bk', 'x.fbk') = '/bk/x.fbk'),
    ServerBackupFile('C:\db\A.FDB', '', 'x.fbk') + ' ' + ServerBackupFile('/srv/db/a.fdb', '', 'x.fbk'));
  Check('Q1c --backup-name with a remote server is refused, naming the host and the automatic name; local and no name are not', RemoteNameProblem(REMOTE, 'mine').Contains('srv.invalid') and
    RemoteNameProblem(REMOTE, 'mine').Contains('automatic') and (RemoteNameProblem(REMOTE, '') = '') and (RemoteNameProblem(LOCAL, 'mine') = ''), RemoteNameProblem(REMOTE, 'mine'));
  Check('Q1d a remote backup is a state of its own, not quick, named not verified', (fbvRemote <> fbvQuick) and VERIFIED_NAMES[fbvRemote].Contains('not verified') and (RenderBackupText(MakeAlterBackup(VERIFIED_NAMES[fbvRemote]))[0].Contains('NOT verified')) and
    not RenderBackupText(MakeAlterBackup(VERIFIED_NAMES[fbvRemote]))[0].Contains('verified quick'), RenderBackupText(MakeAlterBackup(VERIFIED_NAMES[fbvRemote]))[0]);
  vKeep := MakeEntry('q-keep', 'C:\db\A.FDB', 1, fbvFull);
  vRemote := Default(TFrBackupEntry);
  vRemote.FileName := '/srv/db/DLFR_BACKUP_A_20261126_090807.fbk';
  vRemote.Database := 'C:\db\A.FDB';
  vRemote.Host := 'srv.invalid';
  vRemote.CreatedUtc := IncHour(EncodeDate(2026, 11, 23), -5);
  vRemote.Verified := fbvRemote;
  Check('Q3 a remote entry reads as remote, though no such file is here', BackupFileState(vRemote) = ffsRemote);
  vText := '(none)';
  for vItem in PlanBackupPurge([vKeep, vRemote], 1) do
    if vItem.Entry.FileName = vRemote.FileName then
      vText := PURGE_ACTION_NAMES[vItem.Action] + ' ' + vItem.Reason;
  Check('Q3b purge never deletes it, and says why', vText.StartsWith('skip ') and vText.Contains('srv.invalid') and vText.Contains('never deletes'), vText);
  vManifest := TPath.Combine(GDir, 'q.json');
  AddToBackupManifest(vManifest, vRemote);
  AddToBackupManifest(vManifest, vKeep);
  vRead := ReadBackupManifest(vManifest);
  Check('Q4 the host survives the list; a local entry has none', (Length(vRead) = 2) and (vRead[0].Host = 'srv.invalid') and (vRead[1].Host = '') and
    TFile.ReadAllText(vManifest).Contains('"host"'));
  TotalBackupSize(vRead, vFiles);
  Check('Q4b a remote entry is not counted among the files on disk', vFiles = 1, IntToStr(vFiles));
end;
{ BKNAME (1.55): the new default name, --backup-name, and what a purge recognises }
procedure TestNames;
var
  vDir, vFile, vProblem, vResolved: string;
  vOld, vEntry, vKeep: TFrBackupEntry;
  vManifest: string;
  vRead: TArray<TFrBackupEntry>;

  function PlanOf(const pEntry: TFrBackupEntry): string;
  var
    vItem: TFrPurgeItem;
  begin
    Result := '(none)';
    for vItem in PlanBackupPurge([vKeep, pEntry], 1) do
      if vItem.Entry.FileName = pEntry.FileName then
        Result := PURGE_ACTION_NAMES[vItem.Action] + ' ' + vItem.Reason;
  end;

  { an entry whose file is vDir\pName, older than vKeep }
  function Named(const pName: string; pNamed: Boolean): TFrBackupEntry;
  begin
    Result := vOld;
    Result.FileName := TPath.Combine(vDir, pName);
    TFile.WriteAllText(Result.FileName, 'x');
    Result.Size := TFile.GetSize(Result.FileName);
    Result.ModifiedUtc := TFile.GetLastWriteTimeUtc(Result.FileName);
    Result.Named := pNamed;
  end;

begin
  Check('N1 default name', BackupFileName('C:\db\A.FDB', EncodeDateTime(2026, 11, 26, 9, 8, 7, 654)) = 'DLFR_BACKUP_A_20261126_090807.fbk',
    BackupFileName('C:\db\A.FDB', EncodeDateTime(2026, 11, 26, 9, 8, 7, 654)));
  Check('N1b collision suffix', BackupFileName('C:\db\A.FDB', EncodeDateTime(2026, 11, 26, 9, 8, 7, 654), 2) = 'DLFR_BACKUP_A_20261126_090807_2.fbk');
  vProblem := ResolveBackupName('mine', vResolved);
  Check('N2 .fbk is added', (vProblem = '') and (vResolved = 'mine.fbk'), vProblem + ' ' + vResolved);
  vProblem := ResolveBackupName('Mine.FBK', vResolved);
  Check('N2b .fbk kept as typed', (vProblem = '') and (vResolved = 'Mine.FBK'), vProblem + ' ' + vResolved);
  Check('N2c a path separator or drive is refused', (ResolveBackupName('x\y.fbk', vResolved) <> '') and (ResolveBackupName('x/y', vResolved) <> '') and
    (ResolveBackupName('C:y', vResolved) <> '') and (ResolveBackupName('..\y', vResolved) <> ''));
  Check('N2d empty, only the extension, bad characters, trailing dot -> refused', (ResolveBackupName('', vResolved) <> '') and (ResolveBackupName('  ', vResolved) <> '') and
    (ResolveBackupName('.fbk', vResolved) <> '') and (ResolveBackupName('a*b', vResolved) <> '') and (ResolveBackupName('a.', vResolved) <> '') and
    (ResolveBackupName('a?', vResolved) <> ''));
  vDir := TPath.Combine(GDir, 'names');
  TDirectory.CreateDirectory(vDir);
  vKeep := MakeEntry('names-keep', 'C:\db\A.FDB', 1, fbvFull);
  vOld := MakeEntry('names-old', 'C:\db\A.FDB', 2, fbvFull);
  Check('N3 the old form is still deleted', PlanOf(vOld).StartsWith('delete'), PlanOf(vOld));
  vFile := 'DLFR_BACKUP_A_20261126_090807.fbk';
  vEntry := Named(vFile, False);
  Check('N3b the new form is deleted', PlanOf(vEntry).StartsWith('delete'), PlanOf(vEntry));
  vEntry := Named('DLFR_BACKUP_A_20261126_090807_2.fbk', False);
  Check('N3c the new form with a collision suffix is deleted', PlanOf(vEntry).StartsWith('delete'), PlanOf(vEntry));
  vEntry := Named('dlfr_backup_a_20261126_090807.FBK', False);
  Check('N3d case does not matter', PlanOf(vEntry).StartsWith('delete'), PlanOf(vEntry));
  vEntry := Named('DLFR_BACKUP_B_20261126_090807.fbk', False);
  Check('N3e the new form of another database is left alone', PlanOf(vEntry).StartsWith('skip '), PlanOf(vEntry));
  vEntry := Named('DLFR_BACKUP_A_20261126.fbk', False);
  Check('N3f a new form without the time is left alone', PlanOf(vEntry).StartsWith('skip '), PlanOf(vEntry));
  vEntry := Named('mine.fbk', False);
  Check('N4 a free name NOT recorded as chosen is left alone', PlanOf(vEntry).StartsWith('skip '), PlanOf(vEntry));
  vEntry := Named('mine.fbk', True);
  Check('N4b a free name recorded as chosen (--backup-name) is deleted', PlanOf(vEntry).StartsWith('delete'), PlanOf(vEntry));
  vEntry := Named('mine.fdb', True);
  Check('N4c a chosen name that is not .fbk is left alone', PlanOf(vEntry).StartsWith('skip '), PlanOf(vEntry));
  vEntry := Named('mine.fbk', True);
  vEntry.FileName := vEntry.FileName.Replace('\', '/');
  Check('N4d a chosen name still needs the plain full path', PlanOf(vEntry).StartsWith('skip '), PlanOf(vEntry));
  vManifest := TPath.Combine(GDir, 'names\list.json');
  vEntry := Named('mine.fbk', True);
  AddToBackupManifest(vManifest, vEntry);
  AddToBackupManifest(vManifest, vOld);
  vRead := ReadBackupManifest(vManifest);
  Check('N5 the chosen-name mark survives the list file, and is absent for an old entry', (Length(vRead) = 2) and vRead[0].Named and not vRead[1].Named);
  Check('N5b an old list without the mark reads as not chosen', not ReadBackupManifest(vManifest)[1].Named);
end;

{ M4: a path that is not exactly what drag-lint writes is left alone, though size and date match }
procedure TestPurgePaths;
var
  vNew, vOld, vEntry: TFrBackupEntry;
  vDir, vJunction, vFile: string;

  procedure Skipped(const pName, pFile: string);
  var
    vItems: TArray<TFrPurgeItem>;
    vItem: TFrPurgeItem;
    vText: string;
  begin
    vEntry := vOld;
    vEntry.FileName := pFile;
    vText := '(none)';
    vItems := PlanBackupPurge([vNew, vEntry], 1);
    for vItem in vItems do
      if vItem.Entry.FileName = pFile then
        vText := PURGE_ACTION_NAMES[vItem.Action] + ' ' + vItem.Reason;
    Check('R ' + pName, vText.StartsWith('skip '), vText);
  end;

begin
  vNew := MakeEntry('r1', 'C:\db\A.FDB', 1, fbvFull);
  vOld := MakeEntry('r2', 'C:\db\A.FDB', 2, fbvFull);
  vDir := ExtractFilePath(vOld.FileName);
  Check('R0 control: the path as recorded is deleted', Actions(PlanBackupPurge([vNew, vOld], 1)) = 'r1=keep r2=delete', Actions(PlanBackupPurge([vNew, vOld], 1)));
  vFile := TPath.Combine(vDir, 'A.FDB');
  TFile.Copy(vOld.FileName, vFile);
  TFile.SetLastWriteTimeUtc(vFile, vOld.ModifiedUtc);
  Skipped('the database itself', vFile);
  vFile := TPath.Combine(vDir, 'B-20261123-101112000.fbk');
  TFile.Copy(vOld.FileName, vFile);
  TFile.SetLastWriteTimeUtc(vFile, vOld.ModifiedUtc);
  Skipped('the name of another database', vFile);
  vFile := TPath.Combine(vDir, 'A-20261123.fbk');
  TFile.Copy(vOld.FileName, vFile);
  TFile.SetLastWriteTimeUtc(vFile, vOld.ModifiedUtc);
  Skipped('a name drag-lint does not write', vFile);
  Skipped('a path with ..', TPath.Combine(vDir, '..\r2\' + ExtractFileName(vOld.FileName)));
  Skipped('a path with /', vOld.FileName.Replace('\', '/'));
  Skipped('a \\?\ path', '\\?\' + vOld.FileName);
  Skipped('a trailing dot', vOld.FileName + '.');
  vFile := TPath.Combine(vDir, 'A.FDB:A-20261123-101112000.fbk');
  Skipped('a stream of another file', vFile);
  SetCurrentDir(vDir);
  Skipped('a relative path', ExtractFileName(vOld.FileName));
  SetCurrentDir(GDir);
  vJunction := TPath.Combine(GDir, 'r2j');
  MakeJunction(vJunction, vDir);
  Skipped('a folder that is a junction', TPath.Combine(vJunction, ExtractFileName(vOld.FileName)));
  RemoveDir(vJunction);
  vEntry := vOld;
  Check('R9 the same file listed twice: neither entry is deleted', Actions(PlanBackupPurge([vNew, vOld, vEntry], 1)) = 'r1=keep r2=skip r2=skip',
    Actions(PlanBackupPurge([vNew, vOld, vEntry], 1)));
  vEntry.FileName := vOld.FileName.ToUpper;
  Check('R9b also when the spelling differs', Length(Actions(PlanBackupPurge([vNew, vOld, vEntry], 1)).Split(['=skip'])) = 3, Actions(PlanBackupPurge([vNew, vOld, vEntry], 1)));
  vEntry.FileName := ShortName(vOld.FileName);
  if SameText(vEntry.FileName, vOld.FileName) then
    Writeln('note: no short names on this disk, R9c checks nothing')
  else
    Check('R9c also when one entry has the short name of a folder', Length(Actions(PlanBackupPurge([vNew, vOld, vEntry], 1)).Split(['=skip'])) = 3, Actions(PlanBackupPurge([vNew, vOld, vEntry], 1)));
  vEntry := vOld;
  vEntry.FileName := TPath.Combine(GDir, 'unplugged\' + ExtractFileName(vOld.FileName));
  Check('R10 a folder that is not there (an unplugged drive) is skipped, not forgotten', Actions(PlanBackupPurge([vNew, vEntry], 1)) = 'r1=keep unplugged=skip',
    Actions(PlanBackupPurge([vNew, vEntry], 1)));
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
  { what FireDAC connects to, not what the text says }
  SetEnvironmentVariable('DLBK_FAR', 'srv:C:\db\x.fdb');
  SetEnvironmentVariable('DLBK_NEAR', 'C:\db\x.fdb');
  Host('Database=$(DLBK_FAR)', 'srv');
  Host('Database=$(DLBK_NEAR)', '');
  Host('Server=localhost;Database=srv:C:\db\x.fdb', 'srv');
  Host('Server=localhost;Database=inet://srv/x', 'inet');
  Host('Protocol=Local;Database=srv:C:\db\x.fdb', 'srv');
  Check('H2 a key given twice is refused', Failure(procedure begin RequireLocalFbServer('Server=srv;Server=localhost;Database=C:\db\x.fdb') end).Contains('Server is given twice'));
  Check('H2b also with another spelling', Failure(procedure begin RequireLocalFbServer('Database=srv:x; database = C:\db\x.fdb') end).Contains('is given twice'));
  Check('H2c no database: refused', Failure(procedure begin RequireLocalFbServer('User_Name=SYSDBA') end).Contains('Database'));
  Check('H2d control: each key once', Failure(procedure begin RequireLocalFbServer('Server=localhost;Port=3051;Database=C:\db\x.fdb') end) = '');
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
  vSaveReq: TFrBackupRequest;
  vSaveManifest: string;

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
  Check('L1b the name is DLFR_BACKUP_<database>_<date>_<time>.fbk', TRegEx.IsMatch(vName, '^DLFR_BACKUP_scratch_\d{8}_\d{6}\.fbk$', [roIgnoreCase]) and vName.Contains(FormatDateTime('yyyymmdd', Now)), vName);
  Check('L1c only the backup is left in the folder', (Files(vDir, '*') = 1) and (Files(vDir, 'drag-lint-verify-*') = 0));
  Check('L1d it is recorded', (Length(ReadBackupManifest(vManifest)) = 1) and (BackupFileState(ReadBackupManifest(vManifest)[0]) = ffsMatch) and
    SameText(ExtractFileName(ReadBackupManifest(vManifest)[0].Database), 'scratch.fdb'));
  Check('L1e the source is untouched: its tables and rows', OpenFirebirdProvider(ScratchConn).ReadScalar(
    'SELECT 10 * (SELECT COUNT(*) FROM T) + COUNT(*) FROM RDB$RELATIONS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0') = 22);
  { BKNAME: the chosen name; an existing file is refused; the same-second default name gets a suffix }
  vSaveReq := vReq;
  vSaveManifest := vManifest;
  Fresh('bkname');
  vReq.Verify := fvmQuick;
  vRes := BackupFbDatabase(vReq, vManifest);
  vReq.BackupName := 'chosen';
  vFail := Fails;
  Check('L1f --backup-name: the file is <name>.fbk, recorded as chosen', (vFail = '') and TFile.Exists(TPath.Combine(vDir, 'chosen.fbk')) and
    (Length(ReadBackupManifest(vManifest)) = 2) and ReadBackupManifest(vManifest)[1].Named and not ReadBackupManifest(vManifest)[0].Named, vFail);
  vFail := Fails;
  Check('L1g --backup-name over an existing file is refused, nothing more recorded', vFail.Contains('exists already') and (Length(ReadBackupManifest(vManifest)) = 2), vFail);
  vReq.BackupName := 'a\b';
  vFail := Fails;
  Check('L1h a name with a path separator is refused', vFail.Contains('path') and (Length(ReadBackupManifest(vManifest)) = 2), vFail);
  vReq.BackupName := '';
  TFile.Copy(vRes.Entry.FileName, TPath.Combine(vDir, 'DLFR_BACKUP_scratch_29990101_000000.fbk'));
  vReq.Now := function: TDateTime begin Result := EncodeDateTime(2999, 1, 1, 0, 0, 0, 0) end;
  vRes := BackupFbDatabase(vReq, vManifest);
  Check('L1i the default name of the same second gets _2 instead of failing', SameText(ExtractFileName(vRes.Entry.FileName), 'DLFR_BACKUP_scratch_29990101_000000_2.fbk'), ExtractFileName(vRes.Entry.FileName));
  vReq.Now := nil;
  vReq := vSaveReq;
  vManifest := vSaveManifest;
  vDir := vReq.BackupDir;
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
  vFail := Fails;
  Check('L3c control: it is for --verify quick', vFail = '', vFail);
  vReq := Request('space');
  vReq.FreeSpace := function(pDir: string): Int64 begin Result := vNeed * 3 end;
  vFail := Fails;
  Check('L3d control: three times is for both', vFail = '', vFail);
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
  vFail := Fails;
  Check('L4d control: without interference the same request succeeds', vFail = '', vFail);
  vReq := Request('corrupt2');
  vFail := Fails;
  Check('L4e and with the restore test', vFail = '', vFail);
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
  TFile.Copy(TPath.Combine(GDir, 'scratch.fdb'), TPath.Combine(GDir, 'a=b.fdb'));
  vReq.Connection := ScratchConn.Replace('scratch.fdb', 'a=b.fdb');
  vFail := Fails;
  Check('L6g a database with = in its name: refused', vFail.Contains('"="') and (Files(vDir, '*') = 0), vFail);
  vReq := Request('a=b');
  Check('L6d a folder with = in its name: refused', Fails.Contains('"="'));
  vReq := Request('file.txt');
  TFile.WriteAllText(vDir, 'x');
  vFail := Fails;
  Check('L6e a folder that is a file: refused', vFail.Contains('is a file'), vFail);
  Fresh('badlist');
  TFile.WriteAllText(vManifest, 'no list');
  vFail := Fails;
  Check('L6f a list that cannot be read: refused before the backup', vFail.Contains('not readable') and (Files(vDir, '*') = 0), vFail);
  { M1: the database of the open connection is the one that is backed up }
  Fresh('resolve');
  SetEnvironmentVariable('DLBK_LIVE', PChar(TPath.Combine(GDir, 'scratch.fdb')));
  vReq.Connection := 'DriverID=FB;Database=$(DLBK_LIVE);User_Name=SYSDBA;Password=unused';
  vRes := BackupFbDatabase(vReq, vManifest);
  Check('L8 a variable in Database: the expanded database is backed up', SameText(vRes.Entry.Database, TPath.Combine(GDir, 'scratch.fdb')) and (vRes.Entry.Verified = fbvFull), vRes.Entry.Database);
  Check('L8b the file the connection names, as it is recorded', FbDatabaseFile(vReq.Connection) = vRes.Entry.Database);
  Fresh('refuse1');
  vReq.Connection := 'DriverID=FB;Server=srv;Server=localhost;Database=' + TPath.Combine(GDir, 'scratch.fdb') + ';User_Name=SYSDBA;Password=unused';
  vFail := Fails;
  Check('L8c a key given twice: refused, nothing written', vFail.Contains('given twice') and (Files(vDir, '*') = 0) and Clean, vFail);
  Fresh('refuse2');
  vReq.Attachment := function: string begin Result := 'TCPv4|10.1.2.3/4711' end;
  vFail := Fails;
  Check('L8d the server says the attachment is remote: refused, nothing written', vFail.Contains('not on this machine (10.1.2.3)') and (Files(vDir, '*') = 0) and Clean, vFail);
  vReq.Attachment := function: string begin Result := 'TCPv4|127.0.0.1/4711' end;
  vFail := Fails;
  Check('L8e control: a loopback attachment passes', vFail = '', vFail);
  Fresh('refuse3');
  vReq.Identity := 1;
  vFail := Fails;
  Check('L8f another database than the one being altered: refused, nothing written', vFail.Contains('another database') and (Files(vDir, '*') = 0) and Clean, vFail);
  vReq.Identity := OpenFirebirdProvider(ScratchConn).ReadScalar(FB_IDENTITY_SQL);
  vFail := Fails;
  Check('L8g control: the same database passes, its identity is not 0', (vFail = '') and (vReq.Identity <> 0), vFail);
  { a backup that cannot be recorded: the file is named, and so is what went wrong before }
  Fresh('unlisted');
  vReq.Verify := fvmQuick;
  vReq.AfterBackup := procedure(pFile: string) begin TFile.WriteAllText(vManifest, 'broken meanwhile') end;
  vFail := Fails;
  Check('L9 the list breaks while the backup runs: the message names the file', vFail.Contains('.fbk') and vFail.Contains('not readable'), vFail);
  Fresh('unlisted2');
  vReq.AfterBackup := procedure(pFile: string) begin TFile.WriteAllText(vManifest, 'broken meanwhile') end;
  vReq.BeforeBackup := procedure(pFile: string) begin RunSql('INSERT INTO T VALUES (4, ''d'')') end;
  vFail := Fails;
  Check('L9b and the failed verification is not hidden', vFail.Contains('row(s)') and vFail.Contains('not readable') and vFail.Contains('.fbk'), vFail);
  RunSql('DELETE FROM T WHERE ID = 4');
  { ON CONNECT triggers do not run on the temporary copy }
  RunSql('CREATE EXCEPTION E_COPY ''a trigger ran on the copy''');
  RunSql('CREATE TRIGGER TR_CONN ON CONNECT AS BEGIN IF (RDB$GET_CONTEXT(''SYSTEM'', ''DB_NAME'') CONTAINING ''drag-lint-verify'') THEN EXCEPTION E_COPY; END');
  Fresh('trigger');
  vFail := Fails;
  Check('L10 ON CONNECT triggers do not run on the temporary copy', vFail = '', vFail);
  RunSql('DROP TRIGGER TR_CONN');
  Check('L7 after all of it the source is still a database with its rows', VarToStr(OpenFirebirdProvider(ScratchConn).ReadScalar('SELECT COUNT(*) FROM T')) = '3');
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-backup-tests-' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(GDir);
  try
    try
      TestManifest;
      TestPurge;
      TestPurgeLast;
      TestPurgePaths;
      TestNames;
      TestRemote;
      TestPurgeSwap;
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
