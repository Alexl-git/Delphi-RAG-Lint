program LspStubServer;

{ A stand-in for DelphiLSP, used by run_lsp_proxy_relay_guard.ps1.

  WHY A STUB AT ALL. The relay's contract is that the client sees exactly what
  it would have seen talking to the server directly. Proving that against the
  REAL DelphiLSP means having RAD Studio in the loop, which is the one
  environment where a broken relay costs the owner their working day -- and it
  also means the expected bytes are whatever DelphiLSP felt like emitting, so a
  mismatch cannot be told apart from a version difference.

  This stub makes both sides known:

    * it writes a fixed PREAMBLE to stdout before reading anything, so the
      child-to-client direction is testable on its own;
    * it echoes stdin to stdout VERBATIM, so the client-to-child direction is
      observable through the same stream -- if the relay mangles, reorders,
      drops or re-chunks what it forwards, the echo shows it;
    * it writes one fixed line to stderr, because the relay must carry the
      child's stderr through as well, and a server that logs into a void is
      undiagnosable;
    * it exits with a fixed non-zero code, so exit-code propagation is testable.

  Three further modes, selected by environment variables the child inherits
  from the guard (merge plan P0; see the constants below): PUSH, SCRIPTED and
  the request LOG. They exist for the merge-proxy guards, which need a server
  that speaks unprompted, answers with known results after a known delay, and
  records what it really received.

  Raw handles throughout, never Read/Write on the RTL text files: text I/O
  would translate line endings and stop at a byte 26, and this stub exists
  precisely to carry bytes that such a translation would corrupt. }

{$APPTYPE CONSOLE}

uses
    Winapi.Windows
  , System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  ;

const
  BUF_BYTES = 4096;

  { Deliberately NOT valid LSP framing. Task 4 replaces the raw pump with a
    Content-Length reader, and this preamble is what catches a reader that
    swallows anything it cannot parse instead of forwarding it. }
  PREAMBLE = 'STUB-PREAMBLE-BEGIN';
  TRAILER  = 'STUB-TRAILER-END';
  ERRLINE  = 'STUB-STDERR-LINE';

  { A distinctive code, chosen so that a relay returning 0 (its own success) or
    1 (a generic failure) cannot pass by coincidence. }
  STUB_EXIT_CODE = 42;

  { LINGER MODE, selected by the environment variable below because the child
    inherits our environment and no new CLI surface is needed to reach it.

    WITHOUT it this stub cannot test the lifecycle at all. Killing the relay
    closes every handle it owned, including the write end of this process's
    stdin -- so a stub that exits on EOF dies on its own, and the lifecycle
    guard then passes against a build with no Job Object whatsoever. Lingering
    models the case the Job Object actually exists for: a language server that
    is hung, or busy, or simply does not treat a closed stdin as a shutdown,
    and which therefore survives its parent unless the OS reaps it.

    The wait is bounded rather than infinite so that a FAILING guard leaves a
    process that goes away by itself instead of a permanent orphan. }
  LINGER_ENV_VAR = 'DRAGLINT_STUB_LINGER';
  LINGER_MS      = 120 * 1000;

  { PUSH MODE (echo mode only). The named file's raw bytes are written to
    stdout right after the preamble, before anything is read -- a server-
    initiated notification such as publishDiagnostics, which is the frame the
    diagnostics merge rewrites and which no request ever prompts. }
  PUBLISH_ENV_VAR = 'DRAGLINT_STUB_PUBLISH_FILE';

  { SCRIPTED MODE. No preamble, no trailer, no echo: stdin is parsed as LSP
    frames (headers in any order, Content-Type tolerated) and each REQUEST is
    answered from the script, one line per method:
      <method> TAB <delay-ms> TAB <result-json>     ("null" = result null)
    A request whose method is not scripted gets error -32601; notifications
    (no id) and client responses (no method) are dropped. Exit code 0 on stdin
    EOF, because a scripted session that ends cleanly is not the exit-code
    test. The delay is what lets a merge guard blow a budget on purpose. }
  SCRIPT_ENV_VAR = 'DRAGLINT_STUB_SCRIPT';

  { REQUEST LOG (scripted mode). One line per received frame:
    <method> TAB <id-or-dash>, so a guard can prove which frames the proxy
    forwarded and which it answered or swallowed itself. }
  LOG_ENV_VAR = 'DRAGLINT_STUB_LOG';

  ERR_METHOD_NOT_FOUND = -32601;
  CRLF2 = #13#10#13#10;

