unit DragLint.Plugin.LspClient;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.Generics.Collections, System.SyncObjs,
  Winapi.Windows;

procedure DebugLog(const AMsg: string);  // appends to %TEMP%\drag-lint-plugin.log

type
  TLspNotificationHandler = reference to procedure(const AMethod: string;
    AParams: TJSONValue);

  TDragLintLspClient = class
  strict private
    FProcessHandle: THandle;
    FProcessId: DWORD;
    FStdInWrite: THandle;
    FStdOutRead: THandle;
    FReaderThread: TThread;
    FPendingRequests: TDictionary<Integer, TEvent>;
    FResponses: TDictionary<Integer, TJSONValue>;
    FLock: TCriticalSection;
    FNextId: Integer;
    FOnNotification: TLspNotificationHandler;
    procedure WriteFramedMessage(const AJson: string);
  private
    { Accessible to TLspReaderThread in same unit }
    procedure DispatchMessage(AMsg: TJSONValue);
  public
    constructor Create;
    destructor Destroy; override;
    function Start(const AExePath: string): Boolean;
    procedure Stop;
    function Initialize: Boolean;
    function Request(const AMethod: string; AParams: TJSONValue;
      ATimeoutMs: Integer = 5000): TJSONValue;
    procedure Notify(const AMethod: string; AParams: TJSONValue);
    property OnNotification: TLspNotificationHandler
      read FOnNotification write FOnNotification;
  end;

implementation

{ ---- Debug log ---- }

var
  GLogLock: TCriticalSection = nil;

procedure DebugLog(const AMsg: string);
var
  LogPath: string;
  Stream: TFileStream;
  Line: AnsiString;
begin
  if GLogLock = nil then GLogLock := TCriticalSection.Create;
  GLogLock.Enter;
  try
    try
      LogPath := TPath.Combine(TPath.GetTempPath, 'drag-lint-plugin.log');
      Line := AnsiString(Format('[%s] %s'#13#10,
        [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), AMsg]));
      if FileExists(LogPath) then
        Stream := TFileStream.Create(LogPath, fmOpenWrite or fmShareDenyNone)
      else
        Stream := TFileStream.Create(LogPath, fmCreate or fmShareDenyNone);
      try
        Stream.Seek(0, soEnd);
        Stream.WriteBuffer(Line[1], Length(Line));
      finally
        Stream.Free;
      end;
    except
      // swallow log errors silently
    end;
  finally
    GLogLock.Leave;
  end;
end;

{ Reader thread }

type
  TLspReaderThread = class(TThread)
  private
    FOwner: TDragLintLspClient;
    FHandle: THandle;
    function ReadBytes(ABuf: PByte; ACount: Integer): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TDragLintLspClient; AHandle: THandle);
  end;

constructor TLspReaderThread.Create(AOwner: TDragLintLspClient;
  AHandle: THandle);
begin
  inherited Create(False);
  FOwner := AOwner;
  FHandle := AHandle;
  FreeOnTerminate := False;
end;

function TLspReaderThread.ReadBytes(ABuf: PByte; ACount: Integer): Boolean;
var
  Remaining, Read: DWORD;
  Ok: LongBool;
begin
  Remaining := ACount;
  while Remaining > 0 do
  begin
    Ok := ReadFile(FHandle, ABuf^, Remaining, Read, nil);
    if (not Ok) or (Read = 0) then
      Exit(False);
    Inc(ABuf, Read);
    Dec(Remaining, Read);
  end;
  Result := True;
end;

procedure TLspReaderThread.Execute;
var
  Ch: Byte;
  Read: DWORD;
  Ok: LongBool;
  HeaderBuf: AnsiString;
  Seq: Integer;           { how many of the 4-char CRLF CRLF we matched }
  ContentLength: Integer;
  BodyBuf: TBytes;
  JsonStr: string;
  JsonVal: TJSONValue;
  Pos: Integer;
  S: string;
