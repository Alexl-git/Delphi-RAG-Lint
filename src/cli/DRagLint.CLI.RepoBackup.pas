unit DRagLint.CLI.RepoBackup;

{ drag-lint 1.54 -- lane ALTERBK (rulings R9 / R10): `repo backup --connection` (a database backup), `repo backup list`,
  `repo backup purge`, and the backup `repo alter-table --apply` makes first. Without --connection and without list /
  purge `repo backup` stays the text backup of the repository (DRagLint.CLI.Repo). The flags are read from the command
  line (ParseArgs only has to accept them). }

interface

uses
  DRagLint.FieldRepo.AlterReport;

/// <summary>True when `repo backup` means database backups, not the text backup of the repository.</summary>
/// <param name="pSub">The sub-verb.</param>
/// <param name="pConnection">--connection.</param>
/// <returns>True for `backup` with --connection, `backup list` and `backup purge`.</returns>
function IsRepoDbBackup(const pSub, pConnection: string): Boolean;

/// <summary>Runs `repo backup --connection ...`, `repo backup list` or `repo backup purge --keep N [--apply]`.</summary>
/// <param name="pRepo">--repo; refused, because a database backup has nothing to do with a repository file.</param>
/// <param name="pConnection">--connection.</param>
/// <param name="pJson">--json: one JSON object on stdout.</param>
/// <returns>0 = ok (a purge dry run included); 1 = bad arguments, a failed backup, a failed verification, or a file the
/// purge could not delete.</returns>
/// <remarks>Never prints a password. The purge deletes nothing without --apply.</remarks>
function RunRepoDbBackup(const pRepo, pConnection: string; pJson: Boolean): Integer;

/// <summary>What is wrong with --verify on this command line.</summary>
/// <returns>'' = usable.</returns>
function BackupArgsProblem: string;

/// <summary>Makes the verified, recorded backup of `alter-table --apply`.</summary>
/// <param name="pConnection">--connection.</param>
/// <param name="pTable">The altered table; its row count is compared.</param>
/// <returns>What the report prints.</returns>
/// <exception cref="EFrBackupError">The backup or its verification failed; the message may hold driver text, scrub it
/// with ScrubSecrets.</exception>
function BackupBeforeApply(const pConnection, pTable: string): TFrAlterBackup;

/// <summary>Masks every password value of a connection string in a text.</summary>
/// <param name="pText">The text.</param>
/// <param name="pConnection">The connection string.</param>
/// <returns>The text with each password replaced by ***.</returns>
function ScrubSecrets(const pText, pConnection: string): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  System.DateUtils,
  System.JSON,
  FireDAC.ConsoleUI.Wait, // the services need a wait-cursor factory; a connection does not
  DRagLint.Core.ContextDefaults,
  DRagLint.FieldRepo.BackupManifest,
  DRagLint.FieldRepo.FbBackup;

const
  EXIT_OK = 0;
  EXIT_FAIL = 1;
  MASK = '***';
  SECRET_KEYS: array[0..3] of string = ('Password', 'Pwd', 'Pass', 'Passwd');
  SUB_BACKUP = 'backup';
  WORD_LIST = 'list';
  WORD_PURGE = 'purge';
  { `repo backup <word>`: the third argument }
  WORD_ARG = 3;
  VERIFY_FULL = 'full';
  VERIFY_QUICK = 'quick';
  MANIFEST_FILE = 'db-backups.json';
  CFG_KEY = 'backupDir';
  CFG_FILE = '_D-RAG\drag-lint-project.json';
  DATE_FORMAT = 'yyyy"-"mm"-"dd hh":"nn":"ss';

function CommandLineFlag(const pFlag: string): Boolean;
var
  VI: Integer;
begin
  Result := False;
  for VI := 1 to ParamCount do
    if SameText(ParamStr(VI), pFlag) then
      Exit(True);
end;

function CommandLineValue(const pFlag: string): string;
var
  VI: Integer;
begin
  Result := '';
  for VI := 1 to ParamCount - 1 do
    if SameText(ParamStr(VI), pFlag) then
      Exit(ParamStr(VI + 1));
end;

function ScrubSecrets(const pText, pConnection: string): string;
var
  VPair, VValue: string;
  VEq: Integer;
begin
  Result := pText;
  for VPair in pConnection.Split([';'], TStringSplitOptions.ExcludeEmpty) do
  begin
    VEq := Pos('=', VPair);
    VValue := Trim(Copy(VPair, VEq + 1, MaxInt));
    if (VEq > 1) and (VValue <> '') and MatchText(Trim(Copy(VPair, 1, VEq - 1)), SECRET_KEYS) then
      Result := StringReplace(Result, VValue, MASK, [rfReplaceAll, rfIgnoreCase]);
  end;
