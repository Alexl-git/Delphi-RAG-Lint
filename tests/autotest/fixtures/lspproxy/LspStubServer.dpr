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

  Raw handles throughout, never Read/Write on the RTL text files: text I/O
  would translate line endings and stop at a byte 26, and this stub exists
  precisely to carry bytes that such a translation would corrupt. }

{$APPTYPE CONSOLE}

uses
    Winapi.Windows
  , System.SysUtils
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

  WriteRaw(HOut, PREAMBLE);
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