type
  TScriptLine = record
    Method : string;
    DelayMs: Integer;
    Result : string;
  end;

procedure WriteRaw(AHandle: THandle; const ABytes: RawByteString);
var
  Sent  : DWORD;
  Offset: DWORD;
  Total : DWORD;
begin
  if ABytes = '' then Exit;
  Total := DWORD(Length(ABytes));
  Offset:= 0;
  while Offset < Total do
  begin
    Sent:= 0;
    if not WriteFile(AHandle, ABytes[Offset + 1], Total - Offset, Sent, nil) then Exit;
    if Sent = 0 then Exit;
    Inc(Offset, Sent);
  end;
end;

procedure WriteBytes(AHandle: THandle; const ABytes: TBytes);
var
  Sent  : DWORD;
  Offset: Integer;
begin
  Offset:= 0;
  while Offset < Length(ABytes) do
  begin
    Sent:= 0;
    if not WriteFile(AHandle, ABytes[Offset], DWORD(Length(ABytes) - Offset), Sent, nil) then Exit;
    if Sent = 0 then Exit;
    Inc(Offset, Integer(Sent));
  end;
end;

{ Writes ABody as one LSP frame; Content-Length is the UTF-8 BYTE count. }
procedure WriteFrame(AHandle: THandle; const ABody: string);
var
  Body: TBytes;
