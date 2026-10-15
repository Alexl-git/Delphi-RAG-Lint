unit DRagLint.Core.ProtocolReg;

/// <summary>`drag-lint protocol register|unregister|status` -- the per-user draglint:// URL protocol
/// registration that makes a click-to-source link open drag-lint-open.exe.</summary>
/// <remarks>
/// <para>A port of charts\src\Register-DragLintProtocol.ps1, which it replaces. The handler is now the
/// GUI-subsystem drag-lint-open.exe, registered IN PLACE (owner decision 2: no copy under LOCALAPPDATA);
/// a handler inside a *-wt\ worktree is refused without --force, as the script refused one.</para>
/// <para>HKCU only, never HKLM (owner D4): no elevation, and one `unregister` undoes it. The previous
/// registration is classified before anything is written; our own legacy PowerShell registration is
/// replaced silently (owner decision 10), a foreign one only with --force.</para>
/// <para>The test-root override: environment variable DRAGLINT_PROTOCOL_TEST_ROOT moves the whole key to
/// HKCU\&lt;that&gt;\Classes\draglint. It exists ONLY so tests\autotest\run_protocol_verb.ps1 can exercise
/// the writing paths without touching the developer's real registration, which is exactly what it would
/// otherwise rewrite on every battery run. While it is set the legacy copy
/// %LOCALAPPDATA%\drag-lint\Open-DragLintUri.ps1 is reported, never deleted -- the copy is not under the
/// test root, so deleting it would reach outside the sandbox.</para>
/// <para>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</para>
/// </remarks>

interface

type
  /// <summary>Who owns the current draglint:// registration.</summary>
  TProtocolClass = (pcNone, pcOurs, pcLegacyPowerShell, pcForeign);

  /// <summary>What HKCU\Software\Classes\draglint currently holds.</summary>
  TProtocolStatus = record
    /// <summary>shell\open\command\(default), raw (an REG_EXPAND_SZ is not expanded); '' when absent.</summary>
    Command: string;
    /// <summary>The classification of Command.</summary>
    Kind   : TProtocolClass;
    /// <summary>The first quoted token of Command (the first space-delimited one when it is not quoted); '' when none.</summary>
    Handler: string;
  end;

/// <summary>The registry root the verb reads and writes.</summary>
/// <returns>'Software\Classes\draglint' under HKCU, or '&lt;DRAGLINT_PROTOCOL_TEST_ROOT&gt;\Classes\draglint' when that
/// environment variable is set (tests only; it never changes what a user's command line does).</returns>
function ProtocolRegistryRoot: string;

/// <summary>Reads the current draglint:// registration.</summary>
/// <returns>Kind pcNone when the key or its command is absent; pcOurs when the handler file name is
/// drag-lint-open.exe; pcLegacyPowerShell when the command names Open-DragLintUri.ps1; else pcForeign -- including
/// a command value that is not a string (Command is then '(a non-string value)').</returns>
/// <remarks>Read-only; never raises on a missing key or a non-string value. Both name matches are case-insensitive.</remarks>
function ReadProtocolStatus: TProtocolStatus;

/// <summary>Registers pHandler as the draglint:// handler for the current user.</summary>
/// <param name="pHandler">Full path of drag-lint-open.exe. Must exist.</param>
/// <param name="pForce">Accept a path containing '-wt\' and replace a pcForeign registration.</param>
/// <param name="pDryRun">Report what would be written and write nothing.</param>
/// <param name="pReport">The lines the verb prints.</param>
/// <returns>0 written (or would be); 1 refused (foreign without pForce, worktree without pForce); 2 handler missing,
/// or DRAGLINT_PROTOCOL_TEST_ROOT resolving to or under the real Software\Classes.</returns>
/// <remarks>HKCU only, never HKLM (owner D4). Writes (default)=URL:drag-lint protocol, an empty REG_SZ
/// "URL Protocol" and shell\open\command\(default)="&lt;handler&gt;" "%1" (REG_SZ). Replacing a
/// pcLegacyPowerShell registration also deletes the copy %LOCALAPPDATA%\drag-lint\Open-DragLintUri.ps1 that
/// Register-DragLintProtocol.ps1 installed -- except under DRAGLINT_PROTOCOL_TEST_ROOT, where it is reported as
/// left in place. A legacy copy that cannot be deleted (locked, read-only) is reported, not raised: the key is
/// already written and the exit stays 0.</remarks>
function RegisterProtocol(const pHandler: string; pForce, pDryRun: Boolean; out pReport: string): Integer;

