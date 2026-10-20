unit FeatureGen.Live;

{ Live reads from the drag-lint engine. Minimal for now: the --help text and
  the usage line of one verb. }

interface

uses
  System.SysUtils
  , System.Classes
  ;

type
  /// <summary>Raised when the engine cannot be run.</summary>
  EFeatureGenLive = class(Exception);

  /// <summary>The engine --help text and per-verb usage lookup.</summary>
  /// <remarks>Not thread-safe. Tests use LoadFromText so they never need the live engine.</remarks>
  TLiveHelp = class
  strict private
    FLines: TArray<string>;
  public
    /// <summary>Runs "pExe --help" (stderr discarded) and keeps its stdout, replacing any earlier load.</summary>
    /// <param name="pExe">Full path of drag-lint.exe.</param>
    /// <exception cref="EFeatureGenLive">The engine cannot be started.</exception>
    procedure Load(const pExe: string);
    /// <summary>Keeps pText as the help text, replacing any earlier load.</summary>
    /// <param name="pText">Help text, any line ending.</param>
    procedure LoadFromText(const pText: string);
    /// <summary>First help line that starts a verb entry.</summary>
    /// <param name="pVerb">Verb, or "verb sub" (single spaces).</param>
    /// <returns>The first line matching ^\s{2}drag-lint\s+verb(?=\s|$), trimmed, runs of spaces collapsed to one; '' when none.</returns>
    function UsageFor(const pVerb: string): string;
    /// <summary>The loaded help text, one element per line (no line ending).</summary>
    /// <returns>Empty before any load.</returns>
    function Lines: TArray<string>;
  end;

/// <summary>Runs a console program and returns its stdout, decoded as UTF-8.</summary>
/// <param name="pExe">Full path of the program (no PATH lookup).</param>
/// <param name="pArgs">Command-line arguments, already quoted.</param>
/// <returns>Everything the program wrote to stdout; '' when nothing.</returns>
/// <exception cref="EFeatureGenLive">The pipe cannot be created or the program cannot be started.</exception>
/// <remarks>stderr is discarded; waits for the program to exit; no timeout.</remarks>
function RunCapture(const pExe, pArgs: string): string;

implementation

uses
  Winapi.Windows
  , System.RegularExpressions
  ;

function RunCapture(const pExe, pArgs: string): string;
var
  lSa: TSecurityAttributes;
  lRead, lWrite, lNul: THandle;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lCmd: string;
  lBuf: array[0..4095] of Byte;
  lGot: DWORD;
  lMem: TMemoryStream;
  lBytes: TBytes;
begin
  Result := '';
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;
  lSa.lpSecurityDescriptor := nil;
  if not CreatePipe(lRead, lWrite, @lSa, 0) then
    raise EFeatureGenLive.Create('cannot create pipe');
  SetHandleInformation(lRead, HANDLE_FLAG_INHERIT, 0);
  lNul := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_WRITE, @lSa, OPEN_EXISTING, 0, 0);
  try
    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    lSi.wShowWindow := SW_HIDE;
    lSi.hStdOutput := lWrite;
    lSi.hStdError := lNul;
    lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    lCmd := '"' + pExe + '" ' + pArgs;
    UniqueString(lCmd);
    if not CreateProcess(PChar(pExe), PChar(lCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, lSi, lPi) then
      raise EFeatureGenLive.CreateFmt('cannot start engine "%s"', [pExe]);
    CloseHandle(lWrite);
    lWrite := 0;
    lMem := TMemoryStream.Create;
    try
      while ReadFile(lRead, lBuf, SizeOf(lBuf), lGot, nil) and (lGot > 0) do
        lMem.WriteBuffer(lBuf, lGot);
      WaitForSingleObject(lPi.hProcess, INFINITE);
      CloseHandle(lPi.hProcess);
      CloseHandle(lPi.hThread);
      if lMem.Size > 0 then
      begin
        SetLength(lBytes, lMem.Size);
        Move(lMem.Memory^, lBytes[0], lMem.Size);
        Result := TEncoding.UTF8.GetString(lBytes);
      end;
    finally
      lMem.Free;
    end;
  finally
    if lWrite <> 0 then
      CloseHandle(lWrite);
    CloseHandle(lRead);
    if lNul <> INVALID_HANDLE_VALUE then
      CloseHandle(lNul);
  end;
end;

procedure TLiveHelp.Load(const pExe: string);
begin
  LoadFromText(RunCapture(pExe, '--help'));
end;

procedure TLiveHelp.LoadFromText(const pText: string);
begin
  FLines := pText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function TLiveHelp.Lines: TArray<string>;
begin
  Result := FLines;
end;

function TLiveHelp.UsageFor(const pVerb: string): string;
var
  lRe: TRegEx;
  lLine: string;
begin
  Result := '';
  lRe := TRegEx.Create('^\s{2}drag-lint\s+' + TRegEx.Escape(pVerb) + '(?=\s|$)');
  for lLine in FLines do
    if lRe.IsMatch(lLine) then
      Exit(TRegEx.Replace(Trim(lLine), ' {2,}', ' '));
end;

end.