end;

function IsRepoDbBackup(const pSub, pConnection: string): Boolean;
begin
  Result := SameText(pSub, SUB_BACKUP) and ((pConnection <> '') or MatchText(ParamStr(WORD_ARG), [WORD_LIST, WORD_PURGE]));
end;

function BackupArgsProblem: string;
begin
  Result := if CommandLineFlag('--verify') and not MatchText(CommandLineValue('--verify'), [VERIFY_FULL, VERIFY_QUICK]) then
    '--verify takes full (default: restore test) or quick' else '';
end;

function ManifestFile: string;
var
  VDir: string;
begin
  VDir := DragLintLocalDataDir;
  if VDir = '' then
    raise EFrBackupError.Create('LOCALAPPDATA is not set: the list of backups has no place');
  Result := TPath.Combine(VDir, MANIFEST_FILE);
end;

{ "backupDir" of the --project's _D-RAG\drag-lint-project.json (relative to the project folder); '' = not set. }
function SettingBackupDir: string;
var
  VProject, VDir, VFile: string;
  VRoot: TJSONValue;
begin
  Result := '';
  VProject := CommandLineValue('--project');
  if VProject = '' then
    Exit;
  VDir := ExtractFilePath(ExpandFileName(VProject));
  VFile := TPath.Combine(VDir, CFG_FILE);
  if not TFile.Exists(VFile) then
    Exit;
  VRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(VFile));
  try
    if VRoot = nil then
      raise EFrBackupError.CreateFmt('not valid JSON: %s', [VFile]);
    if VRoot.TryGetValue<string>(CFG_KEY, Result) and (Result <> '') then
      Result := TPath.GetFullPath(TPath.Combine(VDir, Result));
  finally
    VRoot.Free;
  end;
end;

{ The folder of the command line, else of the project, else '' = beside the database. }
function BackupDir: string;
begin
  Result := CommandLineValue('--backup-dir');
  if Result = '' then
    Result := SettingBackupDir;
end;

function MakeBackup(const pConnection, pTable: string): TFrAlterBackup;
var
  VRequest: TFrBackupRequest;
  VMade: TFrBackupResult;
begin
  VRequest := Default(TFrBackupRequest);
  VRequest.Connection := pConnection;
  VRequest.BackupDir := BackupDir;
  VRequest.TableName := pTable;
  VRequest.Verify := if SameText(CommandLineValue('--verify'), VERIFY_QUICK) then fvmQuick else fvmFull;
  Writeln(ErrOutput, 'making a backup of the database',
    if VRequest.Verify = fvmFull then ' and restoring it into a temporary database (--verify quick skips that)' else '', ' ...');
  VMade := BackupFbDatabase(VRequest, ManifestFile);
  Result.FileName := VMade.Entry.FileName;
  Result.Size := VMade.Entry.Size;
  Result.Verified := VERIFIED_NAMES[VMade.Entry.Verified];
  Result.Tables := VMade.Tables;
  Result.Rows := VMade.Rows;
  Result.Leftover := VMade.Leftover;
  Result.TotalSize := TotalBackupSize(ReadBackupManifest(ManifestFile), Result.TotalFiles);
end;

function BackupBeforeApply(const pConnection, pTable: string): TFrAlterBackup;
begin
  try
    Result := MakeBackup(pConnection, pTable);
  except
    on E: Exception do
      raise EFrBackupError.Create('no backup, nothing applied: ' + E.Message);
  end;
end;

function RunBackup(const pConnection: string; pJson: Boolean): Integer;
var
  VBackup: TFrAlterBackup;
  VLine: string;
  VRoot: TJSONObject;
begin
  Result := EXIT_OK;
  VBackup := MakeBackup(pConnection, CommandLineValue('--table').Trim.ToUpper);
  if not pJson then
  begin
    for VLine in RenderBackupText(VBackup) do
      Writeln(VLine);
    Exit;
  end;
  VRoot := BackupToJson(VBackup);
  try
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

function EntryToJson(const pEntry: TFrBackupEntry): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', pEntry.FileName);
  Result.AddPair('database', pEntry.Database);
  Result.AddPair('size', TJSONNumber.Create(pEntry.Size));
  Result.AddPair('created_utc', DateToISO8601(pEntry.CreatedUtc, True));
  Result.AddPair('verified', VERIFIED_NAMES[pEntry.Verified]);
end;

