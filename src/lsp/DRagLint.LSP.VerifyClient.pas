unit DRagLint.LSP.VerifyClient;

{ 1.53.0 LSP1-VERB: a minimal SYNCHRONOUS LSP client for batch verbs (verify-index).

  WHY NOT THE PROXY'S FRAMING. DRagLint.LSP.Proxy relays two live streams between an
  editor and DelphiLSP with pump threads; its framing helpers are implementation-only
  and shaped for that. A batch verb needs the opposite: send one request, wait for its
  response, answer whatever the server asks meanwhile, no threads. This unit knows
  nothing about the index. }

interface

uses
    System.SysUtils
  , System.JSON
  ;

type
  /// <summary>Raised when the child cannot be started.</summary>
  ELspClientError = class(Exception);

  /// <summary>Minimal synchronous LSP client over a child process's stdio, for batch verbs.
  /// Not thread-safe; one instance per run.</summary>
  /// <remarks>Requests are answered in order; while waiting for a response the client consumes
  /// notifications (dropped, traced) and answers server-to-client requests via OnServerRequest
  /// (default: result null). The child is assigned to the drag-lint job object, so it never
  /// outlives the verb.</remarks>
  TLspVerifyClient = class  // dl:ok high-response@2155 -- REVIEWED 2026-11-23: one cohesive job -- the child-process JSON-RPC session (spawn, initialize, didOpen, request, shutdown); the response set is the callee set of that single linear protocol script, not unrelated responsibilities
  strict private
    FExe     : string;
    FTrace   : string;
    FProc    : THandle;
    FIn      : THandle;
    FOut     : THandle;
    FNextId  : Integer;
    FAcc     : TBytes;
    FAccLen  : Integer;
    FLastError: string;
    FOnServerRequest: TFunc<string, TJSONValue, string>;
    procedure TraceFrame(const pTag, pBody: string);
    procedure Send(const pBody: string);
    function TakeFrame(out pBody: string): Boolean;
    function ReadFrame(pDeadline: UInt64; out pBody, pError: string): Boolean;
    procedure ReplyToServer(pRequest: TJSONObject);
    function ProcessFrame(const pBody: string; pAwaitId: Integer; out pResult: TJSONValue;
      out pError: string): Integer;
    procedure CloseHandles;
  public
    /// <summary>Creates an unstarted client.</summary>
    /// <param name="pExe">Full path of the server executable.</param>
    /// <param name="pTraceFile">'' = no trace; else every frame appended with C>S / S>C tags.</param>
    constructor Create(const pExe, pTraceFile: string);
    /// <summary>Runs Shutdown when the child still runs, then closes the handles.</summary>
    destructor Destroy; override;
    /// <summary>Spawns the child with redirected stdin/stdout; stderr is inherited.</summary>
    /// <exception cref="ELspClientError">CreateProcess or CreatePipe failed.</exception>
    procedure Start;
    /// <summary>Sends a request and waits for its response.</summary>
    /// <param name="pMethod">LSP method name.</param>
    /// <param name="pMethod">LSP method name.</param>
    /// <param name="pParams">Owned by the call (freed after sending); nil omits params.</param>
    /// <param name="pTimeoutMs">Wall-clock wait for the response.</param>
    /// <param name="pResult">On success the response's result (cloned; caller frees; may be TJSONNull); else nil.</param>
    /// <param name="pError">On failure: the error message, 'timeout' or 'server exited'.</param>
    /// <returns>True when a response with a result arrived in time.</returns>
    function Request(const pMethod: string; pParams: TJSONValue; pTimeoutMs: Integer;
      out pResult: TJSONValue; out pError: string): Boolean;
    /// <summary>Sends a notification. pParams is owned by the call; nil omits params.</summary>
    /// <param name="pMethod">LSP method name.</param>
    /// <param name="pParams">Params object, owned by the call; nil omits params.</param>
    procedure Notify(const pMethod: string; pParams: TJSONValue);
    /// <summary>Reads and handles incoming frames for pMs milliseconds (warm-up).</summary>
    /// <param name="pMs">Wall-clock milliseconds to keep reading.</param>
    procedure Pump(pMs: Integer);
    /// <summary>shutdown (2 s) + exit, close stdin, wait 5 s, TerminateProcess when still alive.</summary>
    /// <remarks>Never raises; safe to call twice.</remarks>
    procedure Shutdown;
    /// <summary>Message of the last write, trace or shutdown failure that was absorbed instead of raised; '' = none.</summary>
    property LastError: string read FLastError;
    /// <summary>Answer for a server-to-client request: (method, params) -> result JSON text.
    /// nil = reply null.</summary>
    property OnServerRequest: TFunc<string, TJSONValue, string> read FOnServerRequest write FOnServerRequest;
  end;

