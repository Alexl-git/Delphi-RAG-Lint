unit DRagLint.CLI.RepoBackup;

{ drag-lint 1.54 -- lane ALTERBK (rulings R9 / R10): `repo backup --connection` (a database backup), `repo backup list`,
  `repo backup purge`, and the backup `repo alter-table --apply` makes first. Only a command line of --repo / --project /
  --output is the text backup of the repository (DRagLint.CLI.Repo); anything else on `repo backup` comes here and is a
  database backup, its list, its purge, or an error. The flags are read from the command line (ParseArgs only has to
  accept them). }

interface

uses
  DRagLint.FieldRepo.AlterReport;

/// <summary>True when `repo backup` is not the plain text backup of the repository.</summary>
/// <param name="pSub">The sub-verb.</param>
/// <param name="pConnection">--connection.</param>
/// <returns>False only for `backup` with nothing but --repo, --project and --output on the command line.</returns>
/// <remarks>So a database backup with a forgotten --connection never writes a text backup instead.</remarks>
function IsRepoDbBackup(const pSub, pConnection: string): Boolean;

/// <summary>Runs `repo backup --connection ...`, `repo backup list` or `repo backup purge --keep N [--apply]`.</summary>
/// <param name="pRepo">--repo; refused, because a database backup has nothing to do with a repository file.</param>
/// <param name="pConnection">--connection.</param>
/// <param name="pJson">--json: one JSON object on stdout.</param>
/// <returns>0 = ok (a purge dry run included); 1 = bad arguments (a flag or word that does not belong, has no value or is
/// given twice), a failed backup, a failed verification, or a file the purge could not delete.</returns>
/// <remarks>Never prints a password. The purge deletes nothing without --apply and --connection, and then only backups of
/// the database the connection opens.</remarks>
function RunRepoDbBackup(const pRepo, pConnection: string; pJson: Boolean): Integer;

/// <summary>What is wrong with --verify or --backup-name on this command line.</summary>
/// <returns>'' = usable.</returns>
function BackupArgsProblem: string;

/// <summary>Makes the verified, recorded backup of `alter-table --apply`.</summary>
/// <param name="pConnection">--connection.</param>
/// <param name="pTable">The altered table; its row count is compared.</param>
/// <param name="pIdentity">FB_IDENTITY_SQL as the connection that applies the changes reports it.</param>
/// <returns>What the report prints.</returns>
/// <exception cref="EFrBackupError">The backup or its verification failed; the message may hold driver text, scrub it
/// with ScrubSecrets.</exception>
function BackupBeforeApply(const pConnection, pTable: string; pIdentity: Int64): TFrAlterBackup;

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
  DRagLint.FieldRepo.BackupManifest,  // dl:ok uses-global-census@e975 -- REVIEWED 2026-11-24 INT-W2: the state names the manifest writes are the names the verb prints
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
  FLAG_CONNECTION = '--connection';
  FLAG_TABLE = '--table';
  FLAG_KEEP = '--keep';
  FLAG_APPLY = '--apply';
  FLAG_DRY_RUN = '--dry-run';
  FLAG_JSON = '--json';
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

{ The first argument that is neither one of pPlain nor one of pValued with a value of its own, or that comes twice; '' = none. }
function StrayArgument(pFrom: Integer; const pValued, pPlain: array of string): string;
var
  VI: Integer;
  VArg: string;
  VSeen: TArray<string>;
begin
  Result := '';
  VSeen := nil;
  VI := pFrom;
  while VI <= ParamCount do
  begin
    VArg := ParamStr(VI).ToLower;
    if MatchText(VArg, VSeen) or not (MatchText(VArg, pValued) or MatchText(VArg, pPlain)) then
      Exit(ParamStr(VI));
    VSeen := VSeen + [VArg];
    if MatchText(VArg, pValued) then
    begin
      Inc(VI);
      if (VI > ParamCount) or (Trim(ParamStr(VI)) = '') or ParamStr(VI).StartsWith('--') then
        Exit(VArg);
    end;
    Inc(VI);
  end;
end;

function IsRepoDbBackup(const pSub, pConnection: string): Boolean;
begin
  Result := SameText(pSub, SUB_BACKUP) and ((pConnection <> '') or
    (StrayArgument(WORD_ARG, ['--repo', '--project', '--output', '--out', '--report'], []) <> ''));
end;

{ What is on the command line that the verb does not take; '' = nothing. }
function StrayForWord(const pWord: string): string;
begin
  if SameText(pWord, WORD_LIST) then
    Result := StrayArgument(WORD_ARG + 1, [FLAG_CONNECTION], [FLAG_JSON])
  else if SameText(pWord, WORD_PURGE) then
    Result := StrayArgument(WORD_ARG + 1, [FLAG_CONNECTION, FLAG_KEEP], [FLAG_APPLY, FLAG_DRY_RUN, FLAG_JSON])
  else
    Result := StrayArgument(WORD_ARG, [FLAG_CONNECTION, '--verify', FLAG_TABLE, '--backup-dir', '--backup-name', '--project'], [FLAG_JSON]);
end;

{ '' = usable; else what is wrong with the arguments of a database backup, its list or its purge. }
function DbBackupProblem(const pWord, pRepo, pConnection: string): string;
var
  VStray: string;
