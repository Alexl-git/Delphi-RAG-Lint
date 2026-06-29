unit DragLint.Plugin.ProcRun;

{ Shared stdout/stderr capture for spawning drag-lint.exe with no console
  window. Extracted from UsagesForm/SymbolSearchForm (identical copies). }

interface

uses
  System.SysUtils;

type
  /// <summary>Line callback for RunCaptureStreaming. TProc&lt;string&gt; allows
  /// anonymous closures so callers can capture local variables inline.</summary>
  TOnLineProc = TProc<string>;

/// <summary>Spawns ACmdLine (CREATE_NO_WINDOW), captures stdout+stderr into
/// AOutput, waits up to ATimeoutMs (&lt;=0 = INFINITE), and returns the child
/// exit code, or a negative value if the process could not be started.</summary>
function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;

/// <summary>Spawns ACmdLine (CREATE_NO_WINDOW), reads stdout+stderr line-by-line,
/// and invokes AOnLine per complete line. Returns when the child process exits.
/// Caller may invoke AOnLine from any context; if UI thread sync is needed, the
/// caller marshals (typically via TThread.Queue). On success, returns True and
/// AExitCode contains the exit code; on failure (e.g. process not found), returns
/// False and AExitCode is undefined.</summary>
function RunCaptureStreaming(const ACmdLine: string; AOnLine: TOnLineProc; out AExitCode: Integer): Boolean;

implementation

uses
  Winapi.Windows;

function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;
var
  SA       : TSecurityAttributes       ;
  ReadPipe : THandle                   ;
  WritePipe: THandle                   ;
  SI       : TStartupInfoW             ;
  PI       : TProcessInformation       ;
  Buf      : array[0..4095] of AnsiChar;
  BytesRead: DWORD                     ;
  ExitCode : DWORD                     ;
  WideCmd  : string                    ;
  SB       : TStringBuilder            ;
  TV       : DWORD                     ;
begin
  Result:= -1;
  AOutput:= '';
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    SB:= TStringBuilder.Create;
    try
      repeat
        BytesRead:= 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead]:= #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput:= SB.ToString;
    finally
      SB.Free;
    end;
    if ATimeoutMs <= 0 then TV:= INFINITE else TV:= DWORD(ATimeoutMs);
    WaitForSingleObject(PI.hProcess, TV);
    GetExitCodeProcess (PI.hProcess, ExitCode);
    Result:= Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  finally
    CloseHandle(ReadPipe);
  end;
end;

function RunCaptureStreaming(const ACmdLine: string; AOnLine: TOnLineProc; out AExitCode: Integer): Boolean;
var
  SA       : TSecurityAttributes;
  ReadPipe : THandle;
  WritePipe: THandle;
  SI       : TStartupInfoW;
  PI       : TProcessInformation;
  Buf      : array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  ExitCode : DWORD;
  WideCmd  : string;
  LineBuffer: AnsiString;
  StartPos, LineEnd: Integer;
  TempStr: AnsiString;
begin
  Result:= False;
  AExitCode:= -1;
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    LineBuffer:= '';
    repeat
      BytesRead:= 0;
      if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
      if BytesRead = 0 then Break;
      Buf[BytesRead]:= #0;
      TempStr:= AnsiString(Buf);
      LineBuffer:= LineBuffer + TempStr;

      { Process complete lines from LineBuffer. }
      StartPos:= 1;
      repeat
        LineEnd:= Pos(#10, LineBuffer, StartPos);
        if LineEnd = 0 then Break;
        { Extract line, trimming trailing #13 if present (CRLF -> LF). }
        TempStr:= Copy(LineBuffer, StartPos, LineEnd - StartPos);
        if (Length(TempStr) > 0) and (TempStr[Length(TempStr)] = #13) then
          SetLength(TempStr, Length(TempStr) - 1);
        AOnLine(string(TempStr));
        StartPos:= LineEnd + 1;
      until False;

      { Keep unprocessed tail for next iteration. }
      if StartPos <= Length(LineBuffer) then
        LineBuffer:= Copy(LineBuffer, StartPos, MaxInt)
      else
        LineBuffer:= '';
    until False;

    { Invoke AOnLine for any remaining partial line at EOF. }
    if Length(LineBuffer) > 0 then AOnLine(string(LineBuffer));

    WaitForSingleObject(PI.hProcess, INFINITE);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    AExitCode:= Integer(ExitCode);
    Result:= True;
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(ReadPipe);
  end;
end;

end.
