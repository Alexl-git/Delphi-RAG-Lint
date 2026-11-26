unit DRagLint.FieldRepo.FbBackup;

{ drag-lint 1.54 -- lane ALTERBK (ruling R9): a Firebird backup through the service API (FireDAC TFDIBBackup /
  TFDIBRestore, no gbak.exe) with a restore test into a temporary database.

  The SERVER writes the backup file and the temporary database, so the server must be on this machine: otherwise free
  space, size and date cannot be checked here. Any other host is refused before anything is opened, as FireDAC resolves
  the connection string; what the open connection reports (attachment, database) is checked again. }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.BackupManifest;

type
  /// <summary>fvmFull = restore into a temporary database and compare; fvmQuick = no restore.</summary>
  TFrVerifyMode = (fvmFull, fvmQuick);

  /// <summary>What to back up and where.</summary>
  TFrBackupRequest = record
    /// <summary>The --connection value.</summary>
    Connection: string;
    /// <summary>Folder for the backup (created when missing); '' = beside the database.</summary>
    BackupDir: string;
    /// <summary>The user's file name (--backup-name), a name and not a path; '' = DLFR_BACKUP_&lt;database&gt;_&lt;date&gt;_&lt;time&gt;.fbk.
    /// .fbk is added when missing; an existing file is never overwritten; the entry is recorded as Named.</summary>
    BackupName: string;
    /// <summary>Test seam: the clock of the default name; nil = Now.</summary>
    Now: TFunc<TDateTime>;
    /// <summary>Table whose row count is compared too; '' = only the table list.</summary>
    TableName: string;
    Verify: TFrVerifyMode;
    /// <summary>What FB_IDENTITY_SQL returned on the connection that is going to change the database; the backup is
    /// refused when its own connection reports another value. 0 = not compared.</summary>
    Identity: Int64;
    /// <summary>Test seam: "protocol|address" of the attachment; nil = ask the server.</summary>
    Attachment: TFunc<string>;
    /// <summary>Test seam: free bytes of a folder; nil = ask the disk.</summary>
    FreeSpace: TFunc<string, Int64>;
    /// <summary>Test seam: called with the file name after the source was read, before the backup starts.</summary>
    BeforeBackup: TProc<string>;
    /// <summary>Test seam: called with the file name after the backup, before the verification.</summary>
    AfterBackup: TProc<string>;
  end;

  /// <summary>What was made.</summary>
  TFrBackupResult = record
    Entry: TFrBackupEntry;
    /// <summary>Tables and views compared; 0 with fvmQuick.</summary>
    Tables: Integer;
    /// <summary>Rows of TableName compared; -1 = not compared.</summary>
    Rows: Int64;
    /// <summary>A temporary database that could not be removed; '' = none.</summary>
    Leftover: string;
  end;

const
  /// <summary>A number that tells one database from another: a hash of its file name with its creation time.</summary>
  FB_IDENTITY_SQL = 'SELECT BIN_XOR(HASH(TRIM(MON$DATABASE_NAME)), ' +
    'CAST(DATEDIFF(MILLISECOND FROM TIMESTAMP ''2000-01-01 00:00:00'' TO CAST(MON$CREATION_DATE AS TIMESTAMP)) AS BIGINT)) ' +
    'FROM MON$DATABASE';

/// <summary>The host FireDAC would connect to with a connection string, when it is not this machine.</summary>
/// <param name="pConnection">The --connection value.</param>
/// <returns>The host (or the protocol that is not supported); '' = this machine.</returns>
/// <exception cref="EFrBackupError">A key is given twice, or there is no Database.</exception>
/// <remarks>Reads FireDAC's own definition ($(NAME) expanded); nothing is opened.</remarks>
function RemoteFbHost(const pConnection: string): string;  // dl:ok unused-public-symbol@3f08 -- REVIEWED 2026-11-23 ALTERBK: the pure part is the test seam; BackupTests.dpr (outside the indexed project) calls it

/// <summary>Refuses a connection string whose server is another machine, or that is ambiguous.</summary>
/// <param name="pConnection">The --connection value.</param>
/// <exception cref="EFrBackupError">The server is not this machine, a key is given twice, or there is no Database.
/// Nothing is opened.</exception>
procedure RequireLocalFbServer(const pConnection: string);

