program LspNonBlockingTests;
{$APPTYPE CONSOLE}
{ Pins "whatever gets stuck in DL must not make the IDE stuck" (owner,
  2026-10-29; docs\INBOX-ide-hang-on-slow-engine.md section 1).

  W  the write queue: Enqueue NEVER blocks on a pipe nobody reads (bounded,
     drops instead of waiting), coalesces superseded frames, and Destroy returns
     while the writer is blocked inside WriteFile.
  C  the LSP client over two anonymous pipes with a scripted fake engine:
     RequestAsync answers on the main thread; a cancelled (superseded) request's
     callback never runs -- also when its answer is already queued -- and the
     engine is sent $/cancelRequest; timeouts fire and cancel; IsBusy / IsStuck
     see an engine that keeps a request unanswered; Notify does not block when
     the engine stops reading stdin, and Stop then returns.
  G  the hover show-gate geometry (pure): same window, X within the token span,
     Y within +-0.6 line heights of the original line's centre.
  S  DLIdentSpanAt (pure).

  Every "does not block" assertion runs the call on a worker thread and waits
  with a deadline, so a regression FAILS here instead of hanging the battery.
  The process ends with ExitProcess, which does not wait for a thread a
  regression left blocked. }
uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  System.Types,
  Winapi.Windows,
  DragLint.Plugin.LspWriteQueue in '..\src\delphi-plugin\DragLint.Plugin.LspWriteQueue.pas',
  DragLint.Plugin.LspClient in '..\src\delphi-plugin\DragLint.Plugin.LspClient.pas',
  DragLint.Plugin.HoverGate in '..\src\delphi-plugin\DragLint.Plugin.HoverGate.pas';

const
  BIG_FRAME   = 64 * 1024;
  PIPE_BUFFER = 4096;
  BLOCK_LIMIT_MS = 500;   { "never blocks" = returns well inside this }
  JOIN_LIMIT_MS  = 3000;  { a worker that is not back by now is blocked }

var
  GPass, GFail: Integer;
  { Set when the write queue BLOCKED (W1). Every later pipe test would then
    hang the harness on its first write, so they are reported, not run. }
  GQueueBlocked: Boolean;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName, (if ADetail <> '' then '  -- ' + ADetail else '')); end;
end;

function Frame(ASize: Integer): TBytes;
begin
  SetLength(Result, ASize);
  FillChar(Result[0], ASize, Ord('x'));
end;

{ Runs AProc on a worker; True when it returned within ALimitMs. A worker that
  did not is abandoned (it is blocked -- that IS the failure being reported). }
function RunsWithin(ALimitMs: Cardinal; const AProc: TProc; out AElapsedMs: UInt64): Boolean;
var
  T : TThread;
  T0: UInt64 ;
begin
  T0:= GetTickCount64;
  T:= TThread.CreateAnonymousThread(AProc);
  T.FreeOnTerminate:= False;
  T.Start;
  Result:= WaitForSingleObject(T.Handle, ALimitMs) = WAIT_OBJECT_0;
  AElapsedMs:= GetTickCount64 - T0;
  if Result then T.Free;
end;

procedure Pump(AMs: Cardinal);
var
  T0: UInt64;
begin
  T0:= GetTickCount64;
  repeat
    CheckSynchronize(10);
  until GetTickCount64 - T0 >= AMs;
end;

{ ---- W: write queue ---- }

procedure TestQueueNeverBlocks;
var
  R, W   : THandle;
  Q      : TDLLspWriteQueue;
  Ms     : UInt64;
  Ok     : Boolean;
  Queued : Integer;
