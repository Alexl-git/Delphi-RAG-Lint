unit DRagLint.MCP.ClientConfig;

/// <summary>`drag-lint mcp-config` -- registers drag-lint's MCP server (`drag-lint serve`) with Claude Code and
/// VS Code by editing their user-level config files.</summary>
/// <remarks>
/// <para>A port of charts\src\Set-DragLintMcpConfig.ps1 in its FILE-EDIT mode, which it replaces. The script's
/// `claude mcp` CLI mode is not ported (owner decision 4): this unit never runs a child process.</para>
/// <para>Targets: Claude Code -- the top-level "mcpServers" object of &lt;CLAUDE_CONFIG_DIR or home&gt;\.claude.json;
/// VS Code -- the "servers" object of &lt;APPDATA&gt;\Code\User\mcp.json.</para>
/// <para>This edits a real user's configuration, so every write is merged (only the one named entry changes),
/// backed up, re-checked just before it lands, and refused rather than guessed at when the file holds comments,
/// trailing commas or anything that is not a JSON object. env VALUES are never printed (they may be secrets).</para>
/// <para>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</para>
/// </remarks>

interface

type
  /// <summary>The MCP clients whose user-level config this verb edits.</summary>
  TMcpClient = (mcClaudeCode, mcVSCode, mcCursor);

  /// <summary>One run of mcp-config against one client file.</summary>
  TMcpConfigRequest = record
    /// <summary>Which client's file and container ("mcpServers" or "servers").</summary>
    Client    : TMcpClient;
    /// <summary>The file to edit; '' = the client's default file.</summary>
    ConfigPath: string;
    /// <summary>Where the Claude Code and Cursor default files are looked for; '' = %USERPROFILE%. CLAUDE_CONFIG_DIR still wins for Claude Code.</summary>
    HomeDir   : string;
    /// <summary>Where the VS Code default file is looked for; '' = %APPDATA%.</summary>
    AppDataDir: string;
    /// <summary>The entry name; letters, digits, '_', '.' or '-'.</summary>
    Name      : string;
    /// <summary>The engine the entry runs; '' = ParamStr(0). Stored as a full path.</summary>
    Engine    : string;
    /// <summary>The index the entry serves; '' = args ["serve"]. Must exist; stored as a full path.</summary>
    DbPath    : string;
    /// <summary>Take our entry out instead of adding or updating it.</summary>
    Remove    : Boolean;
    /// <summary>Report the action with a would- prefix and write nothing.</summary>
    DryRun    : Boolean;
    /// <summary>A client that is not installed is skipped, not refused.</summary>
    AllMode   : Boolean;
  end;

  /// <summary>What happened to one client file: the script's Target/Path/Action/Backup/Before/After.</summary>
  TMcpConfigResult = record
    /// <summary>ClaudeCode, VSCode or Cursor.</summary>
    Target  : string;
    /// <summary>The file read (and written).</summary>
    Path    : string;
    /// <summary>added|updated|unchanged|removed|absent (would- prefixed on a dry run), skipped, or refused.</summary>
    Action  : string;
    /// <summary>The backup written; '' when none (no file before, no write, or a dry run). Kept on a refusal that
    /// comes after the backup was taken (the copy exists).</summary>
    Backup  : string;
    /// <summary>The entry before, compact JSON with env/headers values as ***; '(none)' when absent; '(not ours)'
    /// when it runs something else (its body is never printed).</summary>
    Before  : string;
    /// <summary>The entry after, compact JSON with env/headers values as ***; '(none)' when removed or absent.</summary>
    After   : string;
    /// <summary>Why the run was refused; '' when ExitCode is 0.</summary>
    Error   : string;
    /// <summary>0 done, 1 refused, 2 setup.</summary>
    ExitCode: Integer;
  end;

/// <summary>Adds, updates or removes the drag-lint MCP server entry in one client's config file.</summary>
/// <param name="pRequest">Which client, which file, which entry and whether to write.</param>
/// <returns>Action added|updated|unchanged|removed|absent|skipped (would- prefixed on a dry run); ExitCode 0 on
/// any of those, 1 refused (Error set: not ours, not valid JSON, holds comments or trailing commas, the top level
/// or the container not an object, changed / deleted / appeared while running), 2 setup (the named client is not
/// installed, --db or the engine missing, an invalid name).</returns>
/// <remarks>Merges: only the entry named pRequest.Name changes; every other key and server is carried through
/// System.JSON unchanged (member order and number text kept). An update keeps keys the user added to OUR entry
/// (env, ...); "same" means type (absent = stdio), command (case-insensitive) and args (exact) all match, and then
/// nothing is written. An entry by that name whose command is neither drag-lint.exe nor the engine is not ours and
/// is never updated or removed. A write first copies the file to &lt;file&gt;.bak-&lt;yyyyMMdd-HHmmss&gt; (-fff
/// when taken), writes &lt;file&gt;.tmp-&lt;pid&gt; as UTF-8 without BOM in the file's own line-ending style, and
/// moves it into place after re-checking the file did not change; nothing is ever written on a refusal. A file that
/// did not exist gets no backup, its folder is created, and CRLF. Before/After/paste-hint text masks env VALUES as
/// ***, and so do `headers` values (an HTTP entry's token); an entry refused as not ours prints only (not ours) as
/// Before, never its body. Never runs a child process (the claude CLI mode of Set-DragLintMcpConfig.ps1 is not ported; owner
/// decision 4).</remarks>
function ApplyMcpConfig(const pRequest: TMcpConfigRequest): TMcpConfigResult;