/// <summary>The database file a connection string names.</summary>
/// <param name="pConnection">The --connection value.</param>
/// <returns>MON$DATABASE_NAME, the name the list of backups records.</returns>
/// <exception cref="EFrBackupError">As RequireLocalFbServer, or the server reports a remote attachment.</exception>
/// <remarks>Opens the database and only reads.</remarks>
function FbDatabaseFile(const pConnection: string): string;

/// <summary>Backs a database up, verifies the backup and records it.</summary>
/// <param name="pRequest">What and where.</param>
/// <param name="pManifest">The manifest file (DRagLint.FieldRepo.BackupManifest).</param>
/// <returns>The recorded backup.</returns>
/// <exception cref="EFrBackupError">The server is another machine, there is not enough space, or the backup or its
/// verification failed. A backup that was written but not verified is recorded as 'failed'.</exception>
/// <remarks>Only reads the source database. Free space is checked first: one database size for the backup and, with
/// fvmFull, one more for the temporary database, which has a new unique name in the backup folder and is the only database
/// that is dropped. It is opened without its database triggers. Messages hold no password of their own; the caller scrubs what the driver adds. Not thread-safe.</remarks>
function BackupFbDatabase(const pRequest: TFrBackupRequest; const pManifest: string): TFrBackupResult;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.DateUtils,
  FireDAC.Stan.Option,
  FireDAC.Comp.Client,
  FireDAC.Phys.FB,
  FireDAC.Phys.IBBase,
  FireDAC.Phys.IBWrapper,
  DRagLint.Sql.FbConnString,
  DRagLint.FieldRepo.FbImport,
  DRagLint.FieldRepo.DbProviderFb;

const
  TEMP_PREFIX = 'drag-lint-verify-';
  TEMP_EXT = '.fdb';
  { head room over the size of the database: 10 % }
  SPACE_NUMERATOR = 11;
  SPACE_DENOMINATOR = 10;
  NO_ROWS = -1;
  SQL_TABLES = 'SELECT TRIM(RDB$RELATION_NAME) || '':'' || COALESCE(RDB$RELATION_TYPE, 0) FROM RDB$RELATIONS ' +
    'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1';

type
  { How the connection string reaches the server. }
  TFbTargetKind = (ftkPlain, ftkXnet, ftkTcp, ftkOther);

  TFbTarget = record
    Kind: TFbTargetKind;
    Host: string;
    Port: string;
    { what stands before the path in Database; '' when Server is used }
    Prefix: string;
  end;

  { What the restored copy is compared with, read before the backup starts. }
  TFbSource = record
    FileName: string;
    Bytes: Int64;
    Tables: string;
    TableCount: Integer;
    Rows: Int64;
  end;

  { FireDAC reaches the services of a "local" connection through xnet; a connection string without host and protocol
    opens the file with the engine of the client library, and the service must be the one of the same engine. }
  TEmbeddedServiceScope = record
  private
    FLib: TIBLib;
    FSaved: Boolean;
  public
    procedure Enter(pClient: TObject; pPlain: Boolean);
    procedure Leave;
  end;

  TFrBackupService = class(TFDIBBackup)
  private
    FPlain: Boolean;
  protected
    procedure InternalExecute; override;
  end;

  { A damaged backup makes the embedded engine ask for "the next volume" on the console and wait for an answer; with the
    input of the C runtime it uses (ucrtbase) at NUL it gets end of file and reports the damage. }
  TNoConsoleInput = record
  private
    FSaved: Integer;
  public
    procedure Enter;
    procedure Leave;
  end;

  TFrRestoreService = class(TFDIBRestore)
  private
    FPlain: Boolean;
  protected
    procedure InternalExecute; override;
  end;

procedure TEmbeddedServiceScope.Enter(pClient: TObject; pPlain: Boolean);
begin
  FLib := pClient as TIBLib;
  FSaved := FLib.FEmbedded;
  if pPlain then
    FLib.FEmbedded := True;
end;

procedure TEmbeddedServiceScope.Leave;
begin
  FLib.FEmbedded := FSaved;
end;

{$WARN SYMBOL_PLATFORM OFF} // "delayed" exists on Windows only, and so does this unit
const
  UCRT = 'ucrtbase.dll';
  FD_STDIN = 0;
  O_RDONLY = 0;