/// <summary>Removes the draglint:// registration when it is ours or the legacy PowerShell one.</summary>
/// <param name="pForce">Also remove a pcForeign registration.</param>
/// <param name="pDryRun">Report what would be removed and remove nothing.</param>
/// <param name="pReport">The lines the verb prints.</param>
/// <returns>0 removed, absent, kept (a key with no shell\open\command, without pForce), or would be removed;
/// 1 refused (pcForeign without pForce); 2 for an unsafe DRAGLINT_PROTOCOL_TEST_ROOT.</returns>
/// <remarks>The key is deleted recursively. A key that exists but names no command may be another program's and is
/// kept ('nothing to remove') unless pForce. A legacy registration's copy is deleted with it, under the same
/// test-root exception as RegisterProtocol.</remarks>
function UnregisterProtocol(pForce, pDryRun: Boolean; out pReport: string): Integer;

/// <summary>Entry point of `drag-lint protocol`: parses ParamStr(2..) itself (register|unregister|status and flags).</summary>
/// <returns>The verb's exit code; 2 with usage on stderr for no sub-verb, an unknown sub-verb or an unknown flag.</returns>
/// <remarks>Also 2, before anything is opened, when DRAGLINT_PROTOCOL_TEST_ROOT -- normalised as TRegistry reads it:
/// surrounding blanks and backslashes stripped -- is Software, Software\Classes or lies under Software\Classes: the
/// override must never resolve to the tree it exists to protect. A value that is set but blank after that normalisation is refused too, never read as unset. A trailing --handler with no value is a usage
/// error ('--handler needs a value').</remarks>
function RunProtocolVerbFromCommandLine: Integer;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Win.Registry;

type
  { The verb's flags. tests\autotest\run_docs_sync_guard.ps1 reads PROTOCOL_FLAG_NAMES as the set this
    verb accepts (ParseArgs returns before its own chain for `protocol`), so keep the table and the parser one. }
  TProtocolFlag = (pfHandler, pfDryRun, pfForce, pfJson);

const
  PROTOCOL_FLAG_NAMES: array[TProtocolFlag] of string = ('--handler', '--dry-run', '--force', '--json');
  REAL_ROOT        = 'Software\Classes\draglint';
  TEST_ROOT_ENV    = 'DRAGLINT_PROTOCOL_TEST_ROOT';
  COMMAND_SUBKEY   = '\shell\open\command';
  HANDLER_EXE      = 'drag-lint-open.exe';
  LEGACY_SCRIPT    = 'Open-DragLintUri.ps1';
  ROOT_DEFAULT     = 'URL:drag-lint protocol';
  URL_PROTOCOL     = 'URL Protocol';
  WORKTREE_MARK    = '-wt\';
  CLASS_NAMES: array[TProtocolClass] of string = ('none', 'ours', 'legacy-powershell', 'foreign');

  EXIT_OK      = 0;
  EXIT_REFUSED = 1;
  EXIT_SETUP   = 2;

  NON_STRING_COMMAND = '(a non-string value)';
  TEST_ROOT_REFUSAL  = TEST_ROOT_ENV + ' resolves to or under the real HKCU\Software\Classes; refusing';
  FIRST_FLAG_PARAM = 3;  // ParamStr(1) is `protocol`, ParamStr(2) the sub-verb

{ Normalised the way TRegistry reads a path: surrounding blanks and backslashes stripped (a leading '\' is
  absolute to TRegistry, so '\Software' would otherwise be the real Software) and doubled backslashes folded. }