begin
  Win32Check(CreatePipe(R, W, nil, PIPE_BUFFER));
  Q:= TDLLspWriteQueue.Create(W, 8, nil);
  Queued:= 0;
  { 50 x 64 KB into a 4 KB pipe NOBODY reads: the old blocking write froze on
    the first frame. }
  Ok:= RunsWithin(JOIN_LIMIT_MS,
    procedure
    begin
      for var I:= 1 to 50 do
        if Q.Enqueue(Frame(BIG_FRAME)) then Inc(Queued);
    end, Ms);
  Check('W1 50 Enqueue calls into an unread pipe return (no block)', Ok and (Ms < BLOCK_LIMIT_MS), Format('ok=%s ms=%d', [BoolToStr(Ok, True), Ms]));
  if not Ok then
  begin
    GQueueBlocked:= True;
    Exit; { blocked: nothing below is meaningful, and Q is in use }
  end;
  Check('W2 the queue is bounded: frames beyond capacity are dropped, not waited for', (Q.Dropped > 0) and (Q.PendingCount <= 8),
    Format('dropped=%d pending=%d queued=%d', [Q.Dropped, Q.PendingCount, Queued]));
  Sleep(300);
  Check('W3 WriteStalledMs reports the writer blocked in the full pipe', Q.WriteStalledMs >= 200, Format('stalled=%d', [Q.WriteStalledMs]));
  Ok:= RunsWithin(JOIN_LIMIT_MS, procedure begin Q.Free; end, Ms);
  Check('W4 Destroy returns while the writer is blocked in WriteFile', Ok, Format('ms=%d', [Ms]));
  CloseHandle(R);
  CloseHandle(W);
end;

procedure TestQueueCoalesces;
var
  R, W: THandle;
  Q   : TDLLspWriteQueue;
  Ms  : UInt64;
begin
  Win32Check(CreatePipe(R, W, nil, PIPE_BUFFER));
  Q:= TDLLspWriteQueue.Create(W, 16, nil);
  Q.Enqueue(Frame(BIG_FRAME));      { the writer takes this one and blocks on it }
  Sleep(200);
  Q.Enqueue(Frame(10), 'didChange|file:///a.pas');
  Q.Enqueue(Frame(20), 'didChange|file:///a.pas');
  Q.Enqueue(Frame(30), 'didChange|file:///a.pas');
  Check('W5 three didChange for one document coalesce into one waiting frame', Q.PendingCount = 1, Format('pending=%d', [Q.PendingCount]));
  Q.Enqueue(Frame(10), 'didChange|file:///b.pas');
  Q.Enqueue(Frame(10));
  Check('W6 a different key and an unkeyed frame queue separately', Q.PendingCount = 3, Format('pending=%d', [Q.PendingCount]));
  RunsWithin(JOIN_LIMIT_MS, procedure begin Q.Free; end, Ms);
  CloseHandle(R);
  CloseHandle(W);
end;

{ ---- C: client over pipes with a fake engine ---- }

type
  TFakeEngine = class(TThread)
    private
      FIn       : THandle;           { reads what the client writes }
      FOut      : THandle;           { writes what the client reads }
      FLock     : TCriticalSection;
      FSeen     : TStringList;       { "method|id|cancelId" per frame }
      FReadGate : TEvent;            { reset = stop reading stdin }
      FDie      : Boolean;
      function ReadFrame(out AJson: string): Boolean;
      procedure Reply(AId: Integer; const AMethod: string);
    protected
      procedure Execute; override;
    public
      constructor Create(AIn, AOut: THandle);
      destructor Destroy; override;
      function Seen: string;
      { Ends the engine thread: the 'engine died' half of the teardown test. }
      procedure Kill;
      property ReadGate: TEvent read FReadGate;
  end;

constructor TFakeEngine.Create(AIn, AOut: THandle);
begin
  FIn:= AIn;
  FOut:= AOut;
  FLock:= TCriticalSection.Create;
  FSeen:= TStringList.Create;
  FReadGate:= TEvent.Create(nil, True, True, '');
  FreeOnTerminate:= False;
  inherited Create(False);
end;

destructor TFakeEngine.Destroy;
begin
  inherited;
  FReadGate.Free;
  FSeen.Free;
  FLock.Free;
end;

procedure TFakeEngine.Kill;
begin
  FDie:= True;
  FReadGate.SetEvent;
  repeat
    CancelSynchronousIo(Handle);   { a read already blocked returns }
  until WaitForSingleObject(Handle, 20) = WAIT_OBJECT_0;
end;

function TFakeEngine.Seen: string;
begin
  FLock.Enter;
  try
    Result:= FSeen.CommaText;
  finally
    FLock.Leave;
  end;
end;

function TFakeEngine.ReadFrame(out AJson: string): Boolean;
var
  Ch : Byte;
  N  : DWORD;
  Hdr: AnsiString;
  Len: Integer;
  B  : TBytes;
  Got: Integer;