function CrtOpen(pName: PAnsiChar; pFlags: Integer): Integer; cdecl; external UCRT name '_open' delayed;
function CrtClose(pFile: Integer): Integer; cdecl; external UCRT name '_close' delayed;
function CrtDup(pFile: Integer): Integer; cdecl; external UCRT name '_dup' delayed;
function CrtDup2(pFrom, pTo: Integer): Integer; cdecl; external UCRT name '_dup2' delayed;

{$WARN SYMBOL_PLATFORM DEFAULT}

procedure TNoConsoleInput.Enter;
var
  VNull: Integer;
begin
  FSaved := CrtDup(FD_STDIN);
  VNull := CrtOpen('NUL', O_RDONLY);
  CrtDup2(VNull, FD_STDIN);
  CrtClose(VNull);
end;

procedure TNoConsoleInput.Leave;
begin
  if FSaved < 0 then
    Exit;
  CrtDup2(FSaved, FD_STDIN);
  CrtClose(FSaved);
end;

procedure TFrBackupService.InternalExecute;
var
  VScope: TEmbeddedServiceScope;
begin
  VScope.Enter(TObject(CliObj), FPlain);
  try
    inherited InternalExecute;
  finally
    VScope.Leave;
  end;
end;

procedure TFrRestoreService.InternalExecute;
var
  VScope: TEmbeddedServiceScope;
  VInput: TNoConsoleInput;
begin
  VScope.Enter(TObject(CliObj), FPlain);
  try
    VInput.Enter;
    try
      inherited InternalExecute;
    finally
      VInput.Leave;
    end;
  finally
    VScope.Leave;
  end;
end;

{ The first key a connection string gives twice; FireDAC takes the first value, a reader may see the last. }
function DuplicateKey(const pConnection: string): string;
var
  VKeys: TStringList;
  VPair, VKey: string;
begin
  Result := '';
  VKeys := TStringList.Create;
  try
    for VPair in pConnection.Split([';'], TStringSplitOptions.ExcludeEmpty) do
    begin
      VKey := Trim(Copy(VPair, 1, Pos('=', VPair + '=') - 1));
      if VKey = '' then
        Continue;
      if VKeys.IndexOf(VKey) >= 0 then
        Exit(VKey);
      VKeys.Add(VKey);
    end;
  finally
    VKeys.Free;
  end;
end;

{ The definition FireDAC would open, built as OpenSourceConnection does; it is never opened. The caller frees it. }
function FbDefinition(const pConnection: string): TFDConnection;
var
  VKey, VPair: string;
begin
  VKey := DuplicateKey(pConnection);
  if VKey <> '' then
    raise EFrBackupError.CreateFmt('%s is given twice in --connection: which one counts is not clear', [VKey]);
  Result := TFDConnection.Create(nil);
  try
    for VPair in pConnection.Split([';'], TStringSplitOptions.ExcludeEmpty) do
      if VPair.Contains('=') then
        Result.Params.Add(Trim(Copy(VPair, 1, Pos('=', VPair) - 1)) + '=' + Trim(Copy(VPair, Pos('=', VPair) + 1, MaxInt)));
    if Result.Params.Values['Database'].Trim = '' then
      raise EFrBackupError.Create('--connection has no Database');
  except
    Result.Free;
    raise;
  end;
end;
{ 'host/port' -> host, port; the port of the string wins over pPort }
procedure SplitHost(const pText, pPort: string; pSeparator: Char; var pTarget: TFbTarget);
var
  VPos: Integer;
begin
  VPos := Pos(pSeparator, pText);
  pTarget.Kind := ftkTcp;
  pTarget.Host := if VPos > 0 then Copy(pText, 1, VPos - 1) else pText;
  pTarget.Port := if VPos > 0 then Copy(pText, VPos + 1, MaxInt) else pPort;
end;

procedure ParseUrl(const pDatabase: string; var pTarget: TFbTarget);
const
  SCHEME_END = '://';
  INET: array[0..2] of string = ('inet', 'inet4', 'inet6');
  XNET = 'xnet';
var
  VScheme, VRest: string;
  VSlash: Integer;
