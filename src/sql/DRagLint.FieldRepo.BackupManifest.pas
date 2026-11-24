unit DRagLint.FieldRepo.BackupManifest;

{ drag-lint 1.54 -- lane ALTERBK (rulings R9 / R10): the list of database backups drag-lint made itself, and the purge
  over it. Only files of this list that still have the recorded size and date are ever deleted. No database code here. }

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
  end;

  /// <summary>The file behind an entry: as recorded, different, or gone.</summary>
  TFrBackupFileState = (ffsMatch, ffsChanged, ffsMissing);

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
  FILE_STATE_NAMES: array[TFrBackupFileState] of string = ('ok', 'changed', 'missing');
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
/// <returns>A mutex name of this Windows session.</returns>
function BackupManifestLockName(const pManifest: string): string;  // dl:ok unused-public-symbol@8054 -- REVIEWED 2026-11-23 ALTERBK: the pure part is the test seam; BackupTests.dpr (outside the indexed project) calls it

/// <summary>Compares the file of an entry with what was recorded.</summary>
/// <param name="pEntry">The entry.</param>
/// <returns>ffsMatch only when size and last write time are unchanged.</returns>
function BackupFileState(const pEntry: TFrBackupEntry): TFrBackupFileState;

/// <summary>Bytes of the recorded backups whose file is still as recorded.</summary>
/// <param name="pEntries">The entries.</param>
/// <param name="pFiles">How many files that are.</param>
/// <returns>The sum.</returns>
function TotalBackupSize(const pEntries: TArray<TFrBackupEntry>; out pFiles: Integer): Int64;

/// <summary>Decides, per database, what a purge keeps.</summary>
/// <param name="pEntries">The manifest.</param>
/// <param name="pKeep">How many of the newest good backups of each database stay (1 or more).</param>
/// <returns>One item per entry, newest first per database.</returns>
/// <exception cref="EFrBackupError">pKeep is below 1.</exception>
/// <remarks>Only reads the files' size and date. The newest fully verified backup of a database is always kept. A backup
/// whose verification failed never counts as a kept one.</remarks>
function PlanBackupPurge(const pEntries: TArray<TFrBackupEntry>; pKeep: Integer): TArray<TFrPurgeItem>;  // dl:ok unused-public-symbol@4f0f -- REVIEWED 2026-11-23 ALTERBK: the pure part is the test seam; BackupTests.dpr (outside the indexed project) calls it

/// <summary>Purges: deletes the files PlanBackupPurge names and drops their entries.</summary>
/// <param name="pManifest">The manifest file.</param>
/// <param name="pKeep">See PlanBackupPurge.</param>
/// <param name="pApply">False = only the plan; nothing is deleted or written.</param>
/// <returns>The plan; Error is set where a deletion failed (that entry stays).</returns>
/// <exception cref="EFrBackupError">The manifest is malformed or locked, or pKeep is below 1.</exception>
function PurgeBackups(const pManifest: string; pKeep: Integer; pApply: Boolean): TArray<TFrPurgeItem>;

implementation

uses
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
  MANIFEST_VERSION = 1;
  LOCK_WAIT_MS = 5000;
  { a file time keeps 100 ns, a TDateTime in ISO text one millisecond }
  SAME_DATE_MS = 2;

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
begin
  Result := nil;
  if not TFile.Exists(pManifest) then
    Exit;
  VRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(pManifest));
  try
    if VRoot is not TJSONObject then
      raise Malformed(pManifest);
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
      VList.AddElement(VItem);
    end;
    WriteJsonFileAtomic(pManifest, VRoot);
  finally
    VRoot.Free;
  end;
end;

function BackupManifestLockName(const pManifest: string): string;
begin
  Result := 'drag-lint-backups-' + THashSHA2.GetHashString(ExpandFileName(pManifest).ToLower);
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

function PurgeItem(const pEntry: TFrBackupEntry; pAction: TFrPurgeAction; const pReason: string): TFrPurgeItem;
begin
  Result.Entry := pEntry;
  Result.Action := pAction;
  Result.Reason := pReason;
  Result.Error := '';
end;

function PlanBackupPurge(const pEntries: TArray<TFrBackupEntry>; pKeep: Integer): TArray<TFrPurgeItem>;
var
  VEntry: TFrBackupEntry;
  VDatabase: string;
  VKept: Integer;
  VFullSeen, VNewestFull: Boolean;
begin
  if pKeep < 1 then
    raise EFrBackupError.Create('--keep takes a number of backups, 1 or more');
  Result := nil;
  VDatabase := '';
  VKept := 0;
  VFullSeen := False;
  for VEntry in NewestFirst(pEntries) do
  begin
    if not SameText(VEntry.Database, VDatabase) then
    begin
      VDatabase := VEntry.Database;
      VKept := 0;
      VFullSeen := False;
    end;
    case BackupFileState(VEntry) of
      ffsMissing: Result := Result + [PurgeItem(VEntry, fpaForget, 'the file is gone')];
      ffsChanged: Result := Result + [PurgeItem(VEntry, fpaSkip, 'size or date differs from what was recorded')];
    else
      VNewestFull := (VEntry.Verified = fbvFull) and not VFullSeen;
      VFullSeen := VFullSeen or VNewestFull;
      if VEntry.Verified = fbvFailed then
        Result := Result + [PurgeItem(VEntry, fpaDelete, 'its verification failed')]
      else if VKept < pKeep then
      begin
        Inc(VKept);
        Result := Result + [PurgeItem(VEntry, fpaKeep, Format('one of the newest %d', [pKeep]))];
      end
      else if VNewestFull then
        Result := Result + [PurgeItem(VEntry, fpaKeep, 'the newest verified one')]
      else
        Result := Result + [PurgeItem(VEntry, fpaDelete, Format('older than the newest %d', [pKeep]))];
    end;
  end;
end;

{ The state is asked again right before the deletion. }
procedure DeleteItem(var pItem: TFrPurgeItem);
begin
  if BackupFileState(pItem.Entry) <> ffsMatch then
  begin
    pItem.Action := fpaSkip;
    pItem.Reason := 'the file changed while the purge ran';
    Exit;
  end;
  try
    TFile.Delete(pItem.Entry.FileName);
  except
    on E: Exception do
      pItem.Error := E.Message;
  end;
end;

function PurgeBackups(const pManifest: string; pKeep: Integer; pApply: Boolean): TArray<TFrPurgeItem>;
var
  VLock: TMutex;
  VLeft: TArray<TFrBackupEntry>;
  i: Integer;
begin
  if not pApply then
    Exit(PlanBackupPurge(ReadBackupManifest(pManifest), pKeep));
  VLock := LockManifest(pManifest);
  try
    Result := PlanBackupPurge(ReadBackupManifest(pManifest), pKeep);
    VLeft := nil;
    for i := 0 to High(Result) do
    begin
      if Result[i].Action = fpaDelete then
        DeleteItem(Result[i]);
      if (Result[i].Action in [fpaKeep, fpaSkip]) or (Result[i].Error <> '') then
        VLeft := VLeft + [Result[i].Entry];
    end;
    if Length(VLeft) <> Length(Result) then
      WriteManifest(pManifest, VLeft);
  finally
    VLock.Release;
    VLock.Free;
  end;
end;

end.
