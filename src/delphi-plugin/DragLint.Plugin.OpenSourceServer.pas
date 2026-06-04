unit DragLint.Plugin.OpenSourceServer;

{ Open-in-IDE server (finding F7, plugin half).

  The drag-lint graph viewer runs as its own process.  When the user clicks a
  method/field in the graph it hands the file+line(+col) to THIS plugin over a
  named pipe; we open it in the already-running IDE via OTAPI rather than
  spawning a second bds.exe.

  Wire contract (must match DragLint.Graph.OpenSourceClient on the viewer side,
  docs/ipc-open-source-contract*.md):
    * Pipe   : \\.\pipe\drag-lint-open-source
    * Message: one line  <file><TAB><line>[<TAB><col>]<LF>   UTF-8, no BOM
    * <file> absolute path (may contain spaces, never TAB/LF)
    * <line> 1-based; <col> optional 1-based caret column
    * one message per connection; no reply.

  Robust teardown (the part that matters given the v0.40 unload AVs):
    The listener thread blocks in ConnectNamedPipe.  To stop it cleanly we set
    Terminated and connect a throwaway client to the pipe, which releases
    ConnectNamedPipe; the thread sees Terminated and exits.  No overlapped I/O,
    no thread-kill.  StopOpenSourceServer is idempotent and is called from both
    the wizard's Destroyed and this unit's finalization. }

interface

procedure StartOpenSourceServer;
procedure StopOpenSourceServer;   { idempotent }

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  ToolsAPI;

const
  OPEN_SOURCE_PIPE_NAME = '\\.\pipe\drag-lint-open-source';
  SEP  = #9;
  TERM = #10;
  MAX_MSG = 8 * 1024;   { a path + 2 ints; anything larger is bogus }

type
  TOpenSourceListener = class(TThread)
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

var
  GServer: TOpenSourceListener = nil;

{ ---- main-thread open (OTAPI) ------------------------------------------- }

procedure DoOpenInIDE(const AFile: string; ALine, ACol: Integer);
var
  AS_: IOTAActionServices;
  ESS: IOTAEditorServices;
  EV:  IOTAEditView;
  Pos: IOTAEditPosition;
  OpenOk: Boolean;