begin
  VScheme := Copy(pDatabase, 1, Pos(SCHEME_END, pDatabase) - 1);
  VRest := Copy(pDatabase, Length(VScheme) + Length(SCHEME_END) + 1, MaxInt);
  if SameText(VScheme, XNET) then
  begin
    pTarget.Kind := ftkXnet;
    pTarget.Prefix := VScheme + SCHEME_END;
  end
  else if MatchText(VScheme, INET) then
  begin
    VSlash := Pos('/', VRest);
    SplitHost(Copy(VRest, 1, VSlash - 1), '', ':', pTarget);
    pTarget.Prefix := VScheme + SCHEME_END + Copy(VRest, 1, VSlash);
  end
  else
  begin
    pTarget.Kind := ftkOther;
    pTarget.Host := VScheme;
  end;
end;

{ The port as FireDAC takes it: Port before InstanceName. }
function TargetPort(pConn: TFDConnection): string;
begin
  Result := pConn.Params.Values['Port'].Trim;
  if Result = '' then
    Result := pConn.Params.Values['InstanceName'].Trim;
end;

function ParseTarget(pConn: TFDConnection): TFbTarget;
const
  PROTOCOL_TCP = 'TCPIP';
  PROTOCOL_LOCAL = 'Local';
  DRIVE_COLON = 2;
var
  VServer, VProtocol, VDatabase: string;
  VColon: Integer;