begin
  Result:= False;
  Hdr:= '';
  repeat
    if not ReadFile(FIn, Ch, 1, N, nil) or (N = 0) then Exit;
    Hdr:= Hdr + AnsiChar(Ch);
  until (Length(Hdr) >= 4) and (Copy(Hdr, Length(Hdr) - 3, 4) = #13#10#13#10);
  Len:= StrToIntDef(Trim(Copy(string(Hdr), Pos(':', string(Hdr)) + 1, Pos(#13, string(Hdr)) - Pos(':', string(Hdr)) - 1)), 0);
  SetLength(B, Len);
  Got:= 0;
  while Got < Len do
  begin
    if not ReadFile(FIn, B[Got], Len - Got, N, nil) or (N = 0) then Exit;
    Inc(Got, N);
  end;
  AJson:= TEncoding.UTF8.GetString(B);
  Result:= True;
end;

procedure TFakeEngine.Reply(AId: Integer; const AMethod: string);
var
  Body: TBytes;
  All : TBytes;
  N   : DWORD;
begin
  Body:= TEncoding.UTF8.GetBytes(Format('{"jsonrpc":"2.0","id":%d,"result":{"echo":"%s"}}', [AId, AMethod]));
  All:= TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(Body)])) + Body;
  WriteFile(FOut, All[0], Length(All), N, nil);
end;

procedure TFakeEngine.Execute;
var
  Js : string;
  V  : TJSONValue;
  M  : string;
  Id : Integer;
  CId: Integer;
begin
  try
    while True do
    begin
      FReadGate.WaitFor(INFINITE);
      if FDie then Exit;
      if not ReadFrame(Js) then Exit;
      V:= TJSONObject.ParseJSONValue(Js);
      try
        if not (V is TJSONObject) then Continue;
        M := TJSONObject(V).GetValue<string>('method', '');
        Id:= TJSONObject(V).GetValue<Integer>('id', 0);
        CId:= 0;
        if M = '$/cancelRequest' then CId:= TJSONObject(V).GetValue<Integer>('params.id', 0);
        FLock.Enter;
        try
          FSeen.Add(Format('%s|%d|%d', [M, Id, CId]));
        finally
          FLock.Leave;
        end;
        { 'slow' is never answered: the engine is "still working on it". }
        if (Id > 0) and (M <> 'slow') then Reply(Id, M);
      finally
        V.Free;
      end;
    end;
  except
    on E: Exception do Writeln('fake engine: ', E.Message);
  end;
end;

type
  TRig = record
    Client: TDragLintLspClient;
    Engine: TFakeEngine;
    InR, InW, OutR, OutW: THandle;
  end;

function OpenRig: TRig;
begin
  Win32Check(CreatePipe(Result.InR , Result.InW , nil, PIPE_BUFFER));
  Win32Check(CreatePipe(Result.OutR, Result.OutW, nil, PIPE_BUFFER));
  Result.Engine:= TFakeEngine.Create(Result.InR, Result.OutW);
  Result.Client:= TDragLintLspClient.Create;
  Result.Client.AttachPipes(Result.InW, Result.OutR);
end;

procedure CloseRig(var ARig: TRig);
var
  Ms: UInt64;
  C : TDragLintLspClient;
begin
  ARig.Engine.ReadGate.SetEvent;
  CloseHandle(ARig.OutW);             { client reader sees EOF }
  C:= ARig.Client;
  { Stop closes InW / OutR; the engine then reads EOF and exits. }
  if not RunsWithin(JOIN_LIMIT_MS, procedure begin C.Free; end, Ms) then
    Check('C-teardown client Free returned', False, Format('ms=%d', [Ms]));
  ARig.Engine.WaitFor;
  ARig.Engine.Free;
  CloseHandle(ARig.InR);
end;

procedure TestAsyncReply;
var
  Rig   : TRig;
  Got   : Integer;
  GotSt : TDLLspReplyStatus;
  Echo  : string;
  Id    : Integer;
  Thread: TThreadID;
begin
  Rig:= OpenRig;
  try
    Got:= 0;
    Thread:= 0;
    Id:= Rig.Client.RequestAsync('draglint/hoverBundle', nil, 5000,
      procedure(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue)
      begin
        Got  := AId;
        GotSt:= AStatus;
        Thread:= GetCurrentThreadId;
        if AReply <> nil then Echo:= AReply.GetValue<string>('result.echo', '');
      end);
    Check('C1 RequestAsync returns an id at once', Id > 0);
    Pump(1000);
    Check('C2 the answer is delivered to the callback with its id and lrsResult', (Got = Id) and (GotSt = lrsResult) and (Echo = 'draglint/hoverBundle'),
      Format('got=%d echo=%s', [Got, Echo]));
    Check('C3 ... on the main thread', Thread = MainThreadID);
  finally
    CloseRig(Rig);
  end;
end;

procedure TestSupersededDropped;
var
  Rig       : TRig;
  RanA, RanB: Boolean;
  IdA, IdB  : Integer;
  IdC       : Integer;
  RanC      : Boolean;
begin
  Rig:= OpenRig;
  try
    RanA:= False; RanB:= False; RanC:= False;
    IdA:= Rig.Client.RequestAsync('draglint/hoverBundle', nil, 5000,
      procedure(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue) begin RanA:= True; end);
    { The mouse moved on: hover A is superseded by hover B. }
    Rig.Client.CancelRequest(IdA);
    IdB:= Rig.Client.RequestAsync('draglint/hoverBundle', nil, 5000,
      procedure(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue) begin RanB:= True; end);
    Pump(1000);
    Check('C4 a superseded (cancelled) hover never reaches its callback, though the engine answered it', not RanA);
    Check('C5 the request that superseded it does', RanB);
    Check('C6 the engine was sent $/cancelRequest for the superseded id', Pos(Format('$/cancelRequest|0|%d', [IdA]), Rig.Engine.Seen) > 0, Rig.Engine.Seen);

    { Cancelled AFTER its answer arrived but BEFORE the main thread ran it. }
    IdC:= Rig.Client.RequestAsync('draglint/hoverBundle', nil, 5000,
      procedure(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue) begin RanC:= True; end);
    var T0: UInt64:= GetTickCount64;
    while (Rig.Client.OutstandingCount > 0) and (GetTickCount64 - T0 < JOIN_LIMIT_MS) do Sleep(10); { answer dispatched, not yet run }
    Rig.Client.CancelRequest(IdC);
    Pump(500);
    Check('C7 a request cancelled while its answer is already queued is still dropped', (IdC > 0) and not RanC);
  finally
    CloseRig(Rig);
  end;
end;

procedure TestTimeoutBusyStuck;
var
  Rig  : TRig;
  St   : TDLLspReplyStatus;
  Ran  : Boolean;
  Id   : Integer;
begin
  Rig:= OpenRig;
  try
    Rig.Client.BusyAfterMs := 200;
    Rig.Client.StuckAfterMs:= 600;
    Check('C8 an idle client is neither busy nor stuck', (not Rig.Client.IsBusy) and (not Rig.Client.IsStuck));
    Ran:= False;
    Id:= Rig.Client.RequestAsync('slow', nil, 300,
      procedure(AId: Integer; AStatus: TDLLspReplyStatus; AReply: TJSONValue) begin Ran:= True; St:= AStatus; end);
    Pump(800);
    Check('C9 an unanswered request times out to lrsTimeout', Ran and (St = lrsTimeout));
    Check('C10 ... and the engine is sent $/cancelRequest for it', Pos(Format('$/cancelRequest|0|%d', [Id]), Rig.Engine.Seen) > 0, Rig.Engine.Seen);
    Check('C11 IsBusy while the engine still owes that answer', Rig.Client.IsBusy);
    Check('C12 IsStuck once the engine has been silent past StuckAfterMs', Rig.Client.IsStuck);
  finally
    CloseRig(Rig);
  end;
end;

procedure TestNotifyWhenEngineStopsReading;
var
  Rig: TRig;
  Ms : UInt64;
  Ok : Boolean;
  C  : TDragLintLspClient;
  Big: TJSONObject;
begin
  Rig:= OpenRig;
  try
    Rig.Client.BusyAfterMs:= 200;
    Rig.Engine.ReadGate.ResetEvent;   { the engine stops reading stdin }
    Sleep(50);
    C:= Rig.Client;
    Big:= TJSONObject.Create;
    try
      Big.AddPair('text', StringOfChar('x', BIG_FRAME));
      { The didChange path: a full buffer per call, the shape that used to freeze
        the IDE once the pipe filled. Run on the MAIN thread, like the IDE. }
      var B: TJSONObject:= Big;
      Ok:= RunsWithin(JOIN_LIMIT_MS,
        procedure
        begin
          for var I:= 1 to 40 do C.Notify('textDocument/didChange', B, 'didChange|x');
          for var I:= 1 to 40 do C.Notify('textDocument/didSave', B);
        end, Ms);
      Check('C13 80 x 64 KB notifications return while the engine reads nothing', Ok and (Ms < BLOCK_LIMIT_MS), Format('ok=%s ms=%d', [BoolToStr(Ok, True), Ms]));
    finally
      Big.Free;
    end;
    Sleep(400);
    Check('C14 IsBusy sees the stdin writer stalled', Rig.Client.IsBusy);
    Ok:= RunsWithin(JOIN_LIMIT_MS, procedure begin C.Stop; end, Ms);
    Check('C15 Stop returns while the writer is blocked on the full pipe', Ok, Format('ms=%d', [Ms]));
  finally
    CloseRig(Rig);
  end;
end;

{ ---- T: teardown is bounded (coordinator addition, 2026-10-29) ----
  After an engine death RAD Studio took minutes to exit. Free must finish
  inside the 2 s stop budget (+ slack) whether the engine is deaf (alive, not
  reading stdin, never writing stdout: writer AND reader both blocked) or dead
  (both pipe ends gone). }

procedure TestTeardownBudget;
const
  TEARDOWN_LIMIT_MS = 2500;
var
  Rig : TRig;
  C   : TDragLintLspClient;
  Ms  : UInt64;
  Ok  : Boolean;
  Big : TJSONObject;
begin
  { Deaf engine: reads nothing, answers nothing, keeps both pipes open. }
  Rig:= OpenRig;
  Rig.Engine.ReadGate.ResetEvent;
  Sleep(50);
  C:= Rig.Client;
  Big:= TJSONObject.Create;
  try
    Big.AddPair('text', StringOfChar('x', BIG_FRAME));
    C.Notify('textDocument/didChange', Big);
    C.RequestAsync('slow', nil, 60000, nil);
  finally
    Big.Free;
  end;
  Sleep(200);
  Ok:= RunsWithin(JOIN_LIMIT_MS + JOIN_LIMIT_MS, procedure begin C.Free; end, Ms);
  Check('T1 Free of a client whose engine is deaf returns inside the stop budget', Ok and (Ms < TEARDOWN_LIMIT_MS), Format('ms=%d', [Ms]));
  Rig.Engine.ReadGate.SetEvent;
  CloseHandle(Rig.OutW);
  Rig.Engine.WaitFor;
  Rig.Engine.Free;
  CloseHandle(Rig.InR);

  { Dead engine: both of its pipe ends are gone, the next write fails. }
  Rig:= OpenRig;
  C:= Rig.Client;
  { The engine thread ends (its blocked read is cancelled), then both of its
    pipe ends close: reader sees EOF -- the ERROR_BROKEN_PIPE 109 of the
    report -- and the writer's next WriteFile fails. }
  Rig.Engine.Kill;
  CloseHandle(Rig.OutW);
  CloseHandle(Rig.InR);
  C.Notify('textDocument/didSave', nil);
  Sleep(200);
  Ok:= RunsWithin(JOIN_LIMIT_MS + JOIN_LIMIT_MS, procedure begin C.Free; end, Ms);
  Check('T2 Free of a client whose engine is dead returns inside the stop budget', Ok and (Ms < TEARDOWN_LIMIT_MS), Format('ms=%d', [Ms]));
  Rig.Engine.Free;
end;

{ ---- G: gate geometry ---- }

procedure TestGate;
const
  H  = 16;      { line height }
  CW = 8;       { char width  }
  TL = 40;      { text left   }
  TOP = 160;    { top of the hovered line }
  ED: HWND = HWND($1234);
  OTHER: HWND = HWND($5678);
var
  A: TDLHoverAnchor;
begin
  { Token at columns [4, 10): X span [72, 120). Line band centre 168, +-9.6. }
  A:= DLHoverAnchorFor(ED, TL, CW, TOP, H, 4, 10);
  Check('G1 anchor X span = text left + column * char width', (A.TokenLeftX = 72) and (A.TokenRightX = 120), Format('%d..%d', [A.TokenLeftX, A.TokenRightX]));
  Check('G2 same window, inside the token, on the line -> show', DLHoverGate(A, ED, Point(90, 168)) = hgvShow);
  Check('G3 the first pixel of the token shows', DLHoverGate(A, ED, Point(72, 168)) = hgvShow);
  Check('G4 the first pixel AFTER the token does not', DLHoverGate(A, ED, Point(120, 168)) = hgvOffToken);
  Check('G5 one pixel before the token does not', DLHoverGate(A, ED, Point(71, 168)) = hgvOffToken);
  Check('G6 another window (Project Manager) -> discard', DLHoverGate(A, OTHER, Point(90, 168)) = hgvOtherWindow);
  Check('G7 window under the cursor 0 -> discard', DLHoverGate(A, 0, Point(90, 168)) = hgvOtherWindow);
  { centre 168; 0.6 * 16 = 9.6 -> Y in [158.4, 177.6] }
  Check('G8 Y = centre + 9 (inside 0.6 line heights) shows', DLHoverGate(A, ED, Point(90, 177)) = hgvShow);
  Check('G9 Y = centre - 9 shows', DLHoverGate(A, ED, Point(90, 159)) = hgvShow);
  Check('G10 Y = centre + 10 (next line) -> discard', DLHoverGate(A, ED, Point(90, 178)) = hgvOffLine);
  Check('G11 Y = centre - 10 (previous line) -> discard', DLHoverGate(A, ED, Point(90, 158)) = hgvOffLine);
  Check('G12 window is checked before geometry', DLHoverGate(A, OTHER, Point(0, 0)) = hgvOtherWindow);
  A.Hwnd:= 0;
  Check('G13 no anchor -> discard', DLHoverGate(A, 0, Point(90, 168)) = hgvNoAnchor);
end;

{ ---- S: identifier span ---- }

procedure TestIdentSpan;
var
  S, E: Integer;
begin
  Check('S1 middle of an identifier', DLIdentSpanAt('  FooBar := 1;', 4, S, E) and (S = 2) and (E = 8), Format('%d..%d', [S, E]));
  Check('S2 first char', DLIdentSpanAt('  FooBar := 1;', 2, S, E) and (S = 2) and (E = 8));
  Check('S3 last char', DLIdentSpanAt('  FooBar := 1;', 7, S, E) and (S = 2) and (E = 8));
  Check('S4 whitespace is no identifier', not DLIdentSpanAt('  FooBar := 1;', 1, S, E));
  Check('S5 punctuation is no identifier', not DLIdentSpanAt('  FooBar := 1;', 9, S, E));
  Check('S6 a dotted name splits at the dot', DLIdentSpanAt('a.Text', 3, S, E) and (S = 2) and (E = 6), Format('%d..%d', [S, E]));
  Check('S7 past the end of the line', not DLIdentSpanAt('abc', 3, S, E));
  Check('S8 negative column', not DLIdentSpanAt('abc', -1, S, E));
  Check('S9 underscore and digits belong to the identifier', DLIdentSpanAt('x _a1_ y', 3, S, E) and (S = 2) and (E = 6));
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestGate;
    TestIdentSpan;
    TestQueueNeverBlocks;
    if GQueueBlocked then Check('W* .. T*: not run -- the write queue blocks, every pipe test would hang', False)
    else
    begin
      TestQueueCoalesces;
      TestAsyncReply;
      TestSupersededDropped;
      TestTimeoutBusyStuck;
      TestNotifyWhenEngineStopsReading;
      TestTeardownBudget;
    end;
  except
    on E: Exception do
    begin
      Writeln('FAIL  unhandled exception: ', E.ClassName, ': ', E.Message);
      Inc(GFail);
    end;
  end;
  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  Flush(Output);
  { ExitProcess, not Halt: a regression may have left a thread blocked in a
    pipe, and finalization must not wait for it. }
  ExitProcess(if GFail > 0 then 1 else 0);
end.