begin
  DebugLog('ReaderThread: started');
  while not Terminated do
  begin
    { Read header byte-by-byte until CRLFCRLF }
    HeaderBuf := '';
    Seq := 0;
    repeat
      Ok := ReadFile(FHandle, Ch, 1, Read, nil);
      if (not Ok) or (Read = 0) then
      begin
        DebugLog(Format('ReaderThread: ReadFile failed/EOF, Ok=%s Read=%d GetLastError=%d',
          [BoolToStr(Ok, True), Read, GetLastError]));
        Exit;
      end;
      HeaderBuf := HeaderBuf + AnsiChar(Ch);
      { track the CRLFCRLF sequence }
      case Seq of
        0: if Ch = 13 then Seq := 1 else Seq := 0;
        1: if Ch = 10 then Seq := 2 else if Ch = 13 then Seq := 1 else Seq := 0;
        2: if Ch = 13 then Seq := 3 else Seq := 0;
        3: if Ch = 10 then Seq := 4 else if Ch = 13 then Seq := 1 else Seq := 0;
      end;
    until Seq = 4;

    { Parse Content-Length }
    ContentLength := 0;
    S := string(HeaderBuf);
    Pos := System.Pos('Content-Length:', S);
    if Pos = 0 then
      Pos := System.Pos('content-length:', LowerCase(S));
    if Pos > 0 then
    begin
      Inc(Pos, Length('Content-Length:'));
      while (Pos <= Length(S)) and (S[Pos] = ' ') do Inc(Pos);
      while (Pos <= Length(S)) and (S[Pos] >= '0') and (S[Pos] <= '9') do
      begin
        ContentLength := ContentLength * 10 + Ord(S[Pos]) - Ord('0');
        Inc(Pos);
      end;
    end;

    if ContentLength <= 0 then
      Continue;

    { Read body }
    SetLength(BodyBuf, ContentLength);
    if not ReadBytes(@BodyBuf[0], ContentLength) then
      Exit;

    { Decode and parse }
    JsonStr := TEncoding.UTF8.GetString(BodyBuf);
    DebugLog(Format('ReaderThread: rx %d bytes: %s',
      [ContentLength, Copy(JsonStr, 1, 200)]));
    JsonVal := TJSONObject.ParseJSONValue(JsonStr);
    if JsonVal <> nil then
      FOwner.DispatchMessage(JsonVal)
    else
      DebugLog('ReaderThread: JSON parse failed');
  end;
  DebugLog('ReaderThread: terminated normally');
end;

{ TDragLintLspClient }

constructor TDragLintLspClient.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FPendingRequests := TDictionary<Integer, TEvent>.Create;
  FResponses := TDictionary<Integer, TJSONValue>.Create;
  FNextId := 1;
  FProcessHandle := 0;
  FStdInWrite := INVALID_HANDLE_VALUE;
  FStdOutRead := INVALID_HANDLE_VALUE;
  FReaderThread := nil;
end;

destructor TDragLintLspClient.Destroy;
begin
  Stop;
  FPendingRequests.Free;
  FResponses.Free;
  FLock.Free;
  inherited Destroy;
end;

function TDragLintLspClient.Start(const AExePath: string): Boolean;
var
  SA: TSecurityAttributes;
  hReadIn, hWriteIn: THandle;
  hReadOut, hWriteOut: THandle;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  CmdLine: string;
  CmdLineW: array of WideChar;
  LastErr: DWORD;
