unit DRagLint.Core.GhostText;

{ v1.7 B3 -- the ghost-text completion endpoint.

  WHY THIS EXISTS. The IDE logs, repeatedly:

      -32603 http error ... -- http://127.0.0.1:8765/api/generate
      tcp connect error: No connection could be made ... -- os error 10061

  8765 is GhostTextPort's default and /api/generate is Ollama's shape: KAI is
  configured to use drag-lint as a local completion provider, and NOTHING is
  listening. The settings existed; the server never did.

  WHAT IT WILL AND WILL NOT SAY. drag-lint has no language model. It cannot
  generate code and it must not appear to. So this endpoint serves what the
  index can honestly support -- a single identifier or member completion when
  the request resolves to exactly one strong candidate -- and a WELL-FORMED
  EMPTY completion otherwise.

  An empty completion silences the error without inventing text. Returning
  plausible-looking invented code would be the worst outcome available: the
  client cannot tell it from a real suggestion, and it would be wrong. The
  default answer is therefore '', and every path that is unsure returns it.

  WHY A PURE UNIT WITH AN INJECTED PROVIDER. The completion itself needs to
  know which file and cursor the request is about, and llm-ls sends NEITHER --
  it posts a fill-in-the-middle prompt, truncated to the context window, often
  without even the `unit X;` header. Only the OTA can answer that, so the
  plugin hosts the server in-process and supplies an OTA-backed provider.
  Keeping the transport here, with the provider as a callback, is what lets the
  whole thing be driven over real HTTP by a test harness with no IDE in sight --
  which is the only way this was ever going to be verified.

  BINDS TO LOOPBACK ONLY, never INADDR_ANY. A code-completion endpoint that
  answers the network is a code-completion endpoint that answers someone else's
  network. }

interface

uses
    Winapi.Windows
  , Winapi.WinSock2
  , System.Classes
  , System.SysUtils
  , System.SyncObjs   { TCriticalSection -- guards the in-flight client socket,
                        which is a FIELD, so this belongs in the interface uses }
  ;

type
  /// <summary>Supplies the completion text for one request.</summary>
  /// <param name="APrompt">Everything before the cursor, as the client sent it.
  /// Usually truncated; never assume it starts at the top of the file.</param>
  /// <param name="ASuffix">Everything after the cursor, when the client sends
  /// it (fill-in-the-middle). Often empty.</param>
  /// <returns>The completion text, or '' when there is no honest answer.
  /// Returning '' is the DEFAULT and the safe case -- see the unit header on
  /// why an empty completion beats an invented one.</returns>
  TGhostCompletionFunc = reference to function(const APrompt, ASuffix: string): string;

  /// <summary>A minimal loopback HTTP server serving the two request shapes a
  /// local-model client may use: Ollama's POST /api/generate and OpenAI's
  /// POST /v1/completions.</summary>
  /// <remarks>Both are served because the CLIENT's configuration decides which
  /// is called, and the observed IDE error names the Ollama one. Start returns
  /// False rather than raising when the port cannot be bound: a completion
  /// provider that cannot start must not take the IDE down with it.</remarks>
  /// <summary>Optional teardown/diagnostic sink. The host assigns it; this unit
  /// has no log of its own and must not acquire one.</summary>
  TGhostTraceProc = reference to procedure(const AMsg: string);

  TGhostTextServer = class
    private
      FPort    : Integer             ;
      FProvider: TGhostCompletionFunc;
      FListen  : TSocket             ;
      FThread  : TThread             ;
      FStopping: Integer             ;
      { The connection currently being SERVED, and a lock for it. Stop closes it
        so a blocked recv/send returns at once instead of waiting out its
        timeout -- see the note on Stop. }
      FClient  : TSocket             ;
      FClientCS: TCriticalSection    ;
      procedure AcceptLoop;
      procedure ServeOne(ASock: TSocket);
    public
      /// <param name="APort">TCP port on 127.0.0.1. 8765 matches the KAI default.</param>
      /// <param name="AProvider">Completion source; nil means every request is
      /// answered with an empty completion, which is a valid configuration.</param>
      constructor Create(APort: Integer; const AProvider: TGhostCompletionFunc);
      destructor Destroy; override;
      /// <summary>Binds and starts serving. False when the port is taken or
      /// WinSock is unavailable; the caller carries on regardless.</summary>
      function  Start: Boolean;
      /// <summary>Stops serving and waits for the accept thread.</summary>
      procedure Stop;
      /// <summary>The whole start decision in one place: returns a RUNNING
      /// server, or nil when AEnabled is false or the port could not be
      /// bound.</summary>
      /// <remarks>The gate lives here rather than in the caller so that "off
      /// means off" is a property of a unit that can be driven by a test
      /// harness. An unchecked box must leave NOTHING listening -- no socket,
      /// no thread -- and that is only credible if something checks it.</remarks>
      class function StartWhen(AEnabled: Boolean; APort: Integer;
                               const AProvider: TGhostCompletionFunc): TGhostTextServer; static;
      property Port: Integer read FPort;
  end;