implementation

uses
    Winapi.Windows
  , System.Classes
  , System.IOUtils
  , DRagLint.Core.JobObject
  ;

const
  CRLF2            = #13#10#13#10;
  POLL_SLEEP_MS    = 5;
  SHUTDOWN_REQ_MS  = 2000;
  SHUTDOWN_WAIT_MS = 5000;
  READ_CHUNK       = 65536;
  CR               = 13;
  LF               = 10;
  KIND_OTHER       = 0;
  KIND_RESPONSE    = 1;
  KIND_FAILED      = 2;

{ TLspVerifyClient }

constructor TLspVerifyClient.Create(const pExe, pTraceFile: string);
begin
  inherited Create;
  FExe:= pExe;
  FTrace:= pTraceFile;
  FNextId:= 1;
end;

destructor TLspVerifyClient.Destroy;
begin
  Shutdown;
  inherited;
end;

procedure TLspVerifyClient.CloseHandles;
begin
  if FIn <> 0 then CloseHandle(FIn);
  if FOut <> 0 then CloseHandle(FOut);
  if FProc <> 0 then CloseHandle(FProc);
  FIn:= 0;
  FOut:= 0;
  FProc:= 0;
end;

procedure TLspVerifyClient.TraceFrame(const pTag, pBody: string);
begin
  if FTrace = '' then Exit;
  try
    TFile.AppendAllText(FTrace, pTag + ' ' + pBody + #13#10, TEncoding.UTF8);
  except  // dl:ok try-except-swallowed@c04d -- REVIEWED 2026-11-23 LSP1-VERB: the trace file is a diagnostic aid; a failed append is kept in LastError and never fails the measurement
    on E: Exception do FLastError:= E.Message;   { a trace that cannot be written never fails the run }
  end;
end;

procedure TLspVerifyClient.Start;
var
  Sa     : TSecurityAttributes;
  InRd   : THandle;
  InWr   : THandle;
  OutRd  : THandle;
  OutWr  : THandle;
  SI     : TStartupInfo;
  PI     : TProcessInformation;
  Cmd    : string;
  Created: Boolean;
begin
  Sa.nLength:= SizeOf(Sa);
  Sa.bInheritHandle:= True;
  Sa.lpSecurityDescriptor:= nil;
  if not CreatePipe(InRd, InWr, @Sa, 0) then raise ELspClientError.Create('CreatePipe failed (stdin)');
  if not CreatePipe(OutRd, OutWr, @Sa, 0) then
  begin
    CloseHandle(InRd);
    CloseHandle(InWr);
    raise ELspClientError.Create('CreatePipe failed (stdout)');
  end;
  SetHandleInformation(InWr, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(OutRd, HANDLE_FLAG_INHERIT, 0);
  ZeroMemory(@SI, SizeOf(SI));
  SI.cb:= SizeOf(SI);
  SI.dwFlags:= STARTF_USESTDHANDLES;
  SI.hStdInput:= InRd;
  SI.hStdOutput:= OutWr;
  SI.hStdError:= GetStdHandle(STD_ERROR_HANDLE);
  Cmd:= '"' + FExe + '"';
  UniqueString(Cmd);
  Created:= CreateProcess(PChar(FExe), PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI);  // dl:ok taint-command-injection@2436 -- REVIEWED 2026-11-23 LSP1-VERB: the executable is the DelphiLSP path from the Studio registry or --delphi-lsp, checked with FileExists by RunVerifyIndex, and passed as lpApplicationName; no user text reaches the command line
  CloseHandle(InRd);
  CloseHandle(OutWr);
  if not Created then
  begin
    CloseHandle(InWr);
    CloseHandle(OutRd);
    raise ELspClientError.CreateFmt('cannot start %s (error %d)', [FExe, GetLastError]);
  end;
  AssignToDragLintJob(PI.hProcess);
  CloseHandle(PI.hThread);
  FProc:= PI.hProcess;
  FIn:= InWr;
  FOut:= OutRd;
end;

procedure TLspVerifyClient.Send(const pBody: string);
var
  Body  : TBytes;
  Head  : TBytes;
  Sent  : DWORD;
  Offset: Integer;

  procedure WriteAll(const pBytes: TBytes);
  begin
    Offset:= 0;
    while Offset < Length(pBytes) do
    begin
      Sent:= 0;
      if (not WriteFile(FIn, pBytes[Offset], DWORD(Length(pBytes) - Offset), Sent, nil)) or (Sent = 0) then
        raise ELspClientError.Create('write to server failed');
      Inc(Offset, Integer(Sent));
    end;
  end;

begin
  Body:= TEncoding.UTF8.GetBytes(pBody);
  Head:= TEncoding.ASCII.GetBytes('Content-Length: ' + IntToStr(Length(Body)) + CRLF2);
  TraceFrame('C>S', pBody);
  WriteAll(Head);
  WriteAll(Body);
end;

function TLspVerifyClient.TakeFrame(out pBody: string): Boolean;
var
  i      : Integer;
  HdrEnd : Integer;
  BodyLen: Integer;
  Line   : string;
  Head   : string;
  Total  : Integer;
begin
  Result:= False;
  pBody:= '';
  HdrEnd:= -1;
  for i:= 0 to FAccLen - Length(CRLF2) do
    if (FAcc[i] = CR) and (FAcc[i + 1] = LF) and (FAcc[i + 2] = CR) and (FAcc[i + 3] = LF) then
    begin
      HdrEnd:= i;
      Break;
    end;
  if HdrEnd < 0 then Exit;
  Head:= TEncoding.ASCII.GetString(FAcc, 0, HdrEnd);
  BodyLen:= -1;
  for Line in Head.Split([#13#10]) do
    if Line.ToLower.StartsWith('content-length:') then
      BodyLen:= StrToIntDef(Trim(Copy(Line, Length('content-length:') + 1, MaxInt)), -1);
  if BodyLen < 0 then BodyLen:= 0;   { unreadable header: drop it, keep going }
  Total:= HdrEnd + Length(CRLF2) + BodyLen;
  if FAccLen < Total then Exit;
  pBody:= TEncoding.UTF8.GetString(FAcc, HdrEnd + Length(CRLF2), BodyLen);
  Dec(FAccLen, Total);
  if (FAccLen > 0) and (Total < Length(FAcc)) then Move(FAcc[Total], FAcc[0], FAccLen);
  Result:= True;
end;

function TLspVerifyClient.ReadFrame(pDeadline: UInt64; out pBody, pError: string): Boolean;
var
  Avail: DWORD;
  Got  : DWORD;
  Want : DWORD;
begin
  Result:= False;
  pError:= '';
  while True do
  begin
    if TakeFrame(pBody) then
    begin
      TraceFrame('S>C', pBody);
      Exit(True);
    end;
    Avail:= 0;
    if not PeekNamedPipe(FOut, nil, 0, nil, @Avail, nil) then
    begin
      pError:= 'server exited';
      Exit;
    end;
    if Avail > 0 then
    begin
      Want:= Avail;
      if Want > READ_CHUNK then Want:= READ_CHUNK;
      if FAccLen + Integer(Want) > Length(FAcc) then SetLength(FAcc, (FAccLen + Integer(Want)) * 2);
      Got:= 0;
      if (not ReadFile(FOut, FAcc[FAccLen], Want, Got, nil)) or (Got = 0) then
      begin
        pError:= 'server exited';
        Exit;
      end;
      Inc(FAccLen, Integer(Got));
    end
    else
    begin
      if GetTickCount64 >= pDeadline then
      begin
        pError:= 'timeout';
        Exit;
      end;
      Sleep(POLL_SLEEP_MS);
    end;
  end;
end;

procedure TLspVerifyClient.ReplyToServer(pRequest: TJSONObject);
var
  Method : string;
  Params : TJSONValue;
  ResText: string;
begin
  if not pRequest.TryGetValue<string>('method', Method) then Method:= '';
  Params:= pRequest.GetValue('params');
  ResText:= 'null';
  if Assigned(FOnServerRequest) then
  begin
    ResText:= FOnServerRequest(Method, Params);
    if ResText = '' then ResText:= 'null';
  end;
  try
    Send('{"jsonrpc":"2.0","id":' + pRequest.GetValue('id').ToJSON + ',"result":' + ResText + '}');
  except  // dl:ok try-except-swallowed@16d3 -- REVIEWED 2026-11-23 LSP1-VERB: a reply that cannot be written is kept in LastError; the next read reports the dead pipe as server exited
    on E: ELspClientError do FLastError:= E.Message;   { a dead pipe surfaces as 'server exited' on the next read }
  end;
end;

{ KIND_RESPONSE: the awaited response (pResult set); KIND_FAILED: the awaited error response
  (pError set); KIND_OTHER: anything else, already handled. }
function TLspVerifyClient.ProcessFrame(const pBody: string; pAwaitId: Integer; out pResult: TJSONValue;
  out pError: string): Integer;
var
  Json  : TJSONValue;
  Obj   : TJSONObject;
  IdVal : TJSONValue;
  ErrVal: TJSONValue;
  ResVal: TJSONValue;
  Msg   : string;
begin
  Result:= KIND_OTHER;
  pResult:= nil;
  pError:= '';
  Json:= TJSONObject.ParseJSONValue(pBody);
  if Json = nil then Exit;
  try
    if Json is not TJSONObject then Exit;
    Obj:= TJSONObject(Json);
    IdVal:= Obj.GetValue('id');
    if Obj.GetValue('method') <> nil then
    begin
      if IdVal <> nil then ReplyToServer(Obj);   { a server request; a notification is dropped }
      Exit;
    end;
    if (IdVal = nil) or (IdVal is not TJSONNumber) or (TJSONNumber(IdVal).AsInt <> pAwaitId) then Exit;
    ErrVal:= Obj.GetValue('error');
    if ErrVal <> nil then
    begin
      if (ErrVal is not TJSONObject) or (not TJSONObject(ErrVal).TryGetValue<string>('message', Msg)) then Msg:= ErrVal.ToJSON;
      pError:= Msg;
      Exit(KIND_FAILED);
    end;
    ResVal:= Obj.GetValue('result');
    pResult:= if ResVal = nil then TJSONValue(TJSONNull.Create) else TJSONValue(ResVal.Clone);
    Result:= KIND_RESPONSE;
  finally
    Json.Free;
  end;
end;

function TLspVerifyClient.Request(const pMethod: string; pParams: TJSONValue; pTimeoutMs: Integer;
  out pResult: TJSONValue; out pError: string): Boolean;
var
  Msg     : TJSONObject;
  Id      : Integer;
  Deadline: UInt64;
  Body    : string;
  Kind    : Integer;
begin
  Result:= False;
  pResult:= nil;
  pError:= '';
  Id:= FNextId;
  Inc(FNextId);
  Msg:= TJSONObject.Create;
  try
    Msg.AddPair('jsonrpc', '2.0');
    Msg.AddPair('id', TJSONNumber.Create(Id));
    Msg.AddPair('method', pMethod);
    if pParams <> nil then Msg.AddPair('params', pParams);
    try
      Send(Msg.ToJSON);
    except
      on E: ELspClientError do
      begin
        pError:= E.Message;
        Exit;
      end;
    end;
  finally
    Msg.Free;
  end;
  Deadline:= GetTickCount64 + UInt64(pTimeoutMs);
  while True do
  begin
    if not ReadFrame(Deadline, Body, pError) then Exit;
    Kind:= ProcessFrame(Body, Id, pResult, pError);
    if Kind = KIND_RESPONSE then Exit(True);
    if Kind = KIND_FAILED then Exit;
  end;
end;

procedure TLspVerifyClient.Notify(const pMethod: string; pParams: TJSONValue);
var
  Msg: TJSONObject;
begin
  Msg:= TJSONObject.Create;
  try
    Msg.AddPair('jsonrpc', '2.0');
    Msg.AddPair('method', pMethod);
    if pParams <> nil then Msg.AddPair('params', pParams);
    try
      Send(Msg.ToJSON);
    except  // dl:ok try-except-swallowed@16d3 -- REVIEWED 2026-11-23 LSP1-VERB: a notification that cannot be written is kept in LastError; the next Request reports server exited
      on E: ELspClientError do FLastError:= E.Message;   { a dead pipe is reported by the next Request as 'server exited' }
    end;
  finally
    Msg.Free;
  end;
end;

procedure TLspVerifyClient.Pump(pMs: Integer);
var
  Deadline: UInt64;
  Body    : string;
  Err     : string;
  Res     : TJSONValue;
begin
  Deadline:= GetTickCount64 + UInt64(pMs);
  while GetTickCount64 < Deadline do
  begin
    if ReadFrame(Deadline, Body, Err) then
    begin
      ProcessFrame(Body, 0, Res, Err);
      FreeAndNil(Res);
    end
    else
      Exit;   { timeout = warm-up over; 'server exited' ends it early }
  end;
end;

procedure TLspVerifyClient.Shutdown;
var
  Res: TJSONValue;
  Err: string;
begin
  if FProc = 0 then Exit;
  Res:= nil;
  try
    if Request('shutdown', nil, SHUTDOWN_REQ_MS, Res, Err) then Notify('exit', nil);
    Res.Free;
  except  // dl:ok try-except-swallowed@c04d -- REVIEWED 2026-11-23 LSP1-VERB: Shutdown is best effort and never raises (the destructor calls it); the failure is kept in LastError and the child is terminated
    on E: Exception do FLastError:= E.Message;   { best effort and never raises (the destructor calls it); the child is terminated below when it does not leave }
  end;
  if FIn <> 0 then CloseHandle(FIn);
  FIn:= 0;
  if WaitForSingleObject(FProc, SHUTDOWN_WAIT_MS) <> WAIT_OBJECT_0 then TerminateProcess(FProc, 1);
  CloseHandles;
end;

end.