/// <summary>The entry this verb writes, as compact JSON text (the paste hint).</summary>
/// <param name="pClient">Claude Code entries carry "env":{}; VS Code entries do not.</param>
/// <param name="pEngine">The command, written as given.</param>
/// <param name="pDbPath">'' gives args ["serve"], else ["serve","--db",pDbPath].</param>
/// <returns>{"type":"stdio","command":...,"args":[...]} (+ "env":{} for Claude Code).</returns>
function McpEntryText(pClient: TMcpClient; const pEngine, pDbPath: string): string;

/// <summary>Entry point of `drag-lint mcp-config`; parses ParamStr(2..) itself.</summary>
/// <returns>The worst exit code over the targets; 2 with usage on stderr when no target is named, for an unknown
/// flag, a flag missing its value, --config-path with other than exactly one target, or an invalid --name. A --db
/// that does not exist is 2 from ApplyMcpConfig, per target.</returns>
/// <remarks>Prints one block per target (Target, Path, Action, Backup, Before, After) or, with --json, one JSON
/// array of those objects (plus Error and ExitCode). A refusal's reason also goes to stderr.</remarks>
function RunMcpConfigVerbFromCommandLine: Integer;

/// <summary>Entry point of `drag-lint init`; parses ParamStr(2..) itself.</summary>
/// <returns>0 when every step succeeded (or on --dry-run); 2 with usage on stderr when --project is missing, a flag
/// is unknown or lacks its value, or the project file does not exist; otherwise the exit code of the step that
/// failed (the run stops there).</returns>
/// <remarks>Composed of existing verbs, each run as a child of this exe: (1) `register-project &lt;proj&gt; --apply`
/// (the manifest section, a no-op when already registered), (2) `index --project &lt;proj&gt;`, (3) `resolve-dbs
/// --project &lt;proj&gt;` to learn the project's index, (4) `mcp-config --all --db &lt;that index&gt;` (Claude Code,
/// VS Code and Cursor; a client that is not installed is skipped). --dry-run prints those four command lines and runs
/// NOTHING, so nothing is written. --home-dir / --appdata-dir are passed on to mcp-config (they move where the client
/// files are looked for). Each step's output is echoed under a "step n/4" heading.</remarks>
function RunInitVerbFromCommandLine: Integer;

implementation
uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,  // dl:ok unused-unit-in-uses@0dbd -- REVIEWED 2026-10-14: no symbol is named from it, but TJSONObject.Get / TJSONArray.Items are inline and expand through it; without it dcc emits H2443 at every call
  System.JSON,
  DRagLint.Charts.Process;

type
  { The verb's flags. tests\autotest\run_docs_sync_guard.ps1 reads MCP_CONFIG_FLAG_NAMES as the set this verb
    accepts (ParseArgs returns before its own chain for `mcp-config`), so keep the table and the parser one. }
  TMcpConfigFlag = (mfClaudeCode, mfVSCode, mfAll, mfRemove, mfDryRun, mfName, mfDb, mfEngine, mfConfigPath,
    mfJson, mfHomeDir, mfAppDataDir, mfCursor);
  TMcpClients = set of TMcpClient;

  { A refusal (EXIT_REFUSED) or a setup failure (EXIT_SETUP), carried out of the deep helpers to ApplyMcpConfig. }
  EMcpConfigStop = class(Exception)
  private
    FCode: Integer;
  public
    constructor CreateCode(pCode: Integer; const pMsg: string);
    property Code: Integer read FCode;
  end;

  { The config file as read: its raw bytes and stamp are what the pre-write re-check compares against. }
  TConfigFile = record
    Exists : Boolean;
    Bytes  : TBytes;
    Stamp  : Int64;
    NewLine: string;
    Root   : TJSONObject;
  end;

const
  MCP_CONFIG_FLAG_NAMES: array[TMcpConfigFlag] of string = ('--claude-code', '--vscode', '--all', '--remove',
    '--dry-run', '--name', '--db', '--engine', '--config-path', '--json', '--home-dir', '--appdata-dir', '--cursor');
  { the flags that take a value (the next ParamStr) }
  VALUE_FLAGS = [mfName, mfDb, mfEngine, mfConfigPath, mfHomeDir, mfAppDataDir];
  TARGET_NAMES   : array[TMcpClient] of string = ('ClaudeCode', 'VSCode', 'Cursor');
  CONTAINER_NAMES: array[TMcpClient] of string = ('mcpServers', 'servers', 'mcpServers');

  EXIT_OK      = 0;
  EXIT_REFUSED = 1;
  EXIT_SETUP   = 2;

  DEFAULT_NAME     = 'drag-lint';
  ENGINE_EXE       = 'drag-lint.exe';
  CLAUDE_FILE      = '.claude.json';
  CLAUDE_DIR       = '.claude';
  CLAUDE_DIR_ENV   = 'CLAUDE_CONFIG_DIR';
  VSCODE_USER_DIR  = 'Code\User';
  VSCODE_FILE      = 'mcp.json';
  CURSOR_DIR       = '.cursor';
  CURSOR_FILE      = 'mcp.json';
  NONE_TEXT        = '(none)';
  MASK_TEXT        = '***';
  STAMP_FORMAT     = 'yyyymmdd-hhnnss';
  STAMP_MS_FORMAT  = 'yyyymmdd-hhnnss-zzz';
  JSON_INDENT      = 2;
  FIRST_FLAG_PARAM = 2;  // ParamStr(1) is `mcp-config`
  UTF8_BOM_LEN     = 3;
  FILETIME_HIGH_SHIFT = 32;  // FILETIME is two DWORDs: high << 32 | low
  BOM_BYTE_1       = $EF;
  BOM_BYTE_2       = $BB;
  BOM_BYTE_3       = $BF;
  CRLF             = #13#10;
  LF               = #10;
  NAME_CHARS       = ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-'];
  { the keys that decide "same server" and the only ones an update rewrites }
  SERVER_KEYS: array[0..2] of string = ('type', 'command', 'args');
  { the members whose values may be secrets: masked as *** wherever an entry is printed }
  SECRET_KEYS: array[0..1] of string = ('env', 'headers');
  NOT_OURS_TEXT = '(not ours)';