var
  /// <summary>Set by the host to receive teardown trace lines. Never called
  /// unless assigned, and every call is guarded -- a diagnostic must not be
  /// able to break the thing it is diagnosing.</summary>
  GGhostTextTrace: TGhostTraceProc = nil;

implementation

uses
    System.JSON   { System.SyncObjs moved to the INTERFACE uses -- the critical
                    section guarding the in-flight client is a field. }
  ;

const
  { A completion request is small. Anything larger is not one, and reading it
    would only tie up the single accept loop. }
  MAX_REQUEST_BYTES = 512 * 1024;
  RECV_CHUNK        = 8 * 1024;

  { The IDE waits on this call, so a slow client must not hold completion
    hostage. Loopback with a local client: generous already. }
  RECV_TIMEOUT_MS = 5000;

  { How long Stop waits for the accept thread before abandoning it. Long enough
    that a request in flight finishes, short enough that no human calls it a
    hang. }
  STOP_JOIN_TIMEOUT_MS = 3000;

type
  TAcceptThread = class(TThread)
    private
      FOwner: TGhostTextServer;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TGhostTextServer);
  end;

constructor TAcceptThread.Create(AOwner: TGhostTextServer);
begin
  FOwner:= AOwner;
  inherited Create(False);
end;

procedure TAcceptThread.Execute;
begin
  FOwner.AcceptLoop;
end;

{ ---------------------------------------------------------------------------
  Small helpers
  --------------------------------------------------------------------------- }

procedure GT(const AMsg: string);
begin
  if Assigned(GGhostTextTrace) then
    try GGhostTextTrace(AMsg); except end;
end;

function SendAll(ASock: TSocket; const AData: RawByteString): Boolean;
var
  Sent  : Integer;
  Offset: Integer;
  Total : Integer;
begin
  Total := Length(AData);
  Offset:= 0;
  while Offset < Total do
  begin
    Sent:= Winapi.WinSock2.send(ASock, AData[Offset + 1], Total - Offset, 0);
    if Sent <= 0 then Exit(False);
    Inc(Offset, Sent);
  end;
  Result:= True;
end;

{ Builds a complete HTTP/1.1 response. Connection: close throughout -- these are
  one-shot completion calls and keep-alive would only add a state machine to
  something that does not need one. }
function HttpResponse(const AStatus, ABody: string): RawByteString;
var
  Payload: RawByteString;