function EntryText(const pEntry: TFrBackupEntry): string;
begin
  Result := Format('%s  %d bytes  %s UTC  verified %s  (%s)', [pEntry.FileName, pEntry.Size, FormatDateTime(DATE_FORMAT, pEntry.CreatedUtc),
    VERIFIED_NAMES[pEntry.Verified], pEntry.Database]);
end;

function RunList(pJson: Boolean): Integer;
var
  VEntries: TArray<TFrBackupEntry>;
  VEntry: TFrBackupEntry;
  VFiles: Integer;
  VTotal: Int64;
  VRoot, VItem: TJSONObject;
  VList: TJSONArray;
begin
  VEntries := ReadBackupManifest(ManifestFile);
  VTotal := TotalBackupSize(VEntries, VFiles);
  Result := EXIT_OK;
  if not pJson then
  begin
    for VEntry in VEntries do
      Writeln(EntryText(VEntry), '  ', FILE_STATE_NAMES[BackupFileState(VEntry)]);
    Writeln(Format('backups on disk: %d file(s), %d bytes in total; the list: %s', [VFiles, VTotal, ManifestFile]));
    Exit;
  end;
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('manifest', ManifestFile);
    VList := TJSONArray.Create;
    VRoot.AddPair('backups', VList);
    for VEntry in VEntries do
    begin
      VItem := EntryToJson(VEntry);
      VItem.AddPair('state', FILE_STATE_NAMES[BackupFileState(VEntry)]);
      VList.AddElement(VItem);
    end;
    VRoot.AddPair('total_files', TJSONNumber.Create(VFiles));
    VRoot.AddPair('total_size', TJSONNumber.Create(VTotal));
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

procedure PrintPurge(const pItems: TArray<TFrPurgeItem>; pApply, pJson: Boolean);
var
  VItem: TFrPurgeItem;
  VRoot, VObject: TJSONObject;
  VList: TJSONArray;
begin
  if not pJson then
  begin
    for VItem in pItems do
      Writeln(PURGE_ACTION_NAMES[VItem.Action], '  ', EntryText(VItem.Entry), '  ', VItem.Reason,
        if VItem.Error <> '' then '  FAILED: ' + VItem.Error else '');
    if not pApply then
      Writeln('dry run: nothing deleted (add --apply to delete)');
    Exit;
  end;
  VRoot := TJSONObject.Create;
  try
    VRoot.AddPair('dry_run', TJSONBool.Create(not pApply));
    VList := TJSONArray.Create;
    VRoot.AddPair('items', VList);
    for VItem in pItems do
    begin
      VObject := EntryToJson(VItem.Entry);
      VObject.AddPair('action', PURGE_ACTION_NAMES[VItem.Action]);
      VObject.AddPair('reason', VItem.Reason);
      VObject.AddPair('error', VItem.Error);
      VList.AddElement(VObject);
    end;
    Writeln(VRoot.ToJSON);
  finally
    VRoot.Free;
  end;
end;

function RunPurge(pJson: Boolean): Integer;
var
  VKeep: Integer;
  VApply: Boolean;
  VItems: TArray<TFrPurgeItem>;
  VItem: TFrPurgeItem;
begin
  if not TryStrToInt(CommandLineValue('--keep'), VKeep) then
    raise EFrBackupError.Create('give --keep <number of backups per database>');
  VApply := CommandLineFlag('--apply') and not CommandLineFlag('--dry-run');
  VItems := PurgeBackups(ManifestFile, VKeep, VApply);
  PrintPurge(VItems, VApply, pJson);
  Result := EXIT_OK;
  for VItem in VItems do
    if VItem.Error <> '' then
      Result := EXIT_FAIL;
end;

function RunRepoDbBackup(const pRepo, pConnection: string; pJson: Boolean): Integer;
var
  VWord, VProblem: string;
begin
  Result := EXIT_FAIL;
  try
    VWord := ParamStr(WORD_ARG);
    VProblem := BackupArgsProblem;
    if pRepo <> '' then
      VProblem := '--repo does not go with a database backup (without --connection: the text backup of the repository)';
    if VProblem <> '' then
      raise EFrBackupError.Create(VProblem);
    if SameText(VWord, WORD_LIST) then
      Result := RunList(pJson)
    else if SameText(VWord, WORD_PURGE) then
      Result := RunPurge(pJson)
    else
      Result := RunBackup(pConnection, pJson);
  except
    on E: Exception do
      Writeln(ErrOutput, 'repo backup: ', ScrubSecrets(E.Message, pConnection));
  end;
end;

end.
