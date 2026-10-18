unit DragLint.Open.Main;

/// <summary>The work of drag-lint-open.exe, the draglint:// protocol handler:
/// one URI in, the IDE pipe (or notepad) out, every step logged.</summary>
/// <remarks>
/// <para>A port of charts\src\Open-DragLintUri.ps1:95-182. The contract is in
/// the header of drag-lint-open.dpr; the guard is
/// tests\autotest\run_uri_handler.ps1.</para>
/// <para>Nothing here may show a dialog: the process is GUI-subsystem and runs
/// from a browser click, so every failure is a log line and an exit code.</para>
/// <para>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</para>
/// </remarks>

interface

/// <summary>The process arguments after the program name.</summary>
/// <returns>ParamStr(1)..ParamStr(ParamCount), in order; empty when there are none.</returns>
function CommandLineArgs: TArray<string>;

/// <summary>Handles one draglint:// click: validates the URI, sends the
/// file:line frame to the IDE plugin's pipe, or opens the file in notepad.</summary>
/// <param name="pArgs">The command-line arguments. Exactly one -- the URI -- is
/// accepted (ruling SEC-R2); any other count is logged as args: [..] [..] and
/// refused.</param>
/// <returns>0 sent to the IDE or opened in notepad (in what-if mode: accepted);
/// 2 refused (wrong argument count, blank or invalid URI); 3 the validated file
/// is not on disk and no IDE took it; 1 an unexpected failure.</returns>
/// <remarks>
/// <para>Overrides come ONLY from the environment: DRAGLINT_URI_TEST_WHATIF=1
/// validates, logs whatif: ok=0|1 reason=.. payload=.. (TAB and LF spelled
/// &lt;TAB&gt; and &lt;LF&gt;) and returns 0 or 2 without touching the pipe or
/// starting a process; DRAGLINT_URI_TEST_TIMEOUT (1-6 digits, default 1000) is
/// the pipe wait in ms.</para>
/// <para>Order: uri: line, ParseDragLintUri (refusal: rejected: reason), resolved:
/// line, WaitNamedPipe + CreateFile + WriteFile of the UTF-8 frame (sent N bytes
/// to the IDE), else IDE not running (system error text), then FileExists --
/// only ever on a path the gate accepted -- and CreateProcess of
/// System32\notepad.exe "file", never ShellExecute.</para>
/// <para>Never raises: an exception is logged as failed: and returns 1.</para>
/// </remarks>
function RunHandler(const pArgs: TArray<string>): Integer;

/// <summary>Appends one line to the handler log.</summary>
/// <param name="pText">The event text; may be attacker text (the URI). It is
/// capped at 512 chars plus ...(+N chars), and every control character becomes
/// '?', so one click is one bounded line.</param>
/// <remarks>The line is the local time as yyyy-MM-ddTHH:mm:ss, two spaces, the
/// text, CRLF, UTF-8 without BOM. The file is DRAGLINT_URI_TEST_LOG when set (its
/// folder is NOT created), else %LOCALAPPDATA%\drag-lint\logs\uri-handler.log,
/// whose folder is the only one this program ever creates; with neither there is
/// no log. A log that cannot be written is ignored: logging never stops a
/// click.</remarks>
procedure WriteHandlerLog(const pText: string);

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  DRagLint.Core.DragLintUri;

const
  PIPE_NAME          = '\\.\pipe\drag-lint-open-source';
  ENV_WHATIF         = 'DRAGLINT_URI_TEST_WHATIF';
  ENV_LOG            = 'DRAGLINT_URI_TEST_LOG';
  ENV_TIMEOUT        = 'DRAGLINT_URI_TEST_TIMEOUT';
  LOG_SUBDIR         = 'drag-lint\logs';
  LOG_NAME           = 'uri-handler.log';
  LOG_CAP            = 512;
  TIMEOUT_MAX_DIGITS = 6;
  DEFAULT_TIMEOUT_MS = 1000;
  EXIT_OK            = 0;
  EXIT_FAILED        = 1;
  EXIT_REFUSED       = 2;
  EXIT_NOT_FOUND     = 3;
  DEL_CHAR           = #127;

function CommandLineArgs: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, ParamCount);
  for I:= 1 to ParamCount do
    Result[I - 1]:= ParamStr(I);
end;