begin
  Payload:= UTF8Encode(ABody);
  { UTF8Encode, not AnsiString: the header values are ASCII by construction, and
    an AnsiString cast would silently drop anything outside the active code page
    if that ever stopped being true. }
  Result :=
    RawByteString('HTTP/1.1 ') + UTF8Encode(AStatus) + RawByteString(#13#10) +
    RawByteString('Content-Type: application/json; charset=utf-8'#13#10) +
    RawByteString('Content-Length: ') + UTF8Encode(IntToStr(Length(Payload))) + RawByteString(#13#10) +
    RawByteString('Cache-Control: no-store'#13#10) +
    RawByteString('Connection: close'#13#10#13#10) +
    Payload;
end;

{ JSON string escaping via TJSONString, so the completion text cannot break the
  response no matter what it contains. }
function JsonQuote(const AText: string): string;
var
  S: TJSONString;
begin
  S:= TJSONString.Create(AText);
  try
    Result:= S.ToJSON;
  finally
    S.Free;
  end;
end;

{ Reads one named string member, or '' when absent or not a string. Never
  raises: a malformed body is answered with an empty completion, like every
  other uncertain case. }
function JsonStringMember(const ABody, AName: string): string;
var
  V  : TJSONValue;
  Obj: TJSONObject;
  Mem: TJSONValue;
begin
  Result:= '';
  if Trim(ABody) = '' then Exit;
  V:= nil;
  try
    V:= TJSONObject.ParseJSONValue(ABody);
  except  // dl:ok try-except-swallowed@f708 -- swallowing IS the contract: an unreadable body means no prompt, which means an empty completion
    on E: Exception do V:= nil;   { unreadable body -> no prompt -> empty completion }
  end;
  if V = nil then Exit;
  try
    if not (V is TJSONObject) then Exit;
    Obj:= TJSONObject(V);
    Mem:= Obj.GetValue(AName);
    if (Mem <> nil) and (Mem is TJSONString) then Result:= TJSONString(Mem).Value;
  finally
    V.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  TGhostTextServer
  --------------------------------------------------------------------------- }

constructor TGhostTextServer.Create(APort: Integer; const AProvider: TGhostCompletionFunc);
begin
  inherited Create;
  FPort    := APort;
  FProvider:= AProvider;
  FListen  := INVALID_SOCKET;
  FStopping:= 0;
  FClient  := INVALID_SOCKET;
  FClientCS:= TCriticalSection.Create;
end;

destructor TGhostTextServer.Destroy;
begin
  Stop;
  FreeAndNil(FClientCS);
  inherited;
end;

function TGhostTextServer.Start: Boolean;
var
  WSA  : TWSAData;
  Addr : TSockAddrIn;
  Reuse: Integer;
begin
  Result:= False;
  if FListen <> INVALID_SOCKET then Exit(True);

  if WSAStartup($0202, WSA) <> 0 then Exit;

  FListen:= socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FListen = INVALID_SOCKET then Exit;

  { Deliberately NOT SO_REUSEADDR for the address: on Windows that would let a
    second instance steal a port already in use, and two servers answering the
    same completions is worse than one refusing to start. }
  Reuse:= 0;
  setsockopt(FListen, SOL_SOCKET, SO_REUSEADDR, @Reuse, SizeOf(Reuse));

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family     := AF_INET;
  Addr.sin_port       := htons(Word(FPort));
  { LOOPBACK ONLY. INADDR_ANY here would publish the IDE's completion endpoint
    to every network the machine is on. }
  Addr.sin_addr.S_addr:= htonl(INADDR_LOOPBACK);

  if bind(FListen, TSockAddr(Addr), SizeOf(Addr)) = SOCKET_ERROR then
  begin
    closesocket(FListen);
    FListen:= INVALID_SOCKET;
    Exit;
  end;

  if listen(FListen, 8) = SOCKET_ERROR then
  begin
    closesocket(FListen);
    FListen:= INVALID_SOCKET;
    Exit;
  end;

  FThread:= TAcceptThread.Create(Self);
  Result := True;
end;

procedure TGhostTextServer.Stop;
var
  Sock: TSocket;
begin
  GT('Stop: ENTER');
  if FListen = INVALID_SOCKET then begin GT('Stop: already stopped'); Exit; end;
  TInterlocked.Exchange(FStopping, 1);

  { Closing the listening socket is what unblocks accept. There is no portable
    way to interrupt it otherwise, and a Stop that waits for the next
    connection is a Stop that hangs the IDE on shutdown. }
  Sock   := FListen;
  FListen:= INVALID_SOCKET;
  closesocket(Sock);

  { CLOSE THE CONNECTION BEING SERVED, not just the listener.

    Closing the listener only unblocks accept(). If the thread is inside
    ServeOne it is in recv or send, and those are bounded by SO_RCVTIMEO /
    SO_SNDTIMEO at 5s -- LONGER than the 3s join below, so the join always lost
    that race and reported a timeout for a thread that was working normally.
    Observed exactly once the trace existed: teardown reached Stop, the socket
    closed, and 3s later the thread was still alive.

    Closing the client makes the blocked call return immediately. }
  FClientCS.Enter;
  try
    if FClient <> INVALID_SOCKET then
    begin
      GT('Stop: closing the in-flight client connection');
      closesocket(FClient);
      FClient:= INVALID_SOCKET;
    end;
  finally
    FClientCS.Leave;
  end;

  GT('Stop: listening socket closed; joining accept thread');

  if Assigned(FThread) then
  begin
    { BOUNDED JOIN (2026-08-26). This used to be an unbounded FThread.WaitFor,
      and bds.exe twice failed to exit with teardown parked exactly here.

      The trade is deliberate and worth stating. Abandoning a live thread whose
      code lives in a BPL that is about to unload is a real hazard -- but on IDE
      SHUTDOWN the process dies moments later, whereas an unbounded wait hangs
      the IDE forever and the user must kill it. A bounded wait converts an
      indefinite hang into a bounded one, and says so loudly either way.

      If this line ever reports a timeout, the accept thread is stuck in
      ServeOne, and the trace above says which stage. Do not raise the timeout
      to make it quiet. }
    if FThread.Handle <> 0 then
    begin
      if WaitForSingleObject(FThread.Handle, STOP_JOIN_TIMEOUT_MS) = WAIT_OBJECT_0 then
      begin
        GT('Stop: accept thread joined cleanly');
        FreeAndNil(FThread);
      end
      else
      begin
        { Deliberately NOT freed: TThread.Destroy waits on the thread, which is
          the very wait that just timed out. Leaking the object is the lesser
          harm and the process is exiting. }
        GT(Format('Stop: TIMEOUT -- accept thread did not exit within %d ms; ' +
                  'abandoning it rather than hanging the IDE', [STOP_JOIN_TIMEOUT_MS]));
        FThread:= nil;
      end;
    end
    else FreeAndNil(FThread);
  end;
  WSACleanup;
  GT('Stop: DONE');
end;

class function TGhostTextServer.StartWhen(AEnabled: Boolean; APort: Integer;
  const AProvider: TGhostCompletionFunc): TGhostTextServer;
begin
  Result:= nil;
  if not AEnabled then Exit;   { off means off: nothing constructed, nothing bound }
  Result:= TGhostTextServer.Create(APort, AProvider);
  if not Result.Start then FreeAndNil(Result);
end;

procedure TGhostTextServer.AcceptLoop;
var
  Client: TSocket;
begin
  while TInterlocked.CompareExchange(FStopping, 0, 0) = 0 do
  begin
    Client:= accept(FListen, nil, nil);
    if Client = INVALID_SOCKET then Break;   { closed by Stop, or a real error }
    { PUBLISH the connection being served, so Stop can reach in and close it.
      Without this the only way out of a blocked recv/send is its own timeout,
      and Stop's join gave up first. }
    FClientCS.Enter;
    try FClient:= Client; finally FClientCS.Leave; end;
    try
      ServeOne(Client);
    except
      { A failure serving ONE request must never end the loop -- the next
        keystroke deserves an answer even if this one broke. }
    end;
    FClientCS.Enter;
    try
      { Only close it here if Stop has not already done so -- a double close on
        a handle the OS may have reused is a real hazard, not a tidy-up. }
      if FClient <> INVALID_SOCKET then
      begin
        closesocket(FClient);
        FClient:= INVALID_SOCKET;
      end;
    finally
      FClientCS.Leave;
    end;
  end;
end;

procedure TGhostTextServer.ServeOne(ASock: TSocket);
var
  Buf       : array[0..RECV_CHUNK - 1] of AnsiChar;
  Got       : Integer;
  Raw       : RawByteString;
  HeaderEnd : Integer;
  Head      : string;
  Body      : string;
  Line1     : string;
  SpacePos  : Integer;
  Path      : string;
  Method    : string;
  ContentLen: Integer;
  LenPos    : Integer;
  LineEnd   : Integer;
  Prompt    : string;
  Suffix    : string;
  Text      : string;
  Timeout   : Integer;
begin
  Timeout:= RECV_TIMEOUT_MS;
  setsockopt(ASock, SOL_SOCKET, SO_RCVTIMEO, @Timeout, SizeOf(Timeout));
  { SEND MUST BE BOUNDED TOO (2026-08-26). Only the receive was, so a client
    that opened a connection and then stopped READING parked this thread in
    send() forever -- and Stop joins this thread, so the IDE could not exit.
    An unanswered completion is a non-event; an IDE that will not close is not. }
  setsockopt(ASock, SOL_SOCKET, SO_SNDTIMEO, @Timeout, SizeOf(Timeout));

  Raw      := '';
  HeaderEnd:= 0;
  while Length(Raw) < MAX_REQUEST_BYTES do
  begin
    Got:= recv(ASock, Buf, SizeOf(Buf), 0);
    if Got <= 0 then Break;
    SetLength(Raw, Length(Raw) + Got);
    Move(Buf[0], Raw[Length(Raw) - Got + 1], Got);
    HeaderEnd:= Pos(RawByteString(#13#10#13#10), Raw);
    if HeaderEnd > 0 then
    begin
      Head:= string(Copy(Raw, 1, HeaderEnd - 1));
      { Content-Length decides whether the body has fully arrived. Absent or
        unreadable means "no body", which is answered like any other request
        we cannot interpret: with an empty completion. }
      ContentLen:= 0;
      LenPos:= Pos('content-length:', LowerCase(Head));
      if LenPos > 0 then
      begin
        LineEnd:= Pos(#13#10, Copy(Head, LenPos, MaxInt));
        if LineEnd <= 0 then LineEnd:= Length(Head) - LenPos + 2;
        ContentLen:= StrToIntDef(Trim(Copy(Head, LenPos + 15, LineEnd - 16)), 0);
      end;
      if Length(Raw) >= HeaderEnd + 3 + ContentLen then Break;
    end;
  end;

  if HeaderEnd <= 0 then
  begin
    SendAll(ASock, HttpResponse('400 Bad Request', '{"error":"malformed request"}'));
    Exit;
  end;

  Head:= string(Copy(Raw, 1, HeaderEnd - 1));
  Body:= UTF8ToString(Copy(Raw, HeaderEnd + 4, MaxInt));

  LineEnd:= Pos(#13#10, Head);
  if LineEnd > 0 then Line1:= Copy(Head, 1, LineEnd - 1) else Line1:= Head;
  SpacePos:= Pos(' ', Line1);
  if SpacePos <= 0 then
  begin
    SendAll(ASock, HttpResponse('400 Bad Request', '{"error":"malformed request line"}'));
    Exit;
  end;
  Method:= Copy(Line1, 1, SpacePos - 1);
  Path  := Trim(Copy(Line1, SpacePos + 1, MaxInt));
  SpacePos:= Pos(' ', Path);
  if SpacePos > 0 then Path:= Copy(Path, 1, SpacePos - 1);
  LenPos:= Pos('?', Path);
  if LenPos > 0 then Path:= Copy(Path, 1, LenPos - 1);

  if not SameText(Method, 'POST') then
  begin
    SendAll(ASock, HttpResponse('405 Method Not Allowed', '{"error":"POST only"}'));
    Exit;
  end;

  Prompt:= JsonStringMember(Body, 'prompt');
  Suffix:= JsonStringMember(Body, 'suffix');

  { THE DEFAULT IS EMPTY. A provider that is absent, that raises, or that has
    nothing confident to say all land here, and all produce a valid completion
    carrying no text. }
  Text:= '';
  if Assigned(FProvider) then
    try
      Text:= FProvider(Prompt, Suffix);
    except  // dl:ok try-except-swallowed@cc4a -- FAIL OPEN: a provider that raises must yield an empty completion, never propagate into the IDE
      on E: Exception do Text:= '';   { a broken provider answers nothing, not garbage }
    end;

  if SameText(Path, '/api/generate') then
    SendAll(ASock, HttpResponse('200 OK',
      '{"model":"drag-lint","response":' + JsonQuote(Text) + ',"done":true}'))
  else if SameText(Path, '/v1/completions') then
    SendAll(ASock, HttpResponse('200 OK',
      '{"object":"text_completion","model":"drag-lint","choices":[{"index":0,"text":' +
      JsonQuote(Text) + ',"finish_reason":"stop"}]}'))
  else
    SendAll(ASock, HttpResponse('404 Not Found', '{"error":"no such endpoint"}'));
end;

end.