constructor EMcpConfigStop.CreateCode(pCode: Integer; const pMsg: string);
begin
  inherited Create(pMsg);
  FCode:= pCode;
end;

procedure Stop(pCode: Integer; const pMsg: string);
begin
  raise EMcpConfigStop.CreateCode(pCode, pMsg);
end;

function ValidName(const pName: string): Boolean;
begin
  Result:= pName <> '';
  for var C in pName do
    if not CharInSet(C, NAME_CHARS) then Exit(False);
end;

function EntryArgs(const pDbPath: string): TJSONArray;
begin
  Result:= TJSONArray.Create;
  Result.Add('serve');
  if pDbPath <> '' then
  begin
    Result.Add('--db');
    Result.Add(pDbPath);
  end;
end;

function BuildEntry(pClient: TMcpClient; const pEngine, pDbPath: string): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('type', 'stdio');
  Result.AddPair('command', pEngine);
  Result.AddPair('args', EntryArgs(pDbPath));
  if pClient = mcClaudeCode then Result.AddPair('env', TJSONObject.Create);
end;

function McpEntryText(pClient: TMcpClient; const pEngine, pDbPath: string): string;
begin
  var Entry:= BuildEntry(pClient, pEngine, pDbPath);
  try
    Result:= Entry.ToJSON;
  finally
    Entry.Free;
  end;
end;

{ Masks pObj.pKey in place: an object's VALUES become *** (its keys stay, so a change is still readable); any
  other value (a string, an array, ...) becomes *** whole. An absent member is left absent. }
procedure MaskMember(pObj: TJSONObject; const pKey: string);
begin
  var Pair:= pObj.Get(pKey);
  if Pair = nil then Exit;
  if Pair.JsonValue is TJSONObject then
  begin
    var Inner:= TJSONObject(Pair.JsonValue);
    for var I:= 0 to Inner.Count - 1 do Inner.Pairs[I].JsonValue:= TJSONString.Create(MASK_TEXT);
  end
  else
    Pair.JsonValue:= TJSONString.Create(MASK_TEXT);
end;

