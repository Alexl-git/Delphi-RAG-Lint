unit ConvRules.OpenSourceClient;

{ VENDORED from C:\Projects\Delphi-RAG-Lint-Graph\src\control\DragLint.Graph.OpenSourceClient.pas
  on 2026-07-30. The wire contract is frozen and documented in that repo's
  docs/ipc-open-source-contract.md -- pipe \\.\pipe\drag-lint-open-source, one framed
  message per connection. Copied rather than referenced by search path so this build does
  not depend on a sibling checkout existing at an absolute path. If the contract ever
  changes, both copies must change together.

  The only DELIBERATE divergence from the original is presentational: the graph-viewer
  intro was rewritten for this host, and the four public routines carry DocInsight ///
  comments (house rule) instead of the original's brace-delimited ones. Every executable
  line is byte-identical to the source, so a contract change stays a mechanical
  re-copy. }

{ Open-in-IDE handoff.

  The rule-book editor runs as its own process. To open a source file in the
  *already running* Delphi IDE (rather than spawning a second bds.exe), it hands
  the file+line to the drag-lint IDE plugin over a named pipe. The plugin --
  living inside the IDE process with OTAPI access -- listens on the pipe and
  routes each message to IOTAActionServices.OpenFile +
  IOTAEditView.Position.GotoLine.

  This unit is the CLIENT half. The plugin (server) side must match it.

  Wire contract
  -------------
    * Pipe name : \\.\pipe\drag-lint-open-source  (OPEN_SOURCE_PIPE_NAME)
    * Direction : client -> server, one message per connection.
    * Framing   : a single line  <file><TAB><line><LF>
                  - <file> is an absolute path; may contain spaces, never a
                    TAB or LF (Windows paths cannot contain either).
                  - <line> is the 1-based start line as decimal ASCII.
                  - terminated by a single LF (#10).  No CR.
    * Encoding  : UTF-8 (no BOM).  ASCII paths are a UTF-8 subset, so a
                  plain ANSI reader also works for the common case; the
                  plugin should decode UTF-8 to be safe.
    * Lifecycle : the client opens the pipe, writes exactly one framed
                  message, flushes, and closes.  The server should treat
                  end-of-connection (or the LF) as end-of-message.
    * No reply is required.  The client does not read a response; it closes
      its handle immediately after FlushFileBuffers.

  Server (plugin) requirements
    * Create the pipe with PIPE_ACCESS_DUPLEX (or _INBOUND) and
      PIPE_TYPE_BYTE or PIPE_TYPE_MESSAGE -- this client uses CreateFile +
      WriteFile (a byte stream), so a byte-type pipe is fine.
    * Use PIPE_UNLIMITED_INSTANCES (or re-arm ConnectNamedPipe per message)
      so rapid double-clicks are not dropped.

  Pure: depends only on System.SysUtils + Winapi.Windows.  No VCL, no FireDAC.
  Safe to link into the console test harness. }

interface

uses
  System.SysUtils
  ; { TBytes }

const
  OPEN_SOURCE_PIPE_NAME = '\\.\pipe\drag-lint-open-source';

  { Field/record separators used by the wire framing above. }
  OPEN_SOURCE_SEP  = #9; { TAB between file and line }
  OPEN_SOURCE_TERM = #10; { LF terminator }

/// <summary>Builds the framed UTF-8 message bytes for (AFile, ALine):
/// &lt;file&gt;&lt;TAB&gt;&lt;line&gt;&lt;LF&gt;.</summary>
/// <param name="AFile">Absolute path; must contain neither TAB nor LF.</param>
/// <param name="ALine">1-based start line, emitted as decimal ASCII.</param>
/// <returns>The exact bytes SendOpenSource writes to the pipe.</returns>
/// <remarks>Exposed so a round-trip test (and the plugin author) can assert the
/// byte layout without a live pipe.</remarks>
function BuildOpenSourceMessage(const AFile: string; ALine: Integer): TBytes; overload;

/// <summary>Column-aware framing (contract v2):
/// &lt;file&gt;&lt;TAB&gt;&lt;line&gt;&lt;TAB&gt;&lt;col&gt;&lt;LF&gt;.</summary>
/// <param name="AFile">Absolute path; must contain neither TAB nor LF.</param>
/// <param name="ALine">1-based start line.</param>
/// <param name="ACol">1-based caret column; &lt;= 0 is sent as 1.</param>
/// <returns>The framed v2 message bytes.</returns>
/// <remarks>The server reads the line positionally and treats the column as
/// optional, so this stays back-compatible with a v1 (file+line only) reader.</remarks>
function BuildOpenSourceMessage(const AFile: string; ALine, ACol: Integer): TBytes; overload;

/// <summary>Sends an open-source request to the running plugin.</summary>
/// <param name="AFile">Absolute path to open; '' returns False without touching
/// the pipe.</param>
/// <param name="ALine">1-based line to place the caret on.</param>
/// <param name="AWaitMs">How long to wait for a free pipe instance before giving
/// up.</param>
/// <returns>True only if a pipe server was present AND the full message was
/// written. False (within AWaitMs) when no server is listening -- the caller
/// should then degrade, e.g. show file:line and copy it to the clipboard, so
/// standalone use still works.</returns>
/// <remarks>Never raises: all Win32 failures are reported as a False result.</remarks>
function SendOpenSource(const AFile: string; ALine: Integer; AWaitMs: Cardinal = 200): Boolean;

/// <summary>Column-aware send (contract v2).</summary>
/// <param name="AFile">Absolute path to open; '' returns False.</param>
/// <param name="ALine">1-based line.</param>
/// <param name="ACol">1-based caret column.</param>
/// <param name="AWaitMs">Pipe wait budget in milliseconds.</param>
/// <returns>True only if a server was present AND the whole message was written.</returns>
/// <remarks>A distinct name (not an overload) so it never collides with the
/// file+line+waitMs signature above. Never raises.</remarks>
function SendOpenSourceAt(const AFile: string; ALine, ACol: Integer; AWaitMs: Cardinal = 200): Boolean;

implementation

uses
  Winapi.Windows
  ;

function BuildOpenSourceMessage(const AFile: string; ALine: Integer): TBytes;
var
  Line: string;
begin
  Line:= AFile + OPEN_SOURCE_SEP + IntToStr(ALine) + OPEN_SOURCE_TERM;
  Result:= TEncoding.UTF8.GetBytes(Line);
end;

function BuildOpenSourceMessage(const AFile: string; ALine, ACol: Integer): TBytes;
var
  Line: string ;
  Col : Integer;
begin
  Col:= ACol;
  if Col < 1 then Col:= 1;
  Line:= AFile + OPEN_SOURCE_SEP + IntToStr(ALine) + OPEN_SOURCE_SEP + IntToStr(Col) + OPEN_SOURCE_TERM;
  Result:= TEncoding.UTF8.GetBytes(Line);
end;

{ Shared transport: writes one framed message to the pipe.  Returns True only
  if a server was present AND the whole message was written.  Never raises. }
function SendOpenSourceBytes(const AMsg: TBytes; AWaitMs: Cardinal): Boolean;
var
  H      : THandle;
  Written: DWORD  ;
begin
  Result:= False;
  if Length(AMsg) = 0 then Exit;

  { Fast no-server check: if no instance is available within AWaitMs we bail
    so the caller can degrade instead of blocking the UI. }
  if not WaitNamedPipe(OPEN_SOURCE_PIPE_NAME, AWaitMs) then Exit;

  H:= CreateFile(OPEN_SOURCE_PIPE_NAME, GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    Written:= 0;
    if WriteFile(H, AMsg[0], DWORD(Length(AMsg)), Written, nil) and (Written = DWORD(Length(AMsg))) then
    begin
      FlushFileBuffers(H);
      Result:= True;
    end;
  finally
    CloseHandle(H);
  end;
end; // function

function SendOpenSource(const AFile: string; ALine: Integer; AWaitMs: Cardinal): Boolean;
begin
  Result:= False;
  if AFile = '' then Exit;
  Result:= SendOpenSourceBytes(BuildOpenSourceMessage(AFile, ALine), AWaitMs);
end;

function SendOpenSourceAt(const AFile: string; ALine, ACol: Integer; AWaitMs: Cardinal): Boolean;
begin
  Result:= False;
  if AFile = '' then Exit;
  Result:= SendOpenSourceBytes( BuildOpenSourceMessage(AFile, ALine, ACol), AWaitMs);
end;

end.