begin
  { 1.54.1 INT: say what to do -- a stray flag beside --repo made this a "database backup" nobody asked for }
  if (pRepo <> '') and (pConnection <> '') then
    Exit('--repo and --connection do not go together: drop --connection for the text backup of the repository ' +
      '(it takes --repo, --project and --output), or drop --repo for a backup of the database; nothing was written');
  if pRepo <> '' then
  begin
    VStray := StrayArgument(WORD_ARG, ['--repo', '--project', '--output', '--out', '--report'], []);
    Exit(Format('"%s" is not an option of the text backup of the repository, which takes --repo, --project and ' +
      '--output only: drop "%s" (a database backup takes --connection instead of --repo); nothing was written', [VStray, VStray]));
  end;
  Result := BackupArgsProblem;
  if (Result <> '') or (MatchText(pWord, [WORD_PURGE]) and (CommandLineValue(FLAG_KEEP) = '')) then
    Exit(if Result <> '' then Result else 'give --keep <number of backups per database>');
  VStray := StrayForWord(pWord);
  if VStray <> '' then
    Result := Format('"%s" does not belong here, has no value or is given twice; nothing was written', [VStray])
  else if (Trim(pConnection) = '') and not MatchText(pWord, [WORD_LIST, WORD_PURGE]) then
    Result := 'give --connection "Database=...;User_Name=...;Password=..." (the text backup of the repository takes --repo, --project and ' +
      '--output only); nothing was written';
end;

{ The database of --connection as the list records it; '' = no --connection. }
function NamedDatabase(const pConnection: string): string;
begin
  Result := if pConnection = '' then '' else FbDatabaseFile(pConnection);
end;

function BackupArgsProblem: string;
var
  VFile, VProblem: string;
begin
  Result := if CommandLineFlag('--verify') and not MatchText(CommandLineValue('--verify'), [VERIFY_FULL, VERIFY_QUICK]) then
    '--verify takes full (default: restore test) or quick' else '';
  if (Result = '') and CommandLineFlag('--backup-name') then
  begin
    VProblem := ResolveBackupName(CommandLineValue('--backup-name'), VFile);
    if VProblem <> '' then
      Result := '--backup-name: ' + VProblem;
  end;
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

function MakeBackup(const pConnection, pTable: string; pIdentity: Int64): TFrAlterBackup;
var
  VRequest: TFrBackupRequest;
  VMade: TFrBackupResult;
begin
  VRequest := Default(TFrBackupRequest);
  VRequest.Connection := pConnection;
  VRequest.BackupDir := BackupDir;
  VRequest.BackupName := CommandLineValue('--backup-name');
  VRequest.TableName := pTable;
  VRequest.Identity := pIdentity;
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

function BackupBeforeApply(const pConnection, pTable: string; pIdentity: Int64): TFrAlterBackup;
begin
  if pIdentity = 0 then
    raise EFrBackupError.Create('no backup, nothing applied: the database does not say which one it is');
  try
    Result := MakeBackup(pConnection, pTable, pIdentity);
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
  VBackup := MakeBackup(pConnection, CommandLineValue(FLAG_TABLE).Trim.ToUpper, 0);
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

{ The recorded backups of one database; '' = of every one. }
function EntriesOf(const pDatabase: string): TArray<TFrBackupEntry>;
var
  VEntry: TFrBackupEntry;
begin
  Result := nil;
  for VEntry in ReadBackupManifest(ManifestFile) do
    if (pDatabase = '') or SameText(VEntry.Database, pDatabase) then
      Result := Result + [VEntry];
end;

function RunList(const pConnection: string; pJson: Boolean): Integer;
var
  VEntries: TArray<TFrBackupEntry>;
  VEntry: TFrBackupEntry;
  VFiles: Integer;
  VTotal: Int64;
  VRoot, VItem: TJSONObject;
  VList: TJSONArray;
begin
  VEntries := EntriesOf(NamedDatabase(pConnection));
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
      Writeln('dry run: nothing deleted (add --apply, with the --connection of the database, to delete)');
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

function RunPurge(const pConnection: string; pJson: Boolean): Integer;
var
  VKeep: Integer;
  VApply: Boolean;
  VItems: TArray<TFrPurgeItem>;
  VItem: TFrPurgeItem;
begin
  if not TryStrToInt(CommandLineValue(FLAG_KEEP), VKeep) then
    raise EFrBackupError.Create('give --keep <number of backups per database>');
  VApply := CommandLineFlag(FLAG_APPLY) and not CommandLineFlag(FLAG_DRY_RUN);
  VItems := PurgeBackups(ManifestFile, NamedDatabase(pConnection), VKeep, VApply);
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
    VProblem := DbBackupProblem(VWord, pRepo, pConnection);
    if VProblem <> '' then
      raise EFrBackupError.Create(VProblem);
    if SameText(VWord, WORD_LIST) then
      Result := RunList(pConnection, pJson)
    else if SameText(VWord, WORD_PURGE) then
      Result := RunPurge(pConnection, pJson)
    else
      Result := RunBackup(pConnection, pJson);
  except
    on E: Exception do
      Writeln(ErrOutput, 'repo backup: ', ScrubSecrets(E.Message, pConnection));
  end;
end;

end.