function TestRoot: string;
begin
  Result:= GetEnvironmentVariable(TEST_ROOT_ENV).Trim;
  while Result.Contains('\\') do Result:= Result.Replace('\\', '\');
  Result:= Result.Trim(['\']).Trim;
end;

{ True when DRAGLINT_PROTOCOL_TEST_ROOT is set but blank after normalisation, or the key it yields is the real one or lies under the real
  Software\Classes -- the override exists to keep tests OFF that tree, so such a value is refused outright. }
function UnsafeTestRoot: Boolean;
begin
  var Root:= TestRoot.ToLower;
  if Root = '' then Exit(GetEnvironmentVariable(TEST_ROOT_ENV) <> '');
  Result:= (Root = 'software') or (Root = 'software\classes') or Root.StartsWith('software\classes\');
end;

function ProtocolRegistryRoot: string;
begin
  var Root:= TestRoot;
  Result:= if Root = '' then REAL_ROOT else Root + '\Classes\draglint';
end;

function LegacyCopyPath: string;
begin
  Result:= TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'drag-lint'), LEGACY_SCRIPT);
end;

function FirstToken(const pCommand: string): string;
begin
  var S:= pCommand.Trim;
  if S = '' then Exit('');
  if S.StartsWith('"') then
  begin
    var Close:= S.IndexOf('"', 1);
    Result:= if Close < 0 then S.Substring(1) else S.Substring(1, Close - 1);
  end
  else
  begin
    var Space:= S.IndexOf(' ');
    Result:= if Space < 0 then S else S.Substring(0, Space);
  end;
end;

function Classify(const pCommand: string): TProtocolClass;
begin
  if pCommand.Trim = '' then Exit(pcNone);
  if SameText(ExtractFileName(FirstToken(pCommand)), HANDLER_EXE) then Exit(pcOurs);
  if pCommand.ToLower.Contains(LEGACY_SCRIPT.ToLower) then Exit(pcLegacyPowerShell);
  Result:= pcForeign;
end;

function ReadProtocolStatus: TProtocolStatus;
begin
  Result.Command:= '';
  Result.Handler:= '';
  var NonString:= False;
  var Reg:= TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(ProtocolRegistryRoot + COMMAND_SUBKEY) and Reg.ValueExists('') then
    begin
      { A non-string command is nobody's we know: report it as foreign rather than let ReadString raise. }
      NonString:= not (Reg.GetDataType('') in [rdString, rdExpandString]);
      if not NonString then Result.Command:= Reg.ReadString('');
    end;
  finally
    Reg.Free;
  end;
  if NonString then
  begin
    Result.Command:= NON_STRING_COMMAND;
    Result.Kind:= pcForeign;
    Exit;
  end;
  Result.Kind:= Classify(Result.Command);
  if Result.Kind <> pcNone then Result.Handler:= FirstToken(Result.Command);
end;

function ShownCommand(const pCommand: string): string;
begin
  Result:= if pCommand = '' then '(none)' else pCommand;
end;

{ The legacy copy: deleted for real, reported under the test root, said nothing about when absent. }
procedure RemoveLegacyCopy(pDryRun: Boolean; var pReport: string);
begin
  var LegacyCopy:= LegacyCopyPath;
  if TestRoot <> '' then
  begin
    pReport:= pReport + '  legacy  : ' + LegacyCopy + ' left in place (' + TEST_ROOT_ENV + ' is set)' + sLineBreak;
    Exit;
  end;
  if not TFile.Exists(LegacyCopy) then Exit;
  if pDryRun then
    pReport:= pReport + 'would remove: ' + LegacyCopy + sLineBreak
  else
  begin
    try
      TFile.Delete(LegacyCopy);
      pReport:= pReport + '  removed : ' + LegacyCopy + sLineBreak;
    except
      on E: Exception do  { the key is already written: report, do not fail the verb over a locked copy }
        pReport:= pReport + 'could not remove legacy copy ' + LegacyCopy + ': ' + E.Message + sLineBreak;
    end;
  end;
end;

function RegisterProtocol(const pHandler: string; pForce, pDryRun: Boolean; out pReport: string): Integer;
begin
  pReport:= '';
  if UnsafeTestRoot then
  begin
    pReport:= TEST_ROOT_REFUSAL + sLineBreak;
    Exit(EXIT_SETUP);
  end;
  var Handler:= ExpandFileName(pHandler);
  if not TFile.Exists(Handler) then
  begin
    pReport:= 'handler not found: ' + Handler + sLineBreak;
    Exit(EXIT_SETUP);
  end;
  if Handler.ToLower.Contains(WORKTREE_MARK) and not pForce then
  begin
    pReport:= 'the handler ' + Handler + ' is inside a worktree (*-wt\) -- register from the main checkout, '
      + 'or pass --force to register this copy deliberately' + sLineBreak;
    Exit(EXIT_REFUSED);
  end;
  var Current:= ReadProtocolStatus;
  if (Current.Kind = pcForeign) and not pForce then
  begin
    pReport:= 'refusing: draglint:// is registered to ' + Current.Command + '; pass --force to replace it' + sLineBreak;
    Exit(EXIT_REFUSED);
  end;
  var Root:= ProtocolRegistryRoot;
  var Command:= '"' + Handler + '" "%1"';
  if not pDryRun then
  begin
    var Reg:= TRegistry.Create(KEY_ALL_ACCESS);
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if not Reg.OpenKey(Root, True) then raise ERegistryException.Create('cannot open HKCU\' + Root);
      Reg.WriteString('', ROOT_DEFAULT);
      Reg.WriteString(URL_PROTOCOL, '');
      Reg.CloseKey;
      if not Reg.OpenKey(Root + COMMAND_SUBKEY, True) then
        raise ERegistryException.Create('cannot open HKCU\' + Root + COMMAND_SUBKEY);
      Reg.WriteString('', Command);
    finally
      Reg.Free;
    end;
  end;
  pReport:= (if pDryRun then 'would register: HKCU\' else 'registered: HKCU\') + Root + sLineBreak
    + '  key     : HKCU\' + Root + COMMAND_SUBKEY + sLineBreak
    + '  handler : ' + Handler + sLineBreak
    + '  command : ' + Command + sLineBreak;
  if pDryRun then pReport:= pReport + '  current : ' + ShownCommand(Current.Command) + sLineBreak;
  pReport:= pReport + '  undo    : drag-lint protocol unregister' + sLineBreak;
  if Current.Kind = pcLegacyPowerShell then RemoveLegacyCopy(pDryRun, pReport);
  Result:= EXIT_OK;
end;

function UnregisterProtocol(pForce, pDryRun: Boolean; out pReport: string): Integer;
begin
  pReport:= '';
  if UnsafeTestRoot then
  begin
    pReport:= TEST_ROOT_REFUSAL + sLineBreak;
    Exit(EXIT_SETUP);
  end;
  var Root:= ProtocolRegistryRoot;
  var Current:= ReadProtocolStatus;
  var Reg:= TRegistry.Create(KEY_ALL_ACCESS);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if not Reg.KeyExists(Root) then
    begin
      pReport:= 'nothing to remove: HKCU\' + Root + sLineBreak;
      Exit(EXIT_OK);
    end;
    if (Current.Kind = pcForeign) and not pForce then
    begin
      pReport:= 'refusing: draglint:// is registered to ' + Current.Command + '; pass --force to remove it' + sLineBreak;
      Exit(EXIT_REFUSED);
    end;
    if (Current.Kind = pcNone) and not pForce then
    begin
      { The key exists but names no handler: it may be another program's half-written registration. }
      pReport:= 'nothing to remove: HKCU\' + Root + ' has no shell\open\command; key kept (pass --force to remove it)'
        + sLineBreak;
      Exit(EXIT_OK);
    end;
    if pDryRun then
      pReport:= 'would remove: HKCU\' + Root + sLineBreak
    else
    begin
      if not Reg.DeleteKey(Root) then raise ERegistryException.Create('cannot delete HKCU\' + Root);
      pReport:= 'unregistered: HKCU\' + Root + sLineBreak;
    end;
  finally
    Reg.Free;
  end;
  if Current.Kind = pcLegacyPowerShell then RemoveLegacyCopy(pDryRun, pReport);
  Result:= EXIT_OK;
end;

function StatusJson(const pStatus: TProtocolStatus): string;
begin
  var Obj:= TJSONObject.Create;
  try
    Obj.AddPair('schema', 'protocol/1');
    Obj.AddPair('registered', TJSONBool.Create(pStatus.Kind <> pcNone));
    Obj.AddPair('class', CLASS_NAMES[pStatus.Kind]);
    Obj.AddPair('command', pStatus.Command);
    Obj.AddPair('handler', pStatus.Handler);
    Result:= Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

procedure WriteUsage;
begin
  Writeln(ErrOutput, 'usage:');
  Writeln(ErrOutput, '  drag-lint protocol register [--handler <drag-lint-open.exe>] [--dry-run] [--force]');
  Writeln(ErrOutput, '  drag-lint protocol unregister [--dry-run] [--force]');
  Writeln(ErrOutput, '  drag-lint protocol status [--json]');
end;

function UsageError(const pWhy: string): Integer;
begin
  Writeln(ErrOutput, 'drag-lint protocol: ' + pWhy);
  WriteUsage;
  Result:= EXIT_SETUP;
end;

procedure Emit(pCode: Integer; const pReport: string);
begin
  if pCode = EXIT_OK then Write(pReport) else Write(ErrOutput, pReport);
end;

function RunProtocolVerbFromCommandLine: Integer;
begin
  if ParamCount < 2 then Exit(UsageError('no sub-verb'));
  var Verb:= ParamStr(2).ToLower;
  if (Verb <> 'register') and (Verb <> 'unregister') and (Verb <> 'status') then
    Exit(UsageError('unknown sub-verb "' + ParamStr(2) + '"'));
  if UnsafeTestRoot then Exit(UsageError(TEST_ROOT_REFUSAL));
  var Handler:= TPath.Combine(ExtractFileDir(ParamStr(0)), HANDLER_EXE);
  var Force:= False;
  var DryRun:= False;
  var Json:= False;
  var I:= FIRST_FLAG_PARAM;
  while I <= ParamCount do
  begin
    var Flag:= ParamStr(I);
    if (Flag = PROTOCOL_FLAG_NAMES[pfHandler]) and (Verb = 'register') then
    begin
      if I = ParamCount then Exit(UsageError(Flag + ' needs a value'));
      Inc(I);
      Handler:= ParamStr(I);
    end
    else if (Flag = PROTOCOL_FLAG_NAMES[pfForce]) and (Verb <> 'status') then Force:= True
    else if (Flag = PROTOCOL_FLAG_NAMES[pfDryRun]) and (Verb <> 'status') then DryRun:= True
    else if (Flag = PROTOCOL_FLAG_NAMES[pfJson]) and (Verb = 'status') then Json:= True
    else Exit(UsageError('unknown flag for ' + Verb + ': ' + Flag));
    Inc(I);
  end;
  var Report: string;
  if Verb = 'register' then
  begin
    Result:= RegisterProtocol(Handler, Force, DryRun, Report);
    Emit(Result, Report);
  end
  else if Verb = 'unregister' then
  begin
    Result:= UnregisterProtocol(Force, DryRun, Report);
    Emit(Result, Report);
  end
  else
  begin
    var Status:= ReadProtocolStatus;
    if Json then Writeln(StatusJson(Status))
    else
    begin
      Writeln('draglint://: ' + CLASS_NAMES[Status.Kind]);
      Writeln('  command : ' + ShownCommand(Status.Command));
    end;
    Result:= if Status.Kind = pcOurs then EXIT_OK else EXIT_REFUSED;
  end;
end;

end.
