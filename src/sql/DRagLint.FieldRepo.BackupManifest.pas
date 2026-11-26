unit DRagLint.FieldRepo.BackupManifest;

{ drag-lint 1.54 -- lane ALTERBK (rulings R9 / R10): the list of database backups drag-lint made itself, and the purge
  over it. Only files of this list whose path is exactly one drag-lint writes and that still have the recorded size and
  date are ever deleted. No database code here. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when a backup, its verification or the manifest fails.</summary>
  EFrBackupError = class(Exception);

  /// <summary>How far a backup was verified. fbvFull = restored and compared; fbvQuick = only written; fbvFailed = the
  /// verification failed.</summary>
  TFrBackupVerified = (fbvFailed, fbvQuick, fbvFull);

  /// <summary>One backup file drag-lint made.</summary>
  TFrBackupEntry = record
    FileName: string;
    /// <summary>The database file on the server; backups are kept and purged per database.</summary>
    Database: string;
    Size: Int64;
    /// <summary>Last write time of the file (UTC) when it was recorded.</summary>
    ModifiedUtc: TDateTime;
    CreatedUtc: TDateTime;
    Verified: TFrBackupVerified;
    /// <summary>True when the user chose the file name (--backup-name): a purge then accepts any plain full path ending in
    /// .fbk, not only the names drag-lint gives by itself. Written to the list as "named"; absent = False.</summary>
    Named: Boolean;
    /// <summary>The server host when the backup was written on the disk of ANOTHER machine (the file name is then a path on that
    /// server, and Size / ModifiedUtc are 0); '' = this machine. Written to the list as "host"; absent = ''.</summary>
    Host: string;
  end;

  /// <summary>The file behind an entry: as recorded, different, or gone.</summary>
  TFrBackupFileState = (ffsMatch, ffsChanged, ffsMissing, ffsRemote);

  /// <summary>What a purge does with an entry. fpaSkip = the file is not as recorded and is left alone; fpaForget = the
  /// file is gone, only the entry goes.</summary>
  TFrPurgeAction = (fpaKeep, fpaDelete, fpaSkip, fpaForget);

  /// <summary>One line of a purge plan.</summary>
  TFrPurgeItem = record
    Entry: TFrBackupEntry;
    Action: TFrPurgeAction;
    Reason: string;
    /// <summary>Set by an apply when the deletion failed; '' otherwise.</summary>
    Error: string;
  end;

const
  /// <summary>Names of TFrBackupVerified in reports and in the manifest.</summary>
  VERIFIED_NAMES: array[TFrBackupVerified] of string = ('failed', 'quick', 'full');
  /// <summary>Names of TFrBackupFileState in reports.</summary>
  FILE_STATE_NAMES: array[TFrBackupFileState] of string = ('ok', 'changed', 'missing', 'remote');
  /// <summary>Names of TFrPurgeAction in reports.</summary>
  PURGE_ACTION_NAMES: array[TFrPurgeAction] of string = ('keep', 'delete', 'skip', 'forget');

/// <summary>Reads the manifest.</summary>
/// <param name="pManifest">The manifest file; a missing file is an empty list.</param>
/// <returns>The entries in file order.</returns>
/// <exception cref="EFrBackupError">The file is not a manifest; it is never overwritten then.</exception>
function ReadBackupManifest(const pManifest: string): TArray<TFrBackupEntry>;

/// <summary>Records one backup.</summary>
/// <param name="pManifest">The manifest file; created when missing.</param>
/// <param name="pEntry">The backup.</param>
/// <exception cref="EFrBackupError">The manifest is malformed or locked by another run.</exception>
procedure AddToBackupManifest(const pManifest: string; const pEntry: TFrBackupEntry);

/// <summary>Name of the mutex a writer of the manifest holds.</summary>
/// <param name="pManifest">The manifest file.</param>
/// <returns>A mutex name of this machine, the same in every Windows session.</returns>
function BackupManifestLockName(const pManifest: string): string;  // dl:ok unused-public-symbol@8054 -- REVIEWED 2026-11-23 ALTERBK: the pure part is the test seam; BackupTests.dpr (outside the indexed project) calls it

/// <summary>Compares the file of an entry with what was recorded.</summary>
/// <param name="pEntry">The entry.</param>
/// <returns>ffsRemote for an entry with a Host (the file is on another machine and is never looked at); else ffsMatch only when size
/// and last write time are unchanged.</returns>
function BackupFileState(const pEntry: TFrBackupEntry): TFrBackupFileState;

/// <summary>Bytes of the recorded backups whose file is still as recorded.</summary>
/// <param name="pEntries">The entries.</param>
/// <param name="pFiles">How many files that are.</param>
/// <returns>The sum.</returns>
function TotalBackupSize(const pEntries: TArray<TFrBackupEntry>; out pFiles: Integer): Int64;

/// <summary>Decides, per database, what a purge keeps.</summary>
/// <param name="pEntries">The manifest.</param>
/// <param name="pKeep">How many of the newest backups of each database stay (1 or more); see remarks.</param>
/// <returns>One item per entry, newest first per database.</returns>
/// <exception cref="EFrBackupError">pKeep is below 1.</exception>
/// <remarks>Only reads attributes, size and date of the files. Kept per database: the newest backup whatever its state;
/// the newest pKeep fully verified ones; the newest pKeep that did not fail; and, while there is no fully verified one, the
/// newest failed one. An entry is skipped, and counts for nothing, when its file differs, its folder is not there, its path
/// is not a full, unambiguous path with the name drag-lint gives a backup of that database, a part of the path is a
/// reparse point, or the file is listed more than once.</remarks>
function PlanBackupPurge(const pEntries: TArray<TFrBackupEntry>; pKeep: Integer): TArray<TFrPurgeItem>;  // dl:ok unused-public-symbol@4f0f -- REVIEWED 2026-11-23 ALTERBK: the pure part is the test seam; BackupTests.dpr (outside the indexed project) calls it

/// <summary>Purges the backups of one database: deletes the files PlanBackupPurge names and drops their entries.</summary>
/// <param name="pManifest">The manifest file.</param>
/// <param name="pDatabase">The database file as recorded; '' = the plan of every database, never with pApply.</param>
/// <param name="pKeep">See PlanBackupPurge.</param>
/// <param name="pApply">False = only the plan; nothing is deleted or written.</param>
/// <param name="pBeforeDelete">Test seam: called with the file name before a file is checked again and deleted.</param>
/// <returns>The plan for that database; Error is set where a deletion failed (that entry stays).</returns>
/// <exception cref="EFrBackupError">The manifest is malformed or locked, pKeep is below 1, pApply without a database, or the
/// manifest could not be written afterwards (the message names the deleted files).</exception>
/// <remarks>An entry with a Host (a backup on another machine) is always skipped: it is shown, never deleted. Attributes, size and date are checked again on the handle the file is deleted through, so a file that
/// was swapped after the plan is not deleted.</remarks>
function PurgeBackups(const pManifest, pDatabase: string; pKeep: Integer; pApply: Boolean;
  const pBeforeDelete: TProc<string> = nil): TArray<TFrPurgeItem>;

/// <summary>The name of a backup file made now.</summary>
/// <param name="pDatabase">The database file.</param>
/// <param name="pNow">Local time.</param>
/// <param name="pSuffix">0 or 1 = none; 2 or more appends _<n> (a second backup of the same second).</param>
/// <returns>DLFR_BACKUP_&lt;database&gt;_yyyymmdd_hhnnss.fbk (from 1.55; before it &lt;database&gt;-yyyymmdd-hhnnsszzz.fbk).
/// A purge deletes entries made under either form, with or without the _&lt;n&gt; suffix, and files named by --backup-name
/// only when the entry says so (TFrBackupEntry.Named).</returns>
function BackupFileName(const pDatabase: string; pNow: TDateTime; pSuffix: Integer = 0): string;

/// <summary>Checks a --backup-name and gives the file name it makes.</summary>
/// <param name="pName">The name as typed: a name, not a path.</param>
/// <param name="pFile">The file name: pName with .fbk added when it does not end in it. '' when refused.</param>
/// <returns>'' = usable; else what is wrong (empty, a path or drive in it, characters Windows refuses, a trailing dot).</returns>
function ResolveBackupName(const pName: string; out pFile: string): string;

implementation

uses
  Winapi.Windows,
  System.RegularExpressions,
  System.IOUtils,
  System.SyncObjs,
  System.Hash,
  System.JSON,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  DRagLint.Core.JsonFile;

const
  KEY_VERSION = 'version';
  KEY_BACKUPS = 'backups';
  KEY_FILE = 'file';
  KEY_DATABASE = 'database';
  KEY_SIZE = 'size';
  KEY_MODIFIED = 'modified_utc';
  KEY_CREATED = 'created_utc';
  KEY_VERIFIED = 'verified';
  KEY_NAMED = 'named';
  KEY_HOST = 'host';
  MANIFEST_VERSION = 1;
  LOCK_WAIT_MS = 5000;
  { a file time keeps 100 ns, a TDateTime in ISO text one millisecond }
  SAME_DATE_MS = 2;
  BACKUP_EXT = '.fbk';
  { old form <db>-yyyymmdd-hhnnsszzz.fbk, or the 1.55 form DLFR_BACKUP_<db>_yyyymmdd_hhnnss[_n].fbk }
  STAMP_PATTERN = '-\d{8}-\d{9}';
  STAMP_PATTERN_NEW = '_\d{8}_\d{6}(_\d+)?';
  NEW_PREFIX = 'DLFR_BACKUP_';

type
  { SetFileInformationByHandle, class FileDispositionInfo }
  TFileDisposition = record
    DeleteFile: ByteBool;
  end;

const
  FILE_DISPOSITION_CLASS = 4;
  DELETE_ACCESS = $00010000;
  OPEN_LINK_ITSELF = $00200000; // FILE_FLAG_OPEN_REPARSE_POINT

function SetFileInformationByHandle(pFile: THandle; pClass: Integer; pInfo: Pointer; pSize: DWORD): BOOL; stdcall;
  external kernel32 name 'SetFileInformationByHandle';

function Malformed(const pManifest: string): EFrBackupError;
begin
  Result := EFrBackupError.CreateFmt('the backup list is not readable, it is left as it is: %s', [pManifest]);
end;

function ReadEntry(const pManifest: string; pNode: TJSONValue): TFrBackupEntry;
var
  VVerified: string;
  VKind: TFrBackupVerified;
  VFound: Boolean;
begin
  Result := Default(TFrBackupEntry);
  if pNode is not TJSONObject then
    raise Malformed(pManifest);
  try
    Result.FileName := pNode.GetValue<string>(KEY_FILE);
    Result.Database := pNode.GetValue<string>(KEY_DATABASE);
    Result.Size := pNode.GetValue<Int64>(KEY_SIZE);
    Result.ModifiedUtc := ISO8601ToDate(pNode.GetValue<string>(KEY_MODIFIED), True);
    Result.CreatedUtc := ISO8601ToDate(pNode.GetValue<string>(KEY_CREATED), True);
    VVerified := pNode.GetValue<string>(KEY_VERIFIED);
    pNode.TryGetValue<Boolean>(KEY_NAMED, Result.Named);
    pNode.TryGetValue<string>(KEY_HOST, Result.Host);
  except
    on E: Exception do
      raise Malformed(pManifest);
  end;
  VFound := False;
  for VKind := Low(TFrBackupVerified) to High(TFrBackupVerified) do
    if VERIFIED_NAMES[VKind] = VVerified then
    begin
      Result.Verified := VKind;
      VFound := True;
    end;
  if not VFound then
    raise Malformed(pManifest);
end;

function ReadBackupManifest(const pManifest: string): TArray<TFrBackupEntry>;
var
  VRoot, VList, VNode: TJSONValue;
  VVersion: Integer;
begin
  Result := nil;
  if not TFile.Exists(pManifest) then
    Exit;
  VRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(pManifest));
  try
    if VRoot is not TJSONObject then
      raise Malformed(pManifest);
    if TJSONObject(VRoot).TryGetValue<Integer>(KEY_VERSION, VVersion) and (VVersion > MANIFEST_VERSION) then
      raise EFrBackupError.CreateFmt('the backup list was written by a newer drag-lint, it is left as it is: %s', [pManifest]);
    VList := TJSONObject(VRoot).GetValue(KEY_BACKUPS);
    if VList is not TJSONArray then
      raise Malformed(pManifest);
    for VNode in TJSONArray(VList) do
      Result := Result + [ReadEntry(pManifest, VNode)];
  finally
    VRoot.Free;
  end;
end;

procedure WriteManifest(const pManifest: string; const pEntries: TArray<TFrBackupEntry>);
var
  VRoot, VItem: TJSONObject;
  VList: TJSONArray;
  VEntry: TFrBackupEntry;
begin
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair(KEY_VERSION, TJSONNumber.Create(MANIFEST_VERSION));
    VList := TJSONArray.Create;
    VRoot.AddPair(KEY_BACKUPS, VList);
    for VEntry in pEntries do
    begin
      VItem := TJSONObject.Create;
      VItem.AddPair(KEY_FILE, VEntry.FileName);
      VItem.AddPair(KEY_DATABASE, VEntry.Database);
      VItem.AddPair(KEY_SIZE, TJSONNumber.Create(VEntry.Size));
      VItem.AddPair(KEY_MODIFIED, DateToISO8601(VEntry.ModifiedUtc, True));
      VItem.AddPair(KEY_CREATED, DateToISO8601(VEntry.CreatedUtc, True));
      VItem.AddPair(KEY_VERIFIED, VERIFIED_NAMES[VEntry.Verified]);
      if VEntry.Named then
        VItem.AddPair(KEY_NAMED, TJSONBool.Create(True));
      if VEntry.Host <> '' then
        VItem.AddPair(KEY_HOST, VEntry.Host);
      VList.AddElement(VItem);
    end;
    WriteJsonFileAtomic(pManifest, VRoot);
  finally
    VRoot.Free;
  end;
end;

function BackupManifestLockName(const pManifest: string): string;
begin
  Result := 'Global\drag-lint-backups-' + THashSHA2.GetHashString(ExpandFileName(pManifest).ToLower);
end;

{ Taken for a read-change-write of the manifest; the caller releases and frees it. }
function LockManifest(const pManifest: string): TMutex;
begin
  TDirectory.CreateDirectory(ExtractFilePath(pManifest));
  Result := TMutex.Create(nil, False, BackupManifestLockName(pManifest));
  { an abandoned mutex (its process died) is ours too }
  if Result.WaitFor(LOCK_WAIT_MS) in [wrSignaled, wrAbandoned] then
    Exit;
  Result.Free;
  raise EFrBackupError.CreateFmt('the backup list is in use by another run: %s', [pManifest]);
end;

procedure AddToBackupManifest(const pManifest: string; const pEntry: TFrBackupEntry);
var
  VLock: TMutex;
begin
  VLock := LockManifest(pManifest);
  try
    WriteManifest(pManifest, ReadBackupManifest(pManifest) + [pEntry]);
  finally
    VLock.Release;
    VLock.Free;
  end;
end;

function BackupFileState(const pEntry: TFrBackupEntry): TFrBackupFileState;
begin
  if pEntry.Host <> '' then
    Exit(ffsRemote);
  if not TFile.Exists(pEntry.FileName) then
    Exit(ffsMissing);
  Result := if (TFile.GetSize(pEntry.FileName) = pEntry.Size) and
    (MilliSecondsBetween(TFile.GetLastWriteTimeUtc(pEntry.FileName), pEntry.ModifiedUtc) <= SAME_DATE_MS) then ffsMatch else ffsChanged;
end;

function TotalBackupSize(const pEntries: TArray<TFrBackupEntry>; out pFiles: Integer): Int64;
var
  VEntry: TFrBackupEntry;
begin
  Result := 0;
  pFiles := 0;
  for VEntry in pEntries do
    if BackupFileState(VEntry) = ffsMatch then
    begin
      Inc(pFiles);
      Inc(Result, VEntry.Size);
    end;
end;

function NewestFirst(const pEntries: TArray<TFrBackupEntry>): TArray<TFrBackupEntry>;
begin
  Result := Copy(pEntries);
  TArray.Sort<TFrBackupEntry>(Result, TComparer<TFrBackupEntry>.Construct(
    function(const pLeft, pRight: TFrBackupEntry): Integer
    begin
      Result := CompareText(pLeft.Database, pRight.Database);
      if Result = 0 then
        Result := CompareDateTime(pRight.CreatedUtc, pLeft.CreatedUtc);
    end));
end;

function BackupFileName(const pDatabase: string; pNow: TDateTime; pSuffix: Integer): string;
const
  FIRST_SUFFIX = 2;
begin
  Result := NEW_PREFIX + ChangeFileExt(ExtractFileName(pDatabase), '') + FormatDateTime('"_"yyyymmdd"_"hhnnss', pNow) +
    (if pSuffix >= FIRST_SUFFIX then '_' + IntToStr(pSuffix) else '') + BACKUP_EXT;
end;

function ResolveBackupName(const pName: string; out pFile: string): string;
begin
  pFile := '';
  Result := '';
  if Trim(pName) = '' then
    Result := 'the name is empty'
  else if pName.IndexOfAny(['\', '/', ':']) >= 0 then
    Result := 'give a name, not a path: it has a path separator or a drive (--backup-dir picks the folder)'
  else if pName.IndexOfAny(['*', '?', '"', '<', '>', '|']) >= 0 then
    Result := 'the name has a character a file name cannot have'
  else if pName.EndsWith('.') or pName.EndsWith(' ') or (pName <> Trim(pName)) then
    Result := 'the name ends in a dot or a space'
  else if SameText(pName, BACKUP_EXT) then
    Result := 'the name is only the extension'
  else
    pFile := if pName.EndsWith(BACKUP_EXT, True) then pName else pName + BACKUP_EXT;
end;

function IsReparsePoint(pAttributes: DWORD): Boolean;
begin
  Result := pAttributes and FILE_ATTRIBUTE_REPARSE_POINT <> 0;
end;

{ A junction or link in the path (or a part that cannot be asked): the file may be another one than it says. }
function HasReparsePoint(const pFile: string): Boolean;
var
  VPart: string;
  VAttributes: DWORD;
begin
  Result := False;
  VPart := pFile;
  while not SameFileName(VPart, ExtractFileDir(VPart)) do
  begin
    VAttributes := GetFileAttributes(PChar(VPart));
    if (VAttributes = INVALID_FILE_ATTRIBUTES) or IsReparsePoint(VAttributes) then
      Exit(True);
    VPart := ExtractFileDir(VPart);
  end;
end;

{ '' = a full path in the one spelling drag-lint writes, with the name of a backup of that database. }
function NameProblem(const pEntry: TFrBackupEntry): string;
const
  DRIVE_COLON = 2;
var
  VName, VBase: string;
begin
  Result := '';
  VBase := TRegEx.Escape(ChangeFileExt(ExtractFileName(pEntry.Database), ''));
  VName := '^(' + VBase + STAMP_PATTERN + '|' + NEW_PREFIX + VBase + STAMP_PATTERN_NEW + ')\' + BACKUP_EXT + '$';
  if not SameStr(ExpandFileName(pEntry.FileName), pEntry.FileName) or TPath.IsExtendedPrefixed(pEntry.FileName) or pEntry.FileName.StartsWith('\\.\') or
    (LastDelimiter(':', pEntry.FileName) > DRIVE_COLON) then
    Result := 'not a full path in its plain form'
  else if not (pEntry.Named and ExtractFileName(pEntry.FileName).EndsWith(BACKUP_EXT, True)) and
    not TRegEx.IsMatch(ExtractFileName(pEntry.FileName), VName, [roIgnoreCase]) then
    Result := 'not the name drag-lint gives a backup of this database';
end;

{ Whether the entry is out of the purge, and how. fpaKeep = it takes part. }
function PurgeExclusion(const pEntry: TFrBackupEntry; pTimesListed: Integer; out pReason: string): TFrPurgeAction;
begin
  Result := fpaSkip;
  if pEntry.Host <> '' then
  begin
    pReason := 'the backup is on the server ' + pEntry.Host + ', not on this machine: drag-lint never deletes it';
    Exit;
  end;
  pReason := NameProblem(pEntry);
  if pReason <> '' then
    Exit;
  case BackupFileState(pEntry) of
    ffsMissing:
      if TDirectory.Exists(ExtractFileDir(pEntry.FileName)) then
      begin
        pReason := 'the file is gone';
        Result := fpaForget;
      end
      else
        pReason := 'its folder is not there (an unplugged drive?)';
    ffsChanged: pReason := 'size or date differs from what was recorded';
  else
    if HasReparsePoint(pEntry.FileName) then
      pReason := 'a part of its path is a link or junction'
    else if pTimesListed > 1 then
      pReason := 'the file is listed more than once'
    else
      Result := fpaKeep;
  end;
end;

function PurgeItem(const pEntry: TFrBackupEntry; pAction: TFrPurgeAction; const pReason: string): TFrPurgeItem;
begin
  Result.Entry := pEntry;
  Result.Action := pAction;
  Result.Reason := pReason;
  Result.Error := '';
end;

{ Volume and index of a file: the same for two spellings of one path; the path itself when the file cannot be asked. }
function FileIdentity(const pFile: string): string;
var
  VFile: THandle;
  VInfo: TByHandleFileInformation;
begin
  Result := pFile.ToLower;
  VFile := CreateFile(PChar(pFile), FILE_READ_ATTRIBUTES, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING, 0, 0);
  if VFile = INVALID_HANDLE_VALUE then
    Exit;
  if GetFileInformationByHandle(VFile, VInfo) then
    Result := Format('%x:%x:%x', [VInfo.dwVolumeSerialNumber, VInfo.nFileIndexHigh, VInfo.nFileIndexLow]);
  CloseHandle(VFile);
end;

{ How many entries name each file. The caller frees it. }
function CountFiles(const pEntries: TArray<TFrBackupEntry>): TDictionary<string, Integer>;
var
  VEntry: TFrBackupEntry;
  VId: string;
  VCount: Integer;
begin
  Result := TDictionary<string, Integer>.Create;
  for VEntry in pEntries do
  begin
    VId := FileIdentity(VEntry.FileName);
    if not Result.TryGetValue(VId, VCount) then
      VCount := 0;
    Result.AddOrSetValue(VId, VCount + 1);
  end;
end;

{ Decides the items pFrom..pTo, the usable backups of one database, newest first (Action is fpaKeep for them). }
procedure DecideDatabase(var pItems: TArray<TFrPurgeItem>; pFrom, pTo, pKeep: Integer);
var
  i, VFull, VNotFailed, VFailed, VFullTotal: Integer;
  VNewest: Boolean;
  VReason: string;
begin
  VFullTotal := 0;
  for i := pFrom to pTo do
    if (pItems[i].Action = fpaKeep) and (pItems[i].Entry.Verified = fbvFull) then
      Inc(VFullTotal);
  VFull := 0;
  VNotFailed := 0;
  VFailed := 0;
  VNewest := True;
  for i := pFrom to pTo do
  begin
    if pItems[i].Action <> fpaKeep then
      Continue;
    case pItems[i].Entry.Verified of
      fbvFull: Inc(VFull);
      fbvFailed: Inc(VFailed);
    end;
    if pItems[i].Entry.Verified <> fbvFailed then
      Inc(VNotFailed);
    VReason := '';
    if VNewest then
      VReason := 'the newest one'
    else if (pItems[i].Entry.Verified = fbvFull) and (VFull <= pKeep) then
      VReason := if VFull = 1 then 'the newest verified one' else Format('one of the newest %d verified', [pKeep])
    else if (pItems[i].Entry.Verified <> fbvFailed) and (VNotFailed <= pKeep) then
      VReason := Format('one of the newest %d', [pKeep])
    else if (pItems[i].Entry.Verified = fbvFailed) and (VFullTotal = 0) and (VFailed = 1) then
      VReason := 'there is no verified one';
    VNewest := False;
    if VReason = '' then
    begin
      pItems[i].Action := fpaDelete;
      VReason := if pItems[i].Entry.Verified = fbvFailed then 'its verification failed' else Format('older than the newest %d', [pKeep]);
    end;
    pItems[i].Reason := VReason;
  end;
end;

function PlanBackupPurge(const pEntries: TArray<TFrBackupEntry>; pKeep: Integer): TArray<TFrPurgeItem>;
var
  VEntry: TFrBackupEntry;
  VAction: TFrPurgeAction;
  VReason: string;
  VFirst, VTimes, i: Integer;
  VCounts: TDictionary<string, Integer>;
begin
  if pKeep < 1 then
    raise EFrBackupError.Create('--keep takes a number of backups, 1 or more');
  Result := nil;
  VCounts := CountFiles(pEntries);
  try
    for VEntry in NewestFirst(pEntries) do
    begin
      if not VCounts.TryGetValue(FileIdentity(VEntry.FileName), VTimes) then
        VTimes := 1;
      VAction := PurgeExclusion(VEntry, VTimes, VReason);
      Result := Result + [PurgeItem(VEntry, VAction, VReason)];
    end;
  finally
    VCounts.Free;
  end;
  VFirst := 0;
  for i := 0 to High(Result) do
    if (i = High(Result)) or not SameText(Result[i + 1].Entry.Database, Result[i].Entry.Database) then
    begin
      DecideDatabase(Result, VFirst, i, pKeep);
      VFirst := i + 1;
    end;
end;

{ The file behind an open handle is the recorded one. }
function HandleMatches(pFile: THandle; const pEntry: TFrBackupEntry): Boolean;
var
  VInfo: TByHandleFileInformation;
  VSize: ULARGE_INTEGER;
  VTime: TSystemTime;
begin
  if not GetFileInformationByHandle(pFile, VInfo) or not FileTimeToSystemTime(VInfo.ftLastWriteTime, VTime) then
    RaiseLastOSError;
  VSize.LowPart := VInfo.nFileSizeLow;
  VSize.HighPart := VInfo.nFileSizeHigh;
  Result := not IsReparsePoint(VInfo.dwFileAttributes) and (Int64(VSize.QuadPart) = pEntry.Size) and
    (MilliSecondsBetween(SystemTimeToDateTime(VTime), pEntry.ModifiedUtc) <= SAME_DATE_MS);
end;

{ Checks the file again and deletes it through one handle: nobody can swap the file or a folder of its path in between. }
procedure DeleteItem(var pItem: TFrPurgeItem);
var
  VFile: THandle;
  VDisposition: TFileDisposition;
  VMatches: Boolean;
begin
  VFile := CreateFile(PChar(pItem.Entry.FileName), FILE_READ_ATTRIBUTES or DELETE_ACCESS, FILE_SHARE_READ, nil, OPEN_EXISTING,
    OPEN_LINK_ITSELF, 0);
  if VFile = INVALID_HANDLE_VALUE then
  begin
    VMatches := GetLastError not in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND];
    if VMatches then
      pItem.Error := SysErrorMessage(GetLastError);
  end
  else
    try
      VMatches := HandleMatches(VFile, pItem.Entry) and not HasReparsePoint(pItem.Entry.FileName);
      VDisposition.DeleteFile := True;
      if VMatches and not SetFileInformationByHandle(VFile, FILE_DISPOSITION_CLASS, @VDisposition, SizeOf(VDisposition)) then
        pItem.Error := SysErrorMessage(GetLastError);
    finally
      CloseHandle(VFile);
    end;
  if VMatches then
    Exit;
  pItem.Action := fpaSkip;
  pItem.Reason := 'the file changed while the purge ran';
end;

{ The list after a purge; what was deleted is named when it cannot be written. }
procedure WritePurged(const pManifest: string; const pItems: TArray<TFrPurgeItem>; const pLeft: TArray<TFrBackupEntry>);
var
  VItem: TFrPurgeItem;
  VDeleted: string;
begin
  try
    WriteManifest(pManifest, pLeft);
  except
    on E: Exception do
    begin
      VDeleted := '';
      for VItem in pItems do
        if (VItem.Action = fpaDelete) and (VItem.Error = '') then
          VDeleted := VDeleted + ' ' + VItem.Entry.FileName;
      raise EFrBackupError.CreateFmt('the backup list could not be written (%s); deleted:%s', [E.Message,
        if VDeleted = '' then ' nothing' else VDeleted]);
    end;
  end;
end;

function PurgeBackups(const pManifest, pDatabase: string; pKeep: Integer; pApply: Boolean;
  const pBeforeDelete: TProc<string>): TArray<TFrPurgeItem>;
var
  VLock: TMutex;
  VPlan: TArray<TFrPurgeItem>;
  VLeft: TArray<TFrBackupEntry>;
  i: Integer;

  function Mine(const pItem: TFrPurgeItem): Boolean;
  begin
    Result := (pDatabase = '') or SameText(pItem.Entry.Database, pDatabase);
  end;

begin
  if pApply and (pDatabase = '') then
    raise EFrBackupError.Create('a purge deletes only backups of the database --connection names: give --connection');
  Result := nil;
  if not pApply then
  begin
    VPlan := PlanBackupPurge(ReadBackupManifest(pManifest), pKeep);
    for i := 0 to High(VPlan) do
      if Mine(VPlan[i]) then
        Result := Result + [VPlan[i]];
    Exit;
  end;
  VLock := LockManifest(pManifest);
  try
    VPlan := PlanBackupPurge(ReadBackupManifest(pManifest), pKeep);
    VLeft := nil;
    for i := 0 to High(VPlan) do
    begin
      if not Mine(VPlan[i]) then
      begin
        VLeft := VLeft + [VPlan[i].Entry];
        Continue;
      end;
      if VPlan[i].Action = fpaDelete then
      begin
        if Assigned(pBeforeDelete) then
          pBeforeDelete(VPlan[i].Entry.FileName);
        DeleteItem(VPlan[i]);
      end;
      if (VPlan[i].Action in [fpaKeep, fpaSkip]) or (VPlan[i].Error <> '') then
        VLeft := VLeft + [VPlan[i].Entry];
      Result := Result + [VPlan[i]];
    end;
    if Length(VLeft) <> Length(VPlan) then
      WritePurged(pManifest, Result, VLeft);
  finally
    VLock.Release;
    VLock.Free;
  end;
end;

end.