begin
  Body:= TEncoding.UTF8.GetBytes(ABody);
  WriteBytes(AHandle, TEncoding.ASCII.GetBytes('Content-Length: ' + IntToStr(Length(Body)) + #13#10#13#10));
  WriteBytes(AHandle, Body);
end;

function LoadScript(const APath: string): TArray<TScriptLine>;
var
  Line : string;
  T1   : Integer;
  T2   : Integer;
  Entry: TScriptLine;
begin
  Result:= nil;
  for Line in TFile.ReadAllLines(APath) do
  begin
    T1:= Pos(#9, Line);
    if T1 = 0 then Continue;
    T2:= Pos(#9, Line, T1 + 1);
    if T2 = 0 then Continue;
    Entry.Method := Copy(Line, 1, T1 - 1);
    Entry.DelayMs:= StrToIntDef(Copy(Line, T1 + 1, T2 - T1 - 1), 0);
    Entry.Result := Trim(Copy(Line, T2 + 1, MaxInt));
    Result:= Result + [Entry];
  end;
end;

{ The Content-Length value from a header block, wherever it sits among the
  headers; -1 when absent or unreadable. }
function HeaderContentLength(const AHeaders: string): Integer;
var
  Line: string;
begin
  Result:= -1;
  for Line in AHeaders.Split([#13#10]) do
    if Line.ToLower.StartsWith('content-length:') then
      Exit(StrToIntDef(Trim(Copy(Line, Length('content-length:') + 1, MaxInt)), -1));
end;

procedure AnswerFrame(AOut: THandle; const ABody: string; const AScript: TArray<TScriptLine>;
  const ALogPath: string);
var
  Json  : TJSONValue;
  Obj   : TJSONObject;
  IdVal : TJSONValue;
  Method: string;
  IdText: string;
  Entry : TScriptLine;
  Found : Boolean;
begin
  Json:= TJSONObject.ParseJSONValue(ABody);
  try
    if not (Json is TJSONObject) then Exit;
    Obj:= TJSONObject(Json);
    if not Obj.TryGetValue<string>('method', Method) then Method:= '';
    IdVal := Obj.GetValue('id');
    IdText:= if IdVal = nil then '-' else IdVal.ToJSON;
    if ALogPath <> '' then
      TFile.AppendAllText(ALogPath, Method + #9 + IdText + #13#10, TEncoding.ASCII);
    if (IdVal = nil) or (Method = '') then Exit;   { notification, or a client response }
    Found:= False;
    for Entry in AScript do
      if Entry.Method = Method then
      begin
        Found:= True;
        if Entry.DelayMs > 0 then Sleep(Entry.DelayMs);
        WriteFrame(AOut, '{"jsonrpc":"2.0","id":' + IdText + ',"result":' + Entry.Result + '}');
        Break;
      end;
    if not Found then
      WriteFrame(AOut, '{"jsonrpc":"2.0","id":' + IdText + ',"error":{"code":' +
                       IntToStr(ERR_METHOD_NOT_FOUND) + ',"message":"not scripted"}}');
  finally
    Json.Free;
  end;
end;

{ Scripted mode: parse framed requests from stdin until EOF. }
procedure RunScripted(AIn, AOut: THandle; const AScriptPath, ALogPath: string);
var
  Script : TArray<TScriptLine>;
  Acc    : TBytes;
  Len    : Integer;
  Buf    : array[0..BUF_BYTES - 1] of Byte;
  Got    : DWORD;
  HdrEnd : Integer;
  BodyLen: Integer;
  Text   : string;
  Body   : string;
begin
  Script:= LoadScript(AScriptPath);
  Len:= 0;
  while True do
  begin
    Got:= 0;
    if not ReadFile(AIn, Buf, SizeOf(Buf), Got, nil) then Break;
    if Got = 0 then Break;
    if Len + Integer(Got) > Length(Acc) then SetLength(Acc, (Len + Integer(Got)) * 2);
    Move(Buf[0], Acc[Len], Got);
    Inc(Len, Integer(Got));
    while True do
    begin
      Text  := TEncoding.ASCII.GetString(Acc, 0, Len);   { 1 char per byte, so offsets match }
      HdrEnd:= Pos(CRLF2, Text) - 1;
      if HdrEnd < 0 then Break;
      BodyLen:= HeaderContentLength(Copy(Text, 1, HdrEnd));
      if BodyLen < 0 then BodyLen:= 0;   { unreadable header: drop it and move on }
      if Len < HdrEnd + Length(CRLF2) + BodyLen then Break;
      Body:= TEncoding.UTF8.GetString(Acc, HdrEnd + Length(CRLF2), BodyLen);
      AnswerFrame(AOut, Body, Script, ALogPath);
      Dec(Len, HdrEnd + Length(CRLF2) + BodyLen);
      if Len > 0 then Move(Acc[HdrEnd + Length(CRLF2) + BodyLen], Acc[0], Len);
    end;
  end;
end;

var
  HIn   : THandle;
  HOut  : THandle;
  HErr  : THandle;
  Buf   : array[0..BUF_BYTES - 1] of Byte;
  Got   : DWORD;
  Sent  : DWORD;
  Offset: DWORD;
begin
  HIn := GetStdHandle(STD_INPUT_HANDLE );
  HOut:= GetStdHandle(STD_OUTPUT_HANDLE);
  HErr:= GetStdHandle(STD_ERROR_HANDLE );

  if GetEnvironmentVariable(SCRIPT_ENV_VAR) <> '' then
  begin
    WriteRaw(HErr, ERRLINE + #13#10);
    RunScripted(HIn, HOut, GetEnvironmentVariable(SCRIPT_ENV_VAR), GetEnvironmentVariable(LOG_ENV_VAR));
    ExitCode:= 0;
    Exit;
  end;

  WriteRaw(HOut, PREAMBLE);
  if GetEnvironmentVariable(PUBLISH_ENV_VAR) <> '' then
    WriteBytes(HOut, TFile.ReadAllBytes(GetEnvironmentVariable(PUBLISH_ENV_VAR)));
  WriteRaw(HErr, ERRLINE + #13#10);

  while True do
  begin
    Got:= 0;
    if not ReadFile(HIn, Buf, SizeOf(Buf), Got, nil) then Break;
    if Got = 0 then Break;
    Offset:= 0;
    while Offset < Got do
    begin
      Sent:= 0;
      if not WriteFile(HOut, Buf[Offset], Got - Offset, Sent, nil) then Break;
      if Sent = 0 then Break;
      Inc(Offset, Sent);
    end;
  end;

  WriteRaw(HOut, TRAILER);

  if GetEnvironmentVariable(LINGER_ENV_VAR) <> '' then Sleep(LINGER_MS);

  ExitCode:= STUB_EXIT_CODE;
end.