begin
  Result := Default(TFbTarget);
  VServer := pConn.Params.Values['Server'].Trim;
  VProtocol := pConn.Params.Values['Protocol'].Trim;
  VDatabase := pConn.Params.ExpandedDatabase;
  VColon := Pos(':', VDatabase);
  if (VProtocol <> '') and not MatchText(VProtocol, [PROTOCOL_TCP, PROTOCOL_LOCAL]) then
  begin
    Result.Kind := ftkOther;
    Result.Host := VProtocol;
  end
  else if ((VServer <> '') or (VProtocol <> '')) and (VColon > DRIVE_COLON) then
  begin
    { a host in Server / Protocol and another one in Database: the first would be asked to connect to the second }
    Result.Kind := ftkOther;
    Result.Host := Copy(VDatabase, 1, VColon - 1);
  end
  else if (VServer <> '') or SameText(VProtocol, PROTOCOL_TCP) then
    SplitHost(VServer, TargetPort(pConn), '/', Result)
  else if SameText(VProtocol, PROTOCOL_LOCAL) then
    Result.Kind := ftkXnet
  else if VDatabase.Contains('://') then
    ParseUrl(VDatabase, Result)
  else if VDatabase.StartsWith('\\') then
  begin
    Result.Kind := ftkOther;
    Result.Host := Copy(VDatabase, 1, Pos('\', VDatabase + '\', Length('\\') + 1) - 1);
  end
  else if VColon > DRIVE_COLON then
  begin
    SplitHost(Copy(VDatabase, 1, VColon - 1), '', '/', Result);
    Result.Prefix := Copy(VDatabase, 1, VColon);
  end;
end;

function RemoteTargetHost(const pTarget: TFbTarget): string;
const
  LOCAL_HOSTS: array[0..4] of string = ('', 'localhost', '127.0.0.1', '::1', '[::1]');  // dl:ok hardcoded-ip-address@2bf6 -- REVIEWED 2026-11-23 ALTERBK: the loopback names are what "this machine" means; nothing to configure
begin
  Result := '';
  if (pTarget.Kind = ftkOther) or ((pTarget.Kind = ftkTcp) and not MatchText(pTarget.Host, LOCAL_HOSTS) and
    not SameText(pTarget.Host, GetEnvironmentVariable('COMPUTERNAME'))) then
    Result := pTarget.Host;
end;

function RemoteFbHost(const pConnection: string): string;
var
  VDefinition: TFDConnection;
begin
  VDefinition := FbDefinition(pConnection);
  try
    Result := RemoteTargetHost(ParseTarget(VDefinition));
  finally
    VDefinition.Free;
  end;
end;

procedure RefuseRemote(const pHost: string);
begin
  if pHost <> '' then
    raise EFrBackupError.CreateFmt('the server is not on this machine (%s): it would write the backup on its own disk, where ' +
      'drag-lint can check neither space nor file; run the command on the server', [pHost]);
end;

procedure RequireLocalFbServer(const pConnection: string);
begin
  RefuseRemote(RemoteFbHost(pConnection));
end;

{ The address of an attachment ("protocol|address" of MON$ATTACHMENTS) that does not come from this machine; '' = it does:
  no protocol (embedded), XNET, a loopback address. }
function RemoteAddress(const pAttachment: string): string;
const
  XNET = 'XNET';
  TCP = 'TCP';
  LOOPBACK: array[0..2] of string = ('127.', '::1', '::ffff:127.');
var
  VProtocol, VAddress, VLoop: string;
begin
  VProtocol := Copy(pAttachment, 1, Pos('|', pAttachment) - 1);
  VAddress := Copy(pAttachment, Pos('|', pAttachment) + 1, MaxInt);
  if VAddress.Contains('/') then
    VAddress := Copy(VAddress, 1, Pos('/', VAddress) - 1);
  if (VProtocol = '') or SameText(VProtocol, XNET) then
    Exit('');
  if not VProtocol.StartsWith(TCP, True) then
    Exit(VProtocol);
  for VLoop in LOOPBACK do
    if SameText(VAddress, VLoop) or (VLoop.EndsWith('.') and VAddress.StartsWith(VLoop, True)) then
      Exit('');
  Result := if VAddress = '' then VProtocol else VAddress;
end;

procedure PlainSql(pConn: TFDConnection);
begin
  pConn.TxOptions.ReadOnly := True;
  pConn.ResourceOptions.MacroCreate := False;
  pConn.ResourceOptions.MacroExpand := False;
  pConn.ResourceOptions.EscapeExpand := False;
end;
{ Opens the database, with what FireDAC connected to and what the server says about the attachment checked. }
function OpenLocal(const pConnection: string; const pAttachment: TFunc<string>; out pTarget: TFbTarget): TFDConnection;
const
  SQL_ATTACHMENT = 'SELECT COALESCE(TRIM(MON$REMOTE_PROTOCOL), '''') || ''|'' || COALESCE(TRIM(MON$REMOTE_ADDRESS), '''') ' +
    'FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID = CURRENT_CONNECTION';
var
  VDatabase, VReported: string;
begin
  RequireFbConnectionSafe(pConnection);
  RequireLocalFbServer(pConnection);
  Result := OpenSourceConnection(pConnection, VDatabase);
  try
    PlainSql(Result);
    pTarget := ParseTarget(Result);
    RefuseRemote(RemoteTargetHost(pTarget));
    VReported := if Assigned(pAttachment) then pAttachment() else string(Result.ExecSQLScalar(SQL_ATTACHMENT));
    { a connection to the own name of this machine does not come from a loopback address }
    if not SameText(pTarget.Host, GetEnvironmentVariable('COMPUTERNAME')) or (pTarget.Host = '') then
      RefuseRemote(RemoteAddress(VReported));
  except
    Result.Free;
    raise;
  end;
end;

function DatabaseFile(pConn: TFDConnection): string;
begin
  Result := Trim(string(pConn.ExecSQLScalar('SELECT MON$DATABASE_NAME FROM MON$DATABASE')));
end;

function FbDatabaseFile(const pConnection: string): string;
var
  VConn: TFDConnection;
  VTarget: TFbTarget;
begin
  VConn := OpenLocal(pConnection, nil, VTarget);
  try
    Result := DatabaseFile(VConn);
  finally
    VConn.Free;
  end;
end;

function FreeBytes(const pRequest: TFrBackupRequest; const pDir: string): Int64;
var
  VFree, VTotal: Int64;
begin
  if Assigned(pRequest.FreeSpace) then
    Exit(pRequest.FreeSpace(pDir));
  if not GetDiskFreeSpaceEx(PChar(IncludeTrailingPathDelimiter(pDir)), VFree, VTotal, nil) then
    raise EFrBackupError.CreateFmt('the free space of %s is not known: %s', [pDir, SysErrorMessage(GetLastError)]);
  Result := VFree;
end;


function TableList(pConn: TFDConnection; out pCount: Integer): string;
var
  VQuery: TFDQuery;
  VNames: TStringList;
begin
  VNames := TStringList.Create;
  try
    VQuery := TFDQuery.Create(nil);
    try
      VQuery.Connection := pConn;
      VQuery.Open(SQL_TABLES);
      while not VQuery.Eof do
      begin
        VNames.Add(VQuery.Fields[0].AsString);
        VQuery.Next;
      end;
      VQuery.Close;
    finally
      VQuery.Free;
    end;
    pCount := VNames.Count;
    Result := VNames.Text;
  finally
    VNames.Free;
  end;
end;

function CountTable(pConn: TFDConnection; const pTable: string): Int64;
begin
  Result := if pTable = '' then NO_ROWS else Int64(pConn.ExecSQLScalar(FirebirdDialect.CountRows(pTable)));
end;

function ReadSource(pConn: TFDConnection; const pTable: string): TFbSource;
begin
  Result.FileName := DatabaseFile(pConn);
  Result.Bytes := Int64(pConn.ExecSQLScalar('SELECT CAST(MON$PAGES AS BIGINT) * MON$PAGE_SIZE FROM MON$DATABASE'));
  Result.Tables := TableList(pConn, Result.TableCount);
  Result.Rows := CountTable(pConn, pTable);
  if not TFile.Exists(Result.FileName) then
    raise EFrBackupError.CreateFmt('the database file is not on this machine: %s; run the command on the server', [Result.FileName]);
end;

{ The folder, usable, with the space the backup (and the restore test) can need. }
function PrepareFolder(const pRequest: TFrBackupRequest; const pSource: TFbSource): string;
const
  BACKUP_ONLY = 1;
  BACKUP_AND_RESTORE = 2;
var
  VNeed, VFree: Int64;
begin
  Result := if pRequest.BackupDir <> '' then ExpandFileName(pRequest.BackupDir) else ExtractFilePath(pSource.FileName);
  Result := ExcludeTrailingPathDelimiter(Result);
  if Result.Contains('=') then
    raise EFrBackupError.CreateFmt('the backup folder must not hold "=" in its name: %s', [Result]);
  if ExtractFileName(pSource.FileName).Contains('=') then
    raise EFrBackupError.CreateFmt('the Firebird service cannot back up a database with "=" in its name: %s', [pSource.FileName]);
  if TFile.Exists(Result) then
    raise EFrBackupError.CreateFmt('the backup folder is a file: %s', [Result]);
  if not ForceDirectories(Result) then
    raise EFrBackupError.CreateFmt('the backup folder cannot be created: %s', [Result]);
  VNeed := pSource.Bytes * (if pRequest.Verify = fvmFull then BACKUP_AND_RESTORE else BACKUP_ONLY);
  VNeed := VNeed div SPACE_DENOMINATOR * SPACE_NUMERATOR;
  VFree := FreeBytes(pRequest, Result);
  if VFree < VNeed then
    raise EFrBackupError.CreateFmt('not enough space in %s: %d bytes needed, %d free%s', [Result, VNeed, VFree,
      if pRequest.Verify = fvmFull then ' (--verify quick needs half)' else '']);
end;

procedure SetupService(pService: TFDIBService; const pTarget: TFbTarget; pConn: TFDConnection);
var
  VPort: Integer;
begin
  pService.UserName := pConn.Params.UserName;
  pService.Password := pConn.Params.Password;
  pService.SqlRoleName := pConn.Params.Values['RoleName'];
  if pTarget.Kind <> ftkTcp then
    Exit;
  pService.Protocol := ipTCPIP;
  pService.Host := if pTarget.Host = '' then 'localhost' else pTarget.Host;
  if TryStrToInt(pTarget.Port, VPort) then
    pService.Port := VPort
  else
    pService.InstanceName := pTarget.Port;
end;

procedure RunBackupService(const pTarget: TFbTarget; pConn: TFDConnection; const pSource: TFbSource; const pFile: string);
var
  VLink: TFDPhysFBDriverLink;
  VService: TFrBackupService;
begin
  VLink := TFDPhysFBDriverLink.Create(nil);
  try
    VService := TFrBackupService.Create(nil);
    try
      VService.DriverLink := VLink;
      VService.FPlain := pTarget.Kind = ftkPlain;
      SetupService(VService, pTarget, pConn);
      VService.Database := pSource.FileName;
      VService.BackupFiles.Text := pFile;
      VService.Options := [boNoGarbageCollect];
      VService.Backup;
    finally
      VService.Free;
    end;
  finally
    VLink.Free;
  end;
end;

procedure RunRestoreService(const pTarget: TFbTarget; pConn: TFDConnection; const pFile, pTemp: string);
var
  VLink: TFDPhysFBDriverLink;
  VService: TFrRestoreService;
begin
  VLink := TFDPhysFBDriverLink.Create(nil);
  try
    VService := TFrRestoreService.Create(nil);
    try
      VService.DriverLink := VLink;
      VService.FPlain := pTarget.Kind = ftkPlain;
      SetupService(VService, pTarget, pConn);
      VService.BackupFiles.Text := pFile;
      VService.Database := pTemp;
      { no roReplace: an existing file is refused by the server }
      VService.Options := [];
      VService.Restore;
    finally
      VService.Free;
    end;
  finally
    VLink.Free;
  end;
end;

{ A connection to the temporary database; DropDatabase removes it when the connection closes. }
function OpenTemp(const pTarget: TFbTarget; pConn: TFDConnection; const pTemp: string): TFDConnection;
var
  VAdvanced: string;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.Params.Assign(pConn.Params);
    Result.Params.Values['Database'] := pTarget.Prefix + pTemp;
    Result.Params.Values['DropDatabase'] := 'Yes';
    { a trigger ON CONNECT may act outside the database }
    VAdvanced := Result.Params.Values['IBAdvanced'].Trim;
    Result.Params.Values['IBAdvanced'] := VAdvanced + (if VAdvanced = '' then '' else ';') + 'no_db_triggers=1';
    PlainSql(Result);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

procedure CompareTemp(pTemp: TFDConnection; const pSource: TFbSource; const pTable: string);
const
  ONLINE = 0;
var
  VCount: Integer;
  VRows: Int64;
begin
  { the service can end an interrupted restore without an error; only its last step puts the new database online }
  if Integer(pTemp.ExecSQLScalar('SELECT MON$SHUTDOWN_MODE FROM MON$DATABASE')) <> ONLINE then
    raise EFrBackupError.Create('the restore did not run to its end: the backup is damaged');
  if TableList(pTemp, VCount) <> pSource.Tables then
    raise EFrBackupError.CreateFmt('the restored database has another table list (%d instead of %d)', [VCount, pSource.TableCount]);
  VRows := CountTable(pTemp, pTable);
  if VRows <> pSource.Rows then
    raise EFrBackupError.CreateFmt('table %s has %d row(s) in the restored database and %d in the source (is somebody writing to it?)',
      [pTable, VRows, pSource.Rows]);
end;

{ Removes a file this run made under a name that was free before. Returns the name when it is still there. }
function RemoveOwnFile(const pFile: string): string;
begin
  Result := if not System.SysUtils.DeleteFile(pFile) and TFile.Exists(pFile) then pFile else '';
end;

procedure VerifyByRestore(const pRequest: TFrBackupRequest; const pTarget: TFbTarget; pConn: TFDConnection;
  const pSource: TFbSource; var pResult: TFrBackupResult);
var
  VTemp: string;
  VConn: TFDConnection;
begin
  VTemp := TPath.Combine(ExtractFilePath(pResult.Entry.FileName), TEMP_PREFIX + TGUID.NewGuid.ToString.Trim(['{', '}']) + TEMP_EXT);
  try
    RunRestoreService(pTarget, pConn, pResult.Entry.FileName, VTemp);
    VConn := OpenTemp(pTarget, pConn, VTemp);
    try
      CompareTemp(VConn, pSource, pRequest.TableName);
    finally
      VConn.Free;
    end;
  finally
    { usually gone by now: the connection dropped it }
    pResult.Leftover := RemoveOwnFile(VTemp);
  end;
  pResult.Entry.Verified := fbvFull;
  pResult.Tables := pSource.TableCount;
  pResult.Rows := pSource.Rows;
end;

{ The path of the new backup: the user's --backup-name, or the default name; a default name taken by a backup of the same second gets _2, _3 ... }
function ChooseFile(const pRequest: TFrBackupRequest; const pSource: TFbSource; var pEntry: TFrBackupEntry): string;
const
  FIRST_SUFFIX = 2;
var
  VFolder, VName, VProblem: string;
  VNow: TDateTime;
  VSuffix: Integer;
begin
  VFolder := PrepareFolder(pRequest, pSource);
  if pRequest.BackupName <> '' then
  begin
    VProblem := ResolveBackupName(pRequest.BackupName, VName);
    if VProblem <> '' then
      raise EFrBackupError.CreateFmt('--backup-name: %s', [VProblem]);
    pEntry.Named := True;
    Exit(TPath.Combine(VFolder, VName));
  end;
  VNow := if Assigned(pRequest.Now) then pRequest.Now() else Now;
  VSuffix := 0;
  Result := TPath.Combine(VFolder, BackupFileName(pSource.FileName, VNow));
  while TFile.Exists(Result) or TDirectory.Exists(Result) do
  begin
    VSuffix := if VSuffix = 0 then FIRST_SUFFIX else VSuffix + 1;
    Result := TPath.Combine(VFolder, BackupFileName(pSource.FileName, VNow, VSuffix));
  end;
end;
function WriteBackup(const pRequest: TFrBackupRequest; const pTarget: TFbTarget; pConn: TFDConnection; const pSource: TFbSource): TFrBackupEntry;
begin
  Result := Default(TFrBackupEntry);
  Result.Database := pSource.FileName;
  Result.CreatedUtc := TTimeZone.Local.ToUniversalTime(Now);
  Result.FileName := ChooseFile(pRequest, pSource, Result);
  if Assigned(pRequest.BeforeBackup) then
    pRequest.BeforeBackup(Result.FileName);
  if TFile.Exists(Result.FileName) or TDirectory.Exists(Result.FileName) then
    raise EFrBackupError.CreateFmt('the backup file exists already: %s', [Result.FileName]);
  try
    RunBackupService(pTarget, pConn, pSource, Result.FileName);
  except
    on E: Exception do
      raise EFrBackupError.CreateFmt('the backup failed: %s%s', [E.Message,
        if RemoveOwnFile(Result.FileName) <> '' then '; an incomplete file is left: ' + Result.FileName else '']);
  end;
  if not TFile.Exists(Result.FileName) then
    raise EFrBackupError.CreateFmt('the server reported no error but %s is not there', [Result.FileName]);
  Result.Size := TFile.GetSize(Result.FileName);
  Result.ModifiedUtc := TFile.GetLastWriteTimeUtc(Result.FileName);
  Result.Verified := fbvQuick;
  if Result.Size = 0 then
    raise EFrBackupError.CreateFmt('the backup file is empty: %s%s', [Result.FileName, if RemoveOwnFile(Result.FileName) = '' then ' (removed)' else '']);
end;

{ Adds a backup to the list. Returns '' or what went wrong, the file named: it stays on disk unlisted. }
function Recorded(const pManifest: string; const pEntry: TFrBackupEntry): string;
begin
  Result := '';
  try
    AddToBackupManifest(pManifest, pEntry);
  except
    on E: Exception do
      Result := Format('the backup %s is there but not in the list: %s', [pEntry.FileName, E.Message]);
  end;
end;

function BackupFbDatabase(const pRequest: TFrBackupRequest; const pManifest: string): TFrBackupResult;
var
  VTarget: TFbTarget;
  VConn: TFDConnection;
  VSource: TFbSource;
  VUnlisted: string;
begin
  { a list that cannot be written to must be found before the work }
  ReadBackupManifest(pManifest);
  Result := Default(TFrBackupResult);
  Result.Rows := NO_ROWS;
  VConn := OpenLocal(pRequest.Connection, pRequest.Attachment, VTarget);
  try
    if (pRequest.Identity <> 0) and (Int64(VConn.ExecSQLScalar(FB_IDENTITY_SQL)) <> pRequest.Identity) then
      raise EFrBackupError.CreateFmt('the backup connection reached another database (%s) than the one to be changed', [DatabaseFile(VConn)]);
    VSource := ReadSource(VConn, pRequest.TableName);
    Result.Entry := WriteBackup(pRequest, VTarget, VConn, VSource);
    if Assigned(pRequest.AfterBackup) then
      pRequest.AfterBackup(Result.Entry.FileName);
    if pRequest.Verify = fvmFull then
      try
        VerifyByRestore(pRequest, VTarget, VConn, VSource, Result);
      except
        on E: Exception do
        begin
          Result.Entry.Verified := fbvFailed;
          VUnlisted := Recorded(pManifest, Result.Entry);
          raise EFrBackupError.CreateFmt('the backup %s was written but its verification failed: %s%s%s', [Result.Entry.FileName,
            E.Message, if Result.Leftover <> '' then '; the temporary database is left: ' + Result.Leftover else '',
            if VUnlisted <> '' then '; ' + VUnlisted else '']);
        end;
      end;
  finally
    VConn.Free;
  end;
  VUnlisted := Recorded(pManifest, Result.Entry);
  if VUnlisted <> '' then
    raise EFrBackupError.Create(VUnlisted);
end;

end.