{ The text of one log line: capped, control characters as '?', stamped. }
function FormatLogLine(const pText: string): string;
var
  I: Integer;
begin
  Result:= pText;
  if Length(Result) > LOG_CAP then
    Result:= Copy(Result, 1, LOG_CAP) + Format('...(+%d chars)', [Length(pText) - LOG_CAP]);
  for I:= 1 to Length(Result) do
    if (Result[I] < ' ') or (Result[I] = DEL_CHAR) then
      Result[I]:= '?';
  Result:= FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now) + '  ' + Result;
end;

procedure WriteHandlerLog(const pText: string);
var
  LogPath: string;
  LogDir : string;
  Bytes  : TBytes;
  Stream : TFileStream;
begin
  LogDir:= '';
  LogPath:= GetEnvironmentVariable(ENV_LOG);
  if LogPath = '' then
  begin
    if GetEnvironmentVariable('LOCALAPPDATA') = '' then
      Exit;
    LogDir:= IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + LOG_SUBDIR;
    LogPath:= IncludeTrailingPathDelimiter(LogDir) + LOG_NAME;
  end;
  Bytes:= TEncoding.UTF8.GetBytes(FormatLogLine(pText) + sLineBreak);
  try
    if (LogDir <> '') and not DirectoryExists(LogDir) then
      ForceDirectories(LogDir);
    if FileExists(LogPath) then
      Stream:= TFileStream.Create(LogPath, fmOpenWrite or fmShareDenyWrite)
    else
      Stream:= TFileStream.Create(LogPath, fmCreate or fmShareDenyWrite);
    try
      Stream.Seek(0, soEnd);
      Stream.WriteBuffer(Bytes, Length(Bytes));
    finally
      Stream.Free;
    end;
  except
    { logging never stops a click (the script's catch): a locked log, a missing
      DRAGLINT_URI_TEST_LOG folder or a denied LOCALAPPDATA goes to the debugger only }
    on E: Exception do
      OutputDebugString(PChar('drag-lint-open: log not written: ' + E.Message));  // dl:ok outputdebugstring@c532 -- REVIEWED 2026-10-14: deliberate; the log itself failed and a GUI handler has no other channel
  end;
end;

{ The what-if verdict line; the frame's TAB and LF spelled out so the log keeps them. }
procedure LogWhatIf(const pOk: Boolean; const pReason, pPayload: string);
const
  OK_FLAG: array[Boolean] of string = ('0', '1');
var
  Shown: string;
begin
  Shown:= StringReplace(StringReplace(pPayload, #9, '<TAB>', [rfReplaceAll]), #10, '<LF>', [rfReplaceAll]);
  WriteHandlerLog('whatif: ok=' + OK_FLAG[pOk] + ' reason=' + pReason + ' payload=' + Shown);
end;

function Refuse(const pReason: string; const pWhatIf: Boolean): Integer;
begin
  WriteHandlerLog('rejected: ' + pReason);
  if pWhatIf then
    LogWhatIf(False, pReason, '');
  Result:= EXIT_REFUSED;
end;

{ DRAGLINT_URI_TEST_TIMEOUT when it is 1-6 ASCII digits, else the default. 0 is
  taken as 1: WaitNamedPipe reads 0 as "the server's default wait". }
function PipeTimeoutMs: DWORD;
var
  S: string;
  C: Char;
begin
  S:= GetEnvironmentVariable(ENV_TIMEOUT);
  if (S = '') or (Length(S) > TIMEOUT_MAX_DIGITS) then
    Exit(DEFAULT_TIMEOUT_MS);
  for C in S do
    if not CharInSet(C, ['0'..'9']) then
      Exit(DEFAULT_TIMEOUT_MS);
  Result:= DWORD(StrToInt(S));
  if Result = 0 then
    Result:= 1;
end;

{ One frame to \\.\pipe\drag-lint-open-source (OpenSourceServer.pas:12-19). }
function SendToIde(const pPayload: string; out pSent: Integer; out pError: string): Boolean;
var
  Bytes  : TBytes;
  Pipe   : THandle;
  Written: DWORD;
begin
  Result:= False;
  pSent:= 0;
  pError:= '';
  Bytes:= TEncoding.UTF8.GetBytes(pPayload);
  if not WaitNamedPipe(PChar(PIPE_NAME), PipeTimeoutMs) then
  begin
    pError:= SysErrorMessage(GetLastError);
    Exit;
  end;
  Pipe:= CreateFile(PChar(PIPE_NAME), GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if Pipe = INVALID_HANDLE_VALUE then
  begin
    pError:= SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    if not WriteFile(Pipe, Bytes[0], Length(Bytes), Written, nil) or (Integer(Written) <> Length(Bytes)) then
    begin
      pError:= SysErrorMessage(GetLastError);
      Exit;
    end;
    pSent:= Written;
    Result:= True;
  finally
    CloseHandle(Pipe);
  end;
end;

{ notepad only displays text; ShellExecute of the default verb would run whatever
  the machine associates with the extension. pFile passed the gate: no quote in it. }
function OpenInNotepad(const pFile: string; out pError: string): Boolean;
var
  SysDir : array[0..MAX_PATH] of Char;
  Exe    : string;
  Cmd    : string;
  Startup: TStartupInfo;
  Proc   : TProcessInformation;
begin
  pError:= '';
  SetString(Exe, SysDir, GetSystemDirectory(SysDir, Length(SysDir)));
  Exe:= IncludeTrailingPathDelimiter(Exe) + 'notepad.exe';
  Cmd:= '"' + Exe + '" "' + pFile + '"';
  UniqueString(Cmd);
  FillChar(Startup, SizeOf(Startup), 0);
  Startup.cb:= SizeOf(Startup);
  Result:= CreateProcess(PChar(Exe), PChar(Cmd), nil, nil, False, 0, nil, nil, Startup, Proc);
  if Result then
  begin
    CloseHandle(Proc.hThread);
    CloseHandle(Proc.hProcess);
  end
  else
    pError:= SysErrorMessage(GetLastError);
end;

function HandleUri(const pUri: string; const pWhatIf: Boolean): Integer;
var
  Target: TDragLintTarget;
  Reason: string;
  Sent  : Integer;
begin
  WriteHandlerLog('uri: ' + pUri);
  if not ParseDragLintUri(pUri, Target, Reason) then
    Exit(Refuse(Reason, pWhatIf));
  WriteHandlerLog(Format('resolved: file=%s line=%d col=%s', [Target.File_, Target.Line, if Target.Col <> '' then Target.Col else '-']));
  if pWhatIf then
  begin
    LogWhatIf(True, '', Target.Payload);
    Exit(EXIT_OK);
  end;
  if SendToIde(Target.Payload, Sent, Reason) then
  begin
    WriteHandlerLog(Format('sent %d bytes to the IDE', [Sent]));
    Exit(EXIT_OK);
  end;
  WriteHandlerLog('IDE not running (' + Reason + ')');
  { a validated LOCAL drive path is the only thing that reaches this FileExists }
  if not FileExists(Target.File_) then
  begin
    WriteHandlerLog('file not found on disk: ' + Target.File_);
    Exit(EXIT_NOT_FOUND);
  end;
  if not OpenInNotepad(Target.File_, Reason) then
  begin
    WriteHandlerLog('could not start notepad (' + Reason + ')');
    Exit(EXIT_FAILED);
  end;
  WriteHandlerLog(Format('opened in notepad (line %d is not positioned there)', [Target.Line]));
  Result:= EXIT_OK;
end;

function RunHandler(const pArgs: TArray<string>): Integer;
var
  WhatIf: Boolean;
  Shown : string;
  Arg   : string;
begin
  try
    WhatIf:= GetEnvironmentVariable(ENV_WHATIF) = '1';
    { exactly one argument, and it is the URI -- before anything else is looked at }
    if Length(pArgs) <> 1 then
    begin
      Shown:= '';
      for Arg in pArgs do
        Shown:= Shown + (if Shown = '' then '' else ' ') + '[' + Arg + ']';
      WriteHandlerLog('args: ' + Shown);
      Exit(Refuse(Format('expected exactly one argument, the draglint:// uri (got %d)', [Length(pArgs)]), WhatIf));
    end;
    if Trim(pArgs[0]) = '' then
      Exit(Refuse('no uri given', WhatIf));
    Result:= HandleUri(pArgs[0], WhatIf);
  except
    on E: Exception do
    begin
      WriteHandlerLog('failed: ' + E.ClassName + ': ' + E.Message);
      Result:= EXIT_FAILED;
    end;
  end;
end;

end.