begin
  Result := False;
  DebugLog('Start: ExePath=' + AExePath);
  DebugLog('Start: AExePath FileExists=' + BoolToStr(FileExists(AExePath), True));

  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  { stdin pipe: child reads from hReadIn, parent writes to hWriteIn }
  if not CreatePipe(hReadIn, hWriteIn, @SA, 0) then
  begin
    DebugLog('Start: CreatePipe(stdin) FAILED, GetLastError=' + IntToStr(GetLastError));
    Exit;
  end;
  { don't let child inherit the write end }
  SetHandleInformation(hWriteIn, HANDLE_FLAG_INHERIT, 0);

  { stdout pipe: parent reads from hReadOut, child writes to hWriteOut }
  if not CreatePipe(hReadOut, hWriteOut, @SA, 0) then
  begin
    CloseHandle(hReadIn);
    CloseHandle(hWriteIn);
    Exit;
  end;
  { don't let child inherit the read end }
  SetHandleInformation(hReadOut, HANDLE_FLAG_INHERIT, 0);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES;
  SI.hStdInput := hReadIn;
  SI.hStdOutput := hWriteOut;
  SI.hStdError := hWriteOut;

  ZeroMemory(@PI, SizeOf(PI));

  { Quote the exe path to handle paths with spaces (e.g. Program Files). }
  CmdLine := '"' + AExePath + '" lsp';
  DebugLog('Start: CmdLine=' + CmdLine);
  SetLength(CmdLineW, Length(CmdLine) + 1);
  Move(PChar(CmdLine)^, CmdLineW[0], (Length(CmdLine) + 1) * SizeOf(WideChar));

  if not CreateProcessW(nil, @CmdLineW[0], nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    LastErr := GetLastError;
    DebugLog('Start: CreateProcessW FAILED, GetLastError=' + IntToStr(LastErr));
    CloseHandle(hReadIn);
    CloseHandle(hWriteIn);
    CloseHandle(hReadOut);
    CloseHandle(hWriteOut);
    Exit;
  end;
  DebugLog('Start: CreateProcessW OK, ProcessId=' + IntToStr(PI.dwProcessId));

  { Close child-side handles in the parent }
  CloseHandle(hReadIn);
  CloseHandle(hWriteOut);
  CloseHandle(PI.hThread);

  FProcessHandle := PI.hProcess;
  FProcessId := PI.dwProcessId;
  FStdInWrite := hWriteIn;
  FStdOutRead := hReadOut;

  FReaderThread := TLspReaderThread.Create(Self, FStdOutRead);
  Result := True;
  DebugLog('Start: success, reader thread launched');
end;

procedure TDragLintLspClient.Stop;
var
  WaitResult: DWORD;
begin
  if FReaderThread <> nil then
  begin
    FReaderThread.Terminate;
    { Close the read handle so the reader thread unblocks from ReadFile }
    if FStdOutRead <> INVALID_HANDLE_VALUE then
    begin
      CloseHandle(FStdOutRead);
      FStdOutRead := INVALID_HANDLE_VALUE;
    end;
    FReaderThread.WaitFor;
    FReaderThread.Free;
    FReaderThread := nil;
  end;

  if FStdInWrite <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FStdInWrite);
    FStdInWrite := INVALID_HANDLE_VALUE;
  end;

  if FProcessHandle <> 0 then
  begin
    WaitResult := WaitForSingleObject(FProcessHandle, 2000);
    if WaitResult <> WAIT_OBJECT_0 then
      TerminateProcess(FProcessHandle, 0);
    CloseHandle(FProcessHandle);
    FProcessHandle := 0;
  end;
end;

function TDragLintLspClient.Initialize: Boolean;
var
  Params: TJSONObject;
  Resp: TJSONValue;
begin
  DebugLog('Initialize: sending initialize request');
  Params := TJSONObject.Create;
  Params.AddPair('processId', TJSONNumber.Create(GetCurrentProcessId));
  Params.AddPair('capabilities', TJSONObject.Create);
  try
    Resp := Request('initialize', Params, 10000);  // bumped from 5000
    Result := Resp <> nil;
    if Result then
    begin
      DebugLog('Initialize: response received OK');
      Resp.Free;
    end
    else
      DebugLog('Initialize: TIMEOUT or no response within 10s');
  finally
    Params.Free;
  end;
end;

function TDragLintLspClient.Request(const AMethod: string;
  AParams: TJSONValue; ATimeoutMs: Integer): TJSONValue;
var
  Id: Integer;
  Evt: TEvent;
  Msg: TJSONObject;
begin
  FLock.Enter;
  try
    Id := FNextId;
    Inc(FNextId);
  finally
    FLock.Leave;
  end;

  Evt := TEvent.Create(nil, True, False, '');
  FLock.Enter;
  try
    FPendingRequests.Add(Id, Evt);
  finally
    FLock.Leave;
  end;

  Msg := TJSONObject.Create;
  Msg.AddPair('jsonrpc', '2.0');
  Msg.AddPair('id', TJSONNumber.Create(Id));
  Msg.AddPair('method', AMethod);
  if AParams <> nil then
    Msg.AddPair('params', AParams.Clone as TJSONValue)
  else
    Msg.AddPair('params', TJSONObject.Create);
  try
    WriteFramedMessage(Msg.ToString);
  finally
    Msg.Free;
  end;

  if Evt.WaitFor(ATimeoutMs) = wrSignaled then
  begin
    FLock.Enter;
    try
      if FResponses.ContainsKey(Id) then
      begin
        Result := FResponses[Id];
        FResponses.Remove(Id);
      end
      else
        Result := nil;
      FPendingRequests.Remove(Id);
    finally
      FLock.Leave;
    end;
  end
  else
    Result := nil;
  Evt.Free;
end;

procedure TDragLintLspClient.Notify(const AMethod: string;
  AParams: TJSONValue);
var
  Msg: TJSONObject;
begin
  Msg := TJSONObject.Create;
  Msg.AddPair('jsonrpc', '2.0');
  Msg.AddPair('method', AMethod);
  if AParams <> nil then
    Msg.AddPair('params', AParams.Clone as TJSONValue)
  else
    Msg.AddPair('params', TJSONObject.Create);
  try
    WriteFramedMessage(Msg.ToString);
  finally
    Msg.Free;
  end;
end;

procedure TDragLintLspClient.WriteFramedMessage(const AJson: string);
var
  Bytes: TBytes;
  Header: AnsiString;
  Written: DWORD;
  HdrW, BodyW: BOOL;
  LastErr: DWORD;
begin
  Bytes := TEncoding.UTF8.GetBytes(AJson);
  Header := AnsiString(Format('Content-Length: %d'#13#10#13#10, [Length(Bytes)]));
  DebugLog(Format('Tx: %d bytes: %s', [Length(Bytes), Copy(AJson, 1, 200)]));
  FLock.Enter;
  try
    HdrW := WriteFile(FStdInWrite, Header[1], Length(Header), Written, nil);
    if not HdrW then
    begin
      LastErr := GetLastError;
      DebugLog(Format('WriteFile(header) FAILED, GetLastError=%d', [LastErr]));
    end;
    if Length(Bytes) > 0 then
    begin
      BodyW := WriteFile(FStdInWrite, Bytes[0], Length(Bytes), Written, nil);
      if not BodyW then
      begin
        LastErr := GetLastError;
        DebugLog(Format('WriteFile(body) FAILED, GetLastError=%d', [LastErr]));
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintLspClient.DispatchMessage(AMsg: TJSONValue);
var
  IdVal: TJSONValue;
  Id: Integer;
  Evt: TEvent;
  MethodVal: TJSONValue;
  ParamsVal: TJSONValue;
  MethodStr: string;
begin
  IdVal := (AMsg as TJSONObject).GetValue('id');
  if IdVal <> nil then
  begin
    { It's a response if it has 'result' or 'error' }
    if ((AMsg as TJSONObject).GetValue('result') <> nil) or
       ((AMsg as TJSONObject).GetValue('error') <> nil) then
    begin
      Id := (IdVal as TJSONNumber).AsInt;
      FLock.Enter;
      try
        if FPendingRequests.TryGetValue(Id, Evt) then
        begin
          FResponses.AddOrSetValue(Id, AMsg);
          Evt.SetEvent;
        end
        else
          AMsg.Free;
      finally
        FLock.Leave;
      end;
      Exit;
    end;
  end;

  { Notification or server-to-client request }
  MethodVal := (AMsg as TJSONObject).GetValue('method');
  if (MethodVal <> nil) and Assigned(FOnNotification) then
  begin
    MethodStr := MethodVal.Value;
    ParamsVal := (AMsg as TJSONObject).GetValue('params');
    FOnNotification(MethodStr, ParamsVal);
  end;
  { We do NOT free AMsg here when it's a notification and we called the handler,
    because the caller may hold references. For safety, free it now since the
    handler is synchronous and done by the time we return. }
  AMsg.Free;
end;

initialization

finalization
  if GLogLock <> nil then
  begin
    GLogLock.Free;
    GLogLock := nil;
  end;

end.