begin
  if (AFile = '') or not FileExists(AFile) then Exit;

  { Guard on OpenFile's result.  If it failed (or the service is absent) we must
    NOT fall through and GotoLine -- that would scroll whatever file was already
    focused to ALine, which looks like "the IDE got the command but did the
    wrong thing." }
  OpenOk := Supports(BorlandIDEServices, IOTAActionServices, AS_) and
            AS_.OpenFile(AFile);
  if not OpenOk then Exit;

  if (ALine > 0) and Supports(BorlandIDEServices, IOTAEditorServices, ESS) then
  begin
    EV := ESS.TopView;
    if EV <> nil then
    begin
      Pos := EV.Position;
      if Pos <> nil then
      begin
        if ACol > 1 then
          Pos.Move(ALine, ACol)
        else
          Pos.GotoLine(ALine);
        EV.MoveViewToCursor;
        EV.Paint;
      end;
    end;
  end;
end;

{ Build a fresh closure per call so each queued open captures its OWN copies of
  the arguments (anonymous methods capture variables by reference, so we must
  not let the listener loop reuse the same locals underneath a pending queue). }
function MakeOpenProc(const AFile: string; ALine, ACol: Integer):
  TThreadProcedure;
begin
  Result :=
    procedure
    begin
      DoOpenInIDE(AFile, ALine, ACol);
    end;
end;

{ Parse "<file>[TAB<line>[TAB<col>]]" -- positional, extra fields ignored, a
  missing/garbled number defaults to safe values (line 0 = file only). }
procedure DispatchMessage(const ARaw: string);
var
  S:       string;
  Parts:   TArray<string>;
  AFile:   string;
  ALine:   Integer;
  ACol:    Integer;
begin
  S := ARaw;
  { strip a trailing CR if a client ever sends CRLF, and the LF terminator }
  while (S <> '') and ((S[Length(S)] = #10) or (S[Length(S)] = #13)) do
    SetLength(S, Length(S) - 1);
  if S = '' then Exit;

  Parts := S.Split([SEP]);
  if Length(Parts) = 0 then Exit;
  AFile := Parts[0];
  ALine := 0;
  ACol  := 0;
  if Length(Parts) >= 2 then ALine := StrToIntDef(Parts[1], 0);
  if Length(Parts) >= 3 then ACol  := StrToIntDef(Parts[2], 0);
  if AFile = '' then Exit;

  { OTAPI must run on the IDE main thread. }
  TThread.Queue(nil, MakeOpenProc(AFile, ALine, ACol));
end;

{ ---- listener thread ----------------------------------------------------- }

constructor TOpenSourceListener.Create;
begin
  inherited Create(False);   { start immediately }
  FreeOnTerminate := False;  { owner frees us after WaitFor }
end;

procedure TOpenSourceListener.Execute;
var
  Pipe:     THandle;
  Connected: Boolean;
  Buf:      array[0..511] of AnsiChar;
  Read:     DWORD;
  Acc:      TBytes;
  I:        Integer;
  GotTerm:  Boolean;
  Raw:      string;
begin
  NameThreadForDebugging('drag-lint open-source pipe');
  while not Terminated do
  begin
    Pipe := CreateNamedPipe(
      OPEN_SOURCE_PIPE_NAME,
      PIPE_ACCESS_INBOUND,
      PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT,
      PIPE_UNLIMITED_INSTANCES,
      0, MAX_MSG, 0, nil);
    if Pipe = INVALID_HANDLE_VALUE then
    begin
      { transient failure -- back off briefly, re-check Terminated }
      Sleep(200);
      Continue;
    end;

    try
      { Blocks until a client connects (the viewer, or the throwaway client
        that StopOpenSourceServer uses to release us). }
      Connected := ConnectNamedPipe(Pipe, nil) or
                   (GetLastError = ERROR_PIPE_CONNECTED);
      if Terminated then Break;
      if not Connected then Continue;

      { Read the single framed message (until LF, EOF, or the size cap). }
      SetLength(Acc, 0);
      GotTerm := False;
      while (not GotTerm) and (Length(Acc) < MAX_MSG) do
      begin
        Read := 0;
        if not ReadFile(Pipe, Buf[0], Length(Buf), Read, nil) then Break;
        if Read = 0 then Break;
        I := Length(Acc);
        SetLength(Acc, I + Integer(Read));
        Move(Buf[0], Acc[I], Read);
        { stop as soon as we have the LF terminator }
        for I := 0 to Integer(Read) - 1 do
          if Buf[I] = TERM then begin GotTerm := True; Break; end;
      end;

      if Length(Acc) > 0 then
      begin
        Raw := TEncoding.UTF8.GetString(Acc);
        if not Terminated then
          DispatchMessage(Raw);
      end;
    finally
      DisconnectNamedPipe(Pipe);
      CloseHandle(Pipe);
    end;
  end;
end;

{ ---- public start/stop --------------------------------------------------- }

procedure StartOpenSourceServer;
begin
  if GServer <> nil then Exit;
  GServer := TOpenSourceListener.Create;
end;

procedure StopOpenSourceServer;
var
  H: THandle;
begin
  if GServer = nil then Exit;

  GServer.Terminate;

  { Release the thread's blocking ConnectNamedPipe by connecting a throwaway
    client.  WaitNamedPipe + CreateFile; we write nothing, just close. }
  if WaitNamedPipe(OPEN_SOURCE_PIPE_NAME, 200) then
  begin
    H := CreateFile(OPEN_SOURCE_PIPE_NAME, GENERIC_READ, 0, nil,
      OPEN_EXISTING, 0, 0);
    if H <> INVALID_HANDLE_VALUE then
      CloseHandle(H);
  end;

  GServer.WaitFor;
  FreeAndNil(GServer);
end;

initialization

finalization
  try StopOpenSourceServer; except end;

end.