{ The entry as printed text (Before / After / the paste hint): whatever sits under `env` and `headers` (an HTTP
  entry's Authorization lives there) reads *** -- they may be secrets, and this text is printed and logged by the
  installer. Object keys stay, so the change is still readable. }
function MaskedText(pNode: TJSONValue): string;
begin
  if pNode = nil then Exit(NONE_TEXT);
  if pNode is not TJSONObject then Exit(MASK_TEXT);
  var Copy:= TJSONObject(pNode.Clone);
  try
    for var Key in SECRET_KEYS do MaskMember(Copy, Key);
    Result:= Copy.ToJSON;
  finally
    Copy.Free;
  end;
end;

{ Sets pObj.pKey to pValue in place (the member keeps its position) or appends it; pObj owns pValue after. }
procedure SetMember(pObj: TJSONObject; const pKey: string; pValue: TJSONValue);
begin
  var Pair:= pObj.Get(pKey);
  if Pair <> nil then Pair.JsonValue:= pValue else pObj.AddPair(pKey, pValue);
end;

{ The text with // and /* */ comments and trailing commas removed, outside strings: if THAT parses, the file is
  JSON-with-comments, which a rewrite would silently strip -- refused with the paste hint instead. }
function StripLenient(const pText: string): string;
var
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create(pText.Length);
  try
    var I:= 1;
    var N:= pText.Length;
    var InStr:= False;
    while I <= N do
    begin
      var C:= pText[I];
      if InStr then
      begin
        SB.Append(C);
        if (C = '\') and (I < N) then
        begin
          Inc(I);
          SB.Append(pText[I]);
        end
        else if C = '"' then InStr:= False;
        Inc(I);
        Continue;
      end;
      if C = '"' then InStr:= True;
      if (C = '/') and (I < N) and (pText[I + 1] = '/') then
      begin
        while (I <= N) and (pText[I] <> #10) and (pText[I] <> #13) do Inc(I);
        Continue;
      end;
      if (C = '/') and (I < N) and (pText[I + 1] = '*') then
      begin
        var Close:= Pos('*/', pText, I + 2);
        I:= if Close = 0 then N + 1 else Close + 2;
        SB.Append(' ');
        Continue;
      end;
      if C = ',' then
      begin
        { a comma whose next significant character closes the container is a trailing comma }
        var J:= I + 1;
        while (J <= N) and CharInSet(pText[J], [' ', #9, #10, #13]) do Inc(J);
        if (J <= N) and CharInSet(pText[J], ['}', ']']) then
        begin
          Inc(I);
          Continue;
        end;
      end;
      SB.Append(C);
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function ParsesLeniently(const pText: string): Boolean;
begin
  var V:= TJSONObject.ParseJSONValue(StripLenient(pText), False, False);
  Result:= V <> nil;
  V.Free;
end;

{ The file's last-write time as raw FILETIME ticks; 0 when it cannot be read. }
function FileStamp(const pPath: string): Int64;
var
  Data: TWin32FileAttributeData;
begin
  if not GetFileAttributesEx(PChar(pPath), GetFileExInfoStandard, @Data) then Exit(0);
  Result:= Int64(Data.ftLastWriteTime.dwHighDateTime) shl FILETIME_HIGH_SHIFT or Data.ftLastWriteTime.dwLowDateTime;
end;

function DecodeText(const pBytes: TBytes): string;
begin
  var Skip:= 0;
  if (Length(pBytes) >= UTF8_BOM_LEN) and (pBytes[0] = BOM_BYTE_1) and (pBytes[1] = BOM_BYTE_2)
    and (pBytes[2] = BOM_BYTE_3) then Skip:= UTF8_BOM_LEN;
  Result:= TEncoding.UTF8.GetString(pBytes, Skip, Length(pBytes) - Skip);
end;

function SameBytes(const pA, pB: TBytes): Boolean;
begin
  Result:= (Length(pA) = Length(pB)) and ((Length(pA) = 0) or CompareMem(@pA[0], @pB[0], Length(pA)));
end;

{ Reads the config. Missing -> an empty object (Exists False); empty or whitespace (BOM tolerated) -> an empty object. Anything that is not
  one JSON object is refused before a byte is written. The caller owns Result.Root. }
function ReadConfig(const pPath, pByHand: string): TConfigFile;
begin
  Result.Exists:= TFile.Exists(pPath);
  Result.NewLine:= CRLF;
  Result.Stamp:= 0;
  Result.Bytes:= nil;
  if not Result.Exists then
  begin
    Result.Root:= TJSONObject.Create;
    Exit;
  end;
  Result.Stamp:= FileStamp(pPath);
  Result.Bytes:= TFile.ReadAllBytes(pPath);
  var Text:= DecodeText(Result.Bytes);
  if Text.Contains(LF) and not Text.Contains(CRLF) then Result.NewLine:= LF;
  if Text.Trim = '' then
  begin
    Result.Root:= TJSONObject.Create;
    Exit;
  end;
  var Parsed: TJSONValue:= nil;
  try
    Parsed:= TJSONObject.ParseJSONValue(Text, False, True);
  except
    on E: Exception do
    begin
      if ParsesLeniently(Text) then
        Stop(EXIT_REFUSED, 'refusing ' + pPath + ' -- it holds comments or trailing commas, and rewriting it would '
          + 'silently drop them. Nothing was written. ' + pByHand);
      Stop(EXIT_REFUSED, 'refusing ' + pPath + ' -- it is not valid JSON, so nothing was written: ' + E.Message);
    end;
  end;
  if Parsed is not TJSONObject then
  begin
    Parsed.Free;
    Stop(EXIT_REFUSED, 'refusing ' + pPath + ' -- its top level is not a JSON object, so nothing was written');
  end;
  Result.Root:= TJSONObject(Parsed);
end;

{ args compared element by element as text, ordinal; absent = no args, a lone non-array value = one arg. }
function SameArgs(pHave: TJSONValue; pArgs: TJSONArray): Boolean;
begin
  if pHave = nil then Exit(pArgs.Count = 0);
  if pHave is not TJSONArray then Exit((pArgs.Count = 1) and (pHave.Value = pArgs.Items[0].Value));
  var HaveArr:= TJSONArray(pHave);
  Result:= HaveArr.Count = pArgs.Count;
  for var I:= 0 to HaveArr.Count - 1 do
    if Result and (HaveArr.Items[I].Value <> pArgs.Items[I].Value) then Result:= False;
end;

{ The part of an entry that decides "same server": type (absent = stdio), command (case-insensitive), args (exact). }
function SameEntry(pNode: TJSONValue; const pEngine: string; pArgs: TJSONArray): Boolean;
begin
  if pNode is not TJSONObject then Exit(False);
  var Obj:= TJSONObject(pNode);
  var TypeV:= Obj.GetValue('type');
  var Cmd:= Obj.GetValue('command');
  Result:= ((TypeV = nil) or (TypeV.Value = 'stdio')) and (Cmd <> nil) and SameText(Cmd.Value, pEngine)
    and SameArgs(Obj.GetValue('args'), pArgs);
end;

function CommandOf(pNode: TJSONValue): string;
begin
  Result:= '';
  if pNode is not TJSONObject then Exit;
  var Cmd:= TJSONObject(pNode).GetValue('command');
  if Cmd is TJSONString then Result:= Cmd.Value;
end;

function BackupPath(const pPath: string): string;
begin
  Result:= pPath + '.bak-' + FormatDateTime(STAMP_FORMAT, Now);
  if TFile.Exists(Result) then Result:= pPath + '.bak-' + FormatDateTime(STAMP_MS_FORMAT, Now);
end;

function DefaultPath(const pRequest: TMcpConfigRequest): string;
begin
  if pRequest.Client = mcClaudeCode then
  begin
    var Dir:= GetEnvironmentVariable(CLAUDE_DIR_ENV);
    if Dir = '' then Dir:= if pRequest.HomeDir <> '' then pRequest.HomeDir else GetEnvironmentVariable('USERPROFILE');
    Result:= TPath.Combine(Dir, CLAUDE_FILE);
  end
  else if pRequest.Client = mcCursor then
  begin
    var Dir:= if pRequest.HomeDir <> '' then pRequest.HomeDir else GetEnvironmentVariable('USERPROFILE');
    Result:= TPath.Combine(TPath.Combine(Dir, CURSOR_DIR), CURSOR_FILE);
  end
  else
  begin
    var Dir:= if pRequest.AppDataDir <> '' then pRequest.AppDataDir else GetEnvironmentVariable('APPDATA');
    Result:= TPath.Combine(TPath.Combine(Dir, VSCODE_USER_DIR), VSCODE_FILE);
  end;
end;

{ Claude Code's file sits in the HOME folder, which always exists, so the folder proves nothing: it counts as
  installed only when the file exists, CLAUDE_CONFIG_DIR names an existing folder, or <home>\.claude exists.
  The script's `claude`-on-PATH probe is dropped with the CLI mode (owner decision 4). }
function ClientInstalled(const pRequest: TMcpConfigRequest; const pPath: string; out pWhy: string): Boolean;
begin
  if pRequest.Client = mcClaudeCode then
  begin
    var Home:= if pRequest.HomeDir <> '' then pRequest.HomeDir else GetEnvironmentVariable('USERPROFILE');
    var Dot:= TPath.Combine(Home, CLAUDE_DIR);
    var EnvDir:= GetEnvironmentVariable(CLAUDE_DIR_ENV);
    Result:= TFile.Exists(pPath) or ((EnvDir <> '') and TDirectory.Exists(EnvDir)) or TDirectory.Exists(Dot);
    pWhy:= 'no ' + Dot + ' folder, no ' + CLAUDE_DIR_ENV + ' and no ' + pPath;
  end
  else
  begin
    // VS Code and Cursor: the client's folder (or the file) must exist
    var Dir:= ExtractFileDir(pPath);
    Result:= TDirectory.Exists(Dir) or TFile.Exists(pPath);
    pWhy:= Dir + ' not found';
  end;
end;

{ Writes pText beside pPath and moves it into place, after re-checking the file is still what was read. }
procedure WriteConfig(const pPath, pText: string; const pCfg: TConfigFile; var pResult: TMcpConfigResult);
begin
  var Backup:= '';
  if pCfg.Exists then
  begin
    if not TFile.Exists(pPath) then Stop(EXIT_REFUSED, pPath + ' was deleted while this ran -- nothing was written; run again');
    if (FileStamp(pPath) <> pCfg.Stamp) or not SameBytes(TFile.ReadAllBytes(pPath), pCfg.Bytes) then
      Stop(EXIT_REFUSED, pPath + ' changed while this ran (a running client rewrote it?) -- nothing was written; run again');
    Backup:= BackupPath(pPath);
    TFile.Copy(pPath, Backup, False);
    pResult.Backup:= Backup;  { it exists from here on, whatever happens next }
  end
  else
    ForceDirectories(ExtractFileDir(pPath));
  var Tmp:= pPath + '.tmp-' + IntToStr(GetCurrentProcessId);
  try
    TFile.WriteAllBytes(Tmp, TEncoding.UTF8.GetBytes(pText));
  except
    on E: Exception do
    begin
      { never leave a partial temp file behind; Tmp is ours (pid-named), so no stat gate -- a missing file just fails }
      System.SysUtils.DeleteFile(Tmp);
      raise;
    end;
  end;
  { a file that did not exist when read must still not exist now -- a client may have created it meanwhile,
    and the move would overwrite what it wrote }
  if not pCfg.Exists and TFile.Exists(pPath) then
  begin
    TFile.Delete(Tmp);
    Stop(EXIT_REFUSED, pPath + ' appeared while this ran (a client created it?) -- nothing was written; run again');
  end;
  if not MoveFileEx(PChar(Tmp), PChar(pPath), MOVEFILE_REPLACE_EXISTING) then
  begin
    var Why:= SysErrorMessage(GetLastError);
    TFile.Delete(Tmp);
    Stop(EXIT_REFUSED, 'cannot replace ' + pPath + ': ' + Why + ' -- the file is unchanged'
      + (if Backup <> '' then ' (a copy is at ' + Backup + ')' else ''));
  end;
end;

{ The text the file is rewritten with: Format(2) plus a newline, every line ending in the file's own style. }
function ConfigText(pRoot: TJSONObject; const pNewLine: string): string;
begin
  Result:= (pRoot.Format(JSON_INDENT) + LF).Replace(CRLF, LF);
  if pNewLine = CRLF then Result:= Result.Replace(LF, CRLF);
end;

procedure ApplyCore(const pRequest: TMcpConfigRequest; var pResult: TMcpConfigResult);
begin
  var Client:= pRequest.Client;
  var Container:= CONTAINER_NAMES[Client];
  var Name:= pRequest.Name;
  if not ValidName(Name) then Stop(EXIT_SETUP, 'name ''' + Name + ''' must be letters, digits, ''_'', ''.'' or ''-''');
  var Engine:= ExpandFileName(if pRequest.Engine <> '' then pRequest.Engine else ParamStr(0));
  var DbPath:= '';
  if not pRequest.Remove then
  begin
    if not TFile.Exists(Engine) then Stop(EXIT_SETUP, 'engine ' + Engine + ' does not exist, so the entry would never start');
    if pRequest.DbPath <> '' then
    begin
      DbPath:= ExpandFileName(pRequest.DbPath);
      if not TFile.Exists(DbPath) then
        Stop(EXIT_SETUP, '--db ' + pRequest.DbPath + ' does not exist (' + DbPath
          + ') -- serve refuses a missing index, so the entry would never start');
    end;
  end;

  var Path:= if pRequest.ConfigPath <> '' then ExpandFileName(pRequest.ConfigPath) else DefaultPath(pRequest);
  pResult.Path:= Path;
  if pRequest.ConfigPath = '' then
  begin
    var Why: string;
    if not ClientInstalled(pRequest, Path, Why) then
    begin
      if pRequest.AllMode then
      begin
        pResult.Action:= 'skipped';
        Exit;
      end;
      Stop(EXIT_SETUP, pResult.Target + ' -- ' + Why + '; is the client installed? (pass --config-path to name the file)');
    end;
  end;

  var Want: TJSONObject:= nil;
  if not pRequest.Remove then Want:= BuildEntry(Client, Engine, DbPath);
  var Cfg: TConfigFile;
  Cfg.Root:= nil;
  try
    var ByHand: string;
    if pRequest.Remove then
      ByHand:= 'Delete the "' + Name + '" entry under "' + Container + '" by hand instead.'
    else
      ByHand:= 'Add this entry by hand instead:' + sLineBreak + '  "' + Container + '": { "' + Name + '": '
        + McpEntryText(Client, Engine, DbPath) + ' }';
    Cfg:= ReadConfig(Path, ByHand);
    var BoxV:= Cfg.Root.GetValue(Container);
    if (BoxV <> nil) and (BoxV is not TJSONObject) then
      Stop(EXIT_REFUSED, 'refusing ' + Path + ' -- "' + Container + '" is not a JSON object, so nothing was written');
    var Box:= TJSONObject(BoxV);
    var Have: TJSONValue:= nil;
    if Box <> nil then Have:= Box.GetValue(Name);

    { an entry by this name that runs something else is NOT ours -- never update or remove it, and never print its
      body: a foreign entry may carry a token anywhere (url, headers, ...), so only the command it runs is named }
    if Have <> nil then
    begin
      var HaveCmd:= CommandOf(Have);
      var Ours:= (HaveCmd <> '') and (SameText(ExtractFileName(HaveCmd), ENGINE_EXE) or SameText(HaveCmd, Engine));
      if not Ours then
      begin
        pResult.Before:= NOT_OURS_TEXT;
        Stop(EXIT_REFUSED, 'refusing ' + Path + ' -- the entry "' + Name + '" runs ''' + HaveCmd
          + ''', not drag-lint.exe, so it is not this verb''s to ' + (if pRequest.Remove then 'remove' else 'update')
          + '. Nothing was written. Pass --name for a different entry, or edit it by hand.');
      end;
    end;
    pResult.Before:= MaskedText(Have);

    var Verb: string;
    if pRequest.Remove then
    begin
      Verb:= if Have = nil then 'absent' else 'removed';
    end
    else if Have = nil then
      Verb:= 'added'
    else if SameEntry(Have, Engine, Want.GetValue('args') as TJSONArray) then
      Verb:= 'unchanged'
    else
      Verb:= 'updated';

    var Prefix:= if pRequest.DryRun then 'would-' else '';
    if (Verb = 'unchanged') or (Verb = 'absent') then
    begin
      pResult.After:= if Verb = 'absent' then NONE_TEXT else pResult.Before;
      pResult.Action:= Prefix + Verb;
      Exit;
    end;

    { the new entry: an update keeps keys the user added to OUR entry (env, ...) }
    if Verb = 'removed' then
    begin
      Box.RemovePair(Name).Free;
      pResult.After:= NONE_TEXT;
    end
    else
    begin
      if Box = nil then
      begin
        Box:= TJSONObject.Create;
        Cfg.Root.AddPair(Container, Box);
      end;
      var NewNode: TJSONObject;
      if (Verb = 'updated') and (Have is TJSONObject) then
      begin
        NewNode:= TJSONObject(Have.Clone);
        for var Key in SERVER_KEYS do SetMember(NewNode, Key, TJSONValue(Want.GetValue(Key).Clone));
      end
      else
      begin
        NewNode:= Want;
        Want:= nil;
      end;
      pResult.After:= MaskedText(NewNode);
      SetMember(Box, Name, NewNode);
    end;

    var Text:= ConfigText(Cfg.Root, Cfg.NewLine);
    pResult.Action:= Prefix + Verb;
    if pRequest.DryRun then Exit;
    WriteConfig(Path, Text, Cfg, pResult);
  finally
    Want.Free;
    Cfg.Root.Free;
  end;
end;

function ApplyMcpConfig(const pRequest: TMcpConfigRequest): TMcpConfigResult;
begin
  Result:= Default(TMcpConfigResult);
  Result.Target:= TARGET_NAMES[pRequest.Client];
  Result.Before:= NONE_TEXT;
  Result.After:= NONE_TEXT;
  try
    ApplyCore(pRequest, Result);
  except
    on E: EMcpConfigStop do
    begin
      Result.Action:= 'refused';
      Result.Error:= E.Message;
      Result.ExitCode:= E.Code;
    end;
    on E: Exception do
    begin
      Result.Action:= 'refused';
      Result.Error:= E.Message;
      Result.ExitCode:= EXIT_REFUSED;
    end;
  end;
end;

procedure WriteUsage;
begin
  Writeln(ErrOutput, 'usage:');
  Writeln(ErrOutput, '  drag-lint mcp-config (--claude-code | --vscode | --cursor | --all) [--remove] [--dry-run] [--name <n>] '
    + '[--db <index>] [--engine <exe>] [--config-path <file>] [--json] [--home-dir <dir>] [--appdata-dir <dir>]');
end;

function UsageError(const pWhy: string): Integer;
begin
  Writeln(ErrOutput, 'drag-lint mcp-config: ' + pWhy);
  WriteUsage;
  Result:= EXIT_SETUP;
end;

function ResultJson(const pResult: TMcpConfigResult): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('Target', pResult.Target);
  Result.AddPair('Path', pResult.Path);
  Result.AddPair('Action', pResult.Action);
  Result.AddPair('Backup', pResult.Backup);
  Result.AddPair('Before', pResult.Before);
  Result.AddPair('After', pResult.After);
  Result.AddPair('Error', pResult.Error);
  Result.AddPair('ExitCode', TJSONNumber.Create(pResult.ExitCode));
end;

procedure WriteResultText(const pResult: TMcpConfigResult);
begin
  Writeln('Target: ' + pResult.Target);
  Writeln('Path  : ' + pResult.Path);
  Writeln('Action: ' + pResult.Action);
  Writeln('Backup: ' + (if pResult.Backup = '' then NONE_TEXT else pResult.Backup));
  Writeln('Before: ' + pResult.Before);
  Writeln('After : ' + pResult.After);
end;

{ The flag that spells pFlag; False when none does. }
function FindFlag(const pFlag: string; out pWhich: TMcpConfigFlag): Boolean;
begin
  Result:= False;
  pWhich:= Low(TMcpConfigFlag);
  for var F:= Low(TMcpConfigFlag) to High(TMcpConfigFlag) do
    if not Result and (pFlag = MCP_CONFIG_FLAG_NAMES[F]) then
    begin
      Result:= True;
      pWhich:= F;
    end;
end;

{ How many clients the command line named. }
function ClientCount(pClients: TMcpClients): Integer;
begin
  Result:= 0;
  for var C in pClients do Inc(Result);
end;

{ Reads ParamStr(2..) into pReq and the target set. Returns '' when the command line is usable, else the usage
  error to print. }
function ParseFlags(var pReq: TMcpConfigRequest; out pClients: TMcpClients; out pJson: Boolean): string;
begin
  Result:= '';
  pClients:= [];
  pJson:= False;
  var I:= FIRST_FLAG_PARAM;
  while (Result = '') and (I <= ParamCount) do
  begin
    var Flag:= ParamStr(I);
    var Which: TMcpConfigFlag;
    var Value:= '';
    if not FindFlag(Flag, Which) then Result:= 'unknown flag: ' + Flag
    else if Which in VALUE_FLAGS then
    begin
      if I = ParamCount then Result:= Flag + ' needs a value'
      else
      begin
        Inc(I);
        Value:= ParamStr(I);
      end;
    end;
    if Result <> '' then Break;
    case Which of
      mfClaudeCode: Include(pClients, mcClaudeCode);
      mfVSCode    : Include(pClients, mcVSCode);
      mfCursor    : Include(pClients, mcCursor);
      mfAll       :
        begin
          pClients:= [mcClaudeCode, mcVSCode, mcCursor];
          pReq.AllMode:= True;
        end;
      mfRemove    : pReq.Remove:= True;
      mfDryRun    : pReq.DryRun:= True;
      mfName      : pReq.Name:= Value;
      mfDb        : pReq.DbPath:= Value;
      mfEngine    : pReq.Engine:= Value;
      mfConfigPath: pReq.ConfigPath:= Value;
      mfJson      : pJson:= True;
      mfHomeDir   : pReq.HomeDir:= Value;
      mfAppDataDir: pReq.AppDataDir:= Value;
    end;
    Inc(I);
  end;
  if Result <> '' then Exit;
  if pClients = [] then Result:= 'name a target: --claude-code, --vscode, --cursor or --all'
  else if (pReq.ConfigPath <> '') and (ClientCount(pClients) <> 1) then
    Result:= '--config-path names ONE file, so pass exactly one of --claude-code / --vscode / --cursor with it'
  else if not ValidName(pReq.Name) then
    Result:= '--name ''' + pReq.Name + ''' must be letters, digits, ''_'', ''.'' or ''-''';
end;

function RunMcpConfigVerbFromCommandLine: Integer;
begin
  var Req:= Default(TMcpConfigRequest);
  Req.Name:= DEFAULT_NAME;
  var Clients: TMcpClients;
  var Json: Boolean;
  var Why:= ParseFlags(Req, Clients, Json);
  if Why <> '' then Exit(UsageError(Why));

  Result:= EXIT_OK;
  var Arr:= TJSONArray.Create;
  try
    for var Client in Clients do
    begin
      Req.Client:= Client;
      var Res:= ApplyMcpConfig(Req);
      if Res.ExitCode > Result then Result:= Res.ExitCode;
      if Res.Error <> '' then Writeln(ErrOutput, 'drag-lint mcp-config: ' + Res.Error);
      if Json then Arr.AddElement(ResultJson(Res)) else WriteResultText(Res);
    end;
    if Json then Writeln(Arr.Format(JSON_INDENT));
  finally
    Arr.Free;
  end;
end;

{ ---- init: register + index + find the index + wire the clients, from existing verbs ---- }

const
  INIT_STEP_COUNT   = 4;
  STEP_REGISTER     = 1;
  STEP_INDEX        = 2;
  STEP_RESOLVE      = 3;
  STEP_WIRE         = 4;
  INIT_TIMEOUT_MS   = 3_600_000;  // 1 h: a first full index of a large project
  INIT_FIRST_FLAG   = 2;        // ParamStr(1) is `init`
  SQLITE_EXT        = '.sqlite';

type
  TInitRequest = record
    Project  : string;
    DryRun   : Boolean;
    HomeDir  : string;
    AppDataDir: string;
  end;

procedure InitUsage(const pWhy: string);
begin
  Writeln(ErrOutput, 'drag-lint init: ' + pWhy);
  Writeln(ErrOutput, 'usage:');
  Writeln(ErrOutput, '  drag-lint init --project <file.dproj> [--dry-run] [--home-dir <dir>] [--appdata-dir <dir>]');
end;

{ '' when the command line is usable, else the reason. }
function ParseInitFlags(var pReq: TInitRequest): string;
begin
  Result:= '';
  var I:= INIT_FIRST_FLAG;
  while (Result = '') and (I <= ParamCount) do
  begin
    var Flag:= ParamStr(I);
    if Flag = '--dry-run' then pReq.DryRun:= True
    else if (Flag = '--project') or (Flag = '--home-dir') or (Flag = '--appdata-dir') then
    begin
      if I = ParamCount then Result:= Flag + ' needs a value'
      else
      begin
        Inc(I);
        if Flag = '--project' then pReq.Project:= ParamStr(I)
        else if Flag = '--home-dir' then pReq.HomeDir:= ParamStr(I)
        else pReq.AppDataDir:= ParamStr(I);
      end;
    end
    else Result:= 'unknown flag: ' + Flag;
    Inc(I);
  end;
  if (Result = '') and (pReq.Project = '') then Result:= 'name the project: --project <file.dproj>';
  if (Result = '') and not TFile.Exists(pReq.Project) then Result:= 'project file not found: ' + pReq.Project;
end;

{ The last stdout line that names a .sqlite file ('' when none). }
function IndexPathFrom(const pStdOut: string): string;
begin
  Result:= '';
  for var Line in pStdOut.Split([#13, #10], TStringSplitOptions.ExcludeEmpty) do
    if SameText(ExtractFileExt(Trim(Line)), SQLITE_EXT) then Result:= Trim(Line);
end;

function EngineCommand(const pArgs: string): string;
begin
  Result:= QuoteArg(ParamStr(0)) + ' ' + pArgs;
end;

{ Runs one step, echoes its output under a heading; returns its exit code (-1 when it could not start). }
function RunStep(pNo: Integer; const pTitle, pArgs: string; out pStdOut: string): Integer;
begin
  Writeln(Format('step %d/%d: %s', [pNo, INIT_STEP_COUNT, pTitle]));
  Writeln('  ' + EngineCommand(pArgs));
  var Res: TProcessResult;
  pStdOut:= '';
  if not RunCapture(EngineCommand(pArgs), '', INIT_TIMEOUT_MS, Res) then
  begin
    Writeln(ErrOutput, 'drag-lint init: could not start ' + ParamStr(0));
    Exit(-1);
  end;
  pStdOut:= Res.StdOut;
  if Res.StdOut <> '' then Write(Res.StdOut);
  if Res.StdErr <> '' then Write(ErrOutput, Res.StdErr);
  Result:= if Res.TimedOut then -1 else Res.ExitCode;
end;

function RunInitVerbFromCommandLine: Integer;
begin
  var Req:= Default(TInitRequest);
  var Why:= ParseInitFlags(Req);
  if Why <> '' then
  begin
    InitUsage(Why);
    Exit(EXIT_SETUP);
  end;

  var Proj:= QuoteArg(ExpandFileName(Req.Project));
  var Homes:= '';
  if Req.HomeDir <> '' then Homes:= Homes + ' --home-dir ' + QuoteArg(Req.HomeDir);
  if Req.AppDataDir <> '' then Homes:= Homes + ' --appdata-dir ' + QuoteArg(Req.AppDataDir);
  var RegArgs:= 'register-project ' + Proj + ' --apply';
  var IdxArgs:= 'index --project ' + Proj;
  var ResArgs:= 'resolve-dbs --project ' + Proj;

  if Req.DryRun then
  begin
    Writeln('init (dry run) -- nothing is run and nothing is written; the four steps would be:');
    Writeln(Format('  1/%d  %s   (adds the project''s section to the manifest; no-op when already registered)', [INIT_STEP_COUNT, EngineCommand(RegArgs)]));
    Writeln(Format('  2/%d  %s', [INIT_STEP_COUNT, EngineCommand(IdxArgs)]));
    Writeln(Format('  3/%d  %s   (finds the index step 4 serves)', [INIT_STEP_COUNT, EngineCommand(ResArgs)]));
    Writeln(Format('  4/%d  %s', [INIT_STEP_COUNT, EngineCommand('mcp-config --all --db <index from step 3>' + Homes)]));
    Exit(EXIT_OK);
  end;

  var Out1: string;
  Result:= RunStep(STEP_REGISTER, 'register the project in the manifest', RegArgs, Out1);
  if Result = EXIT_OK then Result:= RunStep(STEP_INDEX, 'index the project', IdxArgs, Out1);
  if Result = EXIT_OK then Result:= RunStep(STEP_RESOLVE, 'find the project''s index', ResArgs, Out1);
  if Result = EXIT_OK then
  begin
    var Db:= IndexPathFrom(Out1);
    if Db = '' then
    begin
      Writeln(ErrOutput, 'drag-lint init: resolve-dbs named no .sqlite index for ' + Req.Project);
      Exit(EXIT_REFUSED);
    end;
    Result:= RunStep(STEP_WIRE, 'wire Claude Code, VS Code and Cursor', 'mcp-config --all --db ' + QuoteArg(Db) + Homes, Out1);
  end;
  if Result < 0 then Result:= EXIT_REFUSED;  // a step that could not start or timed out
end;

end.