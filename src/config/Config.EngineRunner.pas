unit Config.EngineRunner;

/// <summary>Asynchronous engine runner: shells out to drag-lint.exe via
/// CreateProcess + anonymous pipe, streams stdout/stderr line-by-line to the
/// main thread via TThread.Queue, then calls AOnDone with the exit code.
/// All Win32 handles are closed in try-finally; no handle leaks.</summary>
/// <remarks>
/// Usage:
///   TEngineRunner.Run(ExePath, Args, OnLine, OnDone);
/// TEngineRunner.Run is a class method that spawns a background thread and
/// returns immediately. The caller does not own the thread; it is
/// FreeOnTerminate and cleans itself up after AOnDone fires.
/// AOnLine and AOnDone are always invoked on the main (VCL) thread via
/// TThread.Queue. Never touch VCL from the worker thread directly.
/// ResolveEngineExe is a pure class function with no side-effects.
/// Thread-safety: Run may be called multiple times; each call creates an
/// independent worker thread.
/// </remarks>

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows;

type
  /// <summary>Resolves the drag-lint engine path and spawns async runs.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: Config.EngineRunner.TEngineRunner.TRunnerThread.Create (Config.EngineRunner.pas) ?, Config.EngineRunner.TEngineRunner.TRunnerThread.Execute (Config.EngineRunner.pas) ?, Config.EngineRunner.TEngineRunner.TRunnerThread.QueueDone (Config.EngineRunner.pas) ?, Config.EngineRunner.TEngineRunner.TRunnerThread.QueueLine (Config.EngineRunner.pas) ?, Config.IndexesFrame.TIndexesFrame.RunEngine (Config.IndexesFrame.pas)</para>
  /// <para>Used in units: Config.EngineRunner, Config.IndexesFrame</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEngineRunner = class
  private
    type
      /// <summary>Worker thread: creates the child process, reads the pipe
      /// line-by-line, and queues callbacks to the main thread.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Used by: Config.EngineRunner.TEngineRunner.Run (Config.EngineRunner.pas)</para>
      /// <para>Used in units: Config.EngineRunner</para>
      /// <seealso cref="Config.EngineRunner.TEngineRunner.ResolveEngineExe"/>
      /// <seealso cref="Config.EngineRunner.TEngineRunner.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      TRunnerThread = class(TThread)
      private
        FExe:    string;
        FArgs:   string;
        FOnLine: TProc<string>;
        FOnDone: TProc<Integer>;
        /// <summary>Dispatch a line of text to the main thread via TThread.Queue.</summary>
        /// <param name="ALine"><!-- drag-lint:auto type -->const string</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: Config.EngineRunner.TEngineRunner.TRunnerThread.Execute (Config.EngineRunner.pas)</para>
        /// <para>Calls: CB</para>
        /// <para>Reads: FOnLine</para>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.Create"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.Execute"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.QueueDone"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure QueueLine(const ALine: string);
        /// <summary>Dispatch the exit code to the main thread via TThread.Queue.</summary>
        /// <param name="ACode"><!-- drag-lint:auto type -->Integer</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: Config.EngineRunner.TEngineRunner.TRunnerThread.Execute (Config.EngineRunner.pas)</para>
        /// <para>Calls: CB</para>
        /// <para>Reads: FOnDone</para>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.Create"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.Execute"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.QueueLine"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure QueueDone(ACode: Integer);
      protected
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Calls: CloseHandle, Config.EngineRunner.TEngineRunner.TRunnerThread.QueueDone, Config.EngineRunner.TEngineRunner.TRunnerThread.QueueLine, Copy, CreatePipe, CreateProcess, DWORD, FillChar, GetExitCodeProcess, GetStdHandle (+8 more)</para>
        /// <para>Complexity: 17 (cyclomatic, outer body), 106 lines (full implementation)</para>
        /// <para>Reads: FExe, FArgs</para>
        /// <para>Directives: override</para>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.QueueDone"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.QueueLine"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.Create"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        procedure Execute; override;
      public
        /// <summary><!-- drag-lint:auto sum -->TEngineRunner.TRunnerThread</summary>
        /// <param name="AExe"><!-- drag-lint:auto type -->const string</param>
        /// <param name="AArgs"><!-- drag-lint:auto type -->const string</param>
        /// <param name="AOnLine"><!-- drag-lint:auto type -->TProc&lt;string&gt;</param>
        /// <param name="AOnDone"><!-- drag-lint:auto type -->TProc&lt;Integer&gt;</param>
        /// <remarks>
        /// <!-- drag-lint:auto BEGIN -->
        /// <para>Called from: Config.EngineRunner.TEngineRunner.Run (Config.EngineRunner.pas)</para>
        /// <para>constructor</para>
        /// <para>Writes: FExe, FArgs, FOnLine, FOnDone</para>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.Execute"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.QueueDone"/>
        /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.QueueLine"/>
        /// <!-- drag-lint:auto END -->
        /// </remarks>
        constructor Create(const AExe, AArgs: string;
          AOnLine: TProc<string>; AOnDone: TProc<Integer>);
      end;
  public
    /// <summary>Locate drag-lint.exe. Priority:
    ///   1. AEnginePath if non-empty and not 'auto' and the file exists.
    ///   2. Beside this EXE (GetModuleName(0) dir).
    ///   3. ..\..\third_party\dll-win64\drag-lint.exe relative to this EXE.
    /// Returns '' if none of the candidates exist.</summary>
    /// <param name="AEnginePath">Configured engine path, or 'auto', or empty.</param>
    /// <returns>Absolute path to drag-lint.exe, or '' if not found.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Config.IndexesFrame.TIndexesFrame.RunEngine (Config.IndexesFrame.pas)</para>
    /// <para>Calls: GetModuleName</para>
    /// <para>Returns: ''; AEnginePath; Candidate</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="Config.EngineRunner.TEngineRunner.Run"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ResolveEngineExe(const AEnginePath: string): string; static;
    /// <summary>Run drag-lint.exe with AArgs asynchronously. AOnLine is called
    /// on the main thread for each stdout/stderr output line. AOnDone is called
    /// on the main thread with the process exit code when the run finishes.
    /// The spawned thread is FreeOnTerminate and cleans up without caller action.</summary>
    /// <param name="AExe">Full path to drag-lint.exe. Must not be empty.</param>
    /// <param name="AArgs">Argument string appended after the exe path.</param>
    /// <param name="AOnLine">Called (main thread) for each output line.</param>
    /// <param name="AOnDone">Called (main thread) with the exit code on finish.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Config.IndexesFrame.TIndexesFrame.RunEngine (Config.IndexesFrame.pas)</para>
    /// <para>Calls: Config.EngineRunner.TEngineRunner.TRunnerThread.Create</para>
    /// <para>Directives: static</para>
    /// <seealso cref="Config.EngineRunner.TEngineRunner.TRunnerThread.Create"/>
    /// <seealso cref="Config.EngineRunner.TEngineRunner.ResolveEngineExe"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Run(const AExe, AArgs: string;
      AOnLine: TProc<string>; AOnDone: TProc<Integer>); static;
  end;

implementation

{ TEngineRunner }

class function TEngineRunner.ResolveEngineExe(const AEnginePath: string): string;
var
  ExeDir, Candidate: string;
begin
  Result := '';

  { Priority 1: explicit non-auto path }
  if (AEnginePath <> '') and (AEnginePath <> 'auto') then
  begin
    if TFile.Exists(AEnginePath) then
    begin
      Result := AEnginePath;
      Exit;
    end;
  end;

  ExeDir := TPath.GetDirectoryName(GetModuleName(0));

  { Priority 2: beside this EXE }
  Candidate := TPath.Combine(ExeDir, 'drag-lint.exe');
  if TFile.Exists(Candidate) then
  begin
    Result := Candidate;
    Exit;
  end;

  { Priority 3: ..\..\third_party\dll-win64\drag-lint.exe }
  Candidate := TPath.Combine(ExeDir,
    '..\..\third_party\dll-win64\drag-lint.exe');
  Candidate := TPath.GetFullPath(Candidate);
  if TFile.Exists(Candidate) then
    Result := Candidate;
end;

class procedure TEngineRunner.Run(const AExe, AArgs: string;
  AOnLine: TProc<string>; AOnDone: TProc<Integer>);
var
  T: TRunnerThread;
begin
  T := TRunnerThread.Create(AExe, AArgs, AOnLine, AOnDone);
  T.FreeOnTerminate := True;
  T.Start;
end;

{ TEngineRunner.TRunnerThread }

constructor TEngineRunner.TRunnerThread.Create(const AExe, AArgs: string;
  AOnLine: TProc<string>; AOnDone: TProc<Integer>);
begin
  inherited Create(True { suspended });
  FExe    := AExe;
  FArgs   := AArgs;
  FOnLine := AOnLine;
  FOnDone := AOnDone;
end;

procedure TEngineRunner.TRunnerThread.QueueLine(const ALine: string);
var
  Capture: string;
  CB: TProc<string>;
begin
  Capture := ALine;
  CB      := FOnLine;
  TThread.Queue(nil,
    procedure
    begin
      CB(Capture);
    end);
end;

procedure TEngineRunner.TRunnerThread.QueueDone(ACode: Integer);
var
  Code: Integer;
  CB: TProc<Integer>;
begin
  Code := ACode;
  CB   := FOnDone;
  TThread.Queue(nil,
    procedure
    begin
      CB(Code);
    end);
end;

procedure TEngineRunner.TRunnerThread.Execute;
const
  PIPE_BUF = 4096;
var
  SA:          TSecurityAttributes;
  HReadPipe,
  HWritePipe:  THandle;
  SI:          TStartupInfo;
  PI:          TProcessInformation;
  CmdLine:     string;
  Buf:         array[0..PIPE_BUF - 1] of AnsiChar;
  BytesRead:   DWORD;
  ExitCode:    DWORD;
  Raw:         RawByteString;
  LineAccum:   string;
  Chunk:       string;
  P:           Integer;
  Line:        string;
begin
  HReadPipe   := 0;
  HWritePipe  := 0;
  PI.hProcess := 0;
  PI.hThread  := 0;

  { Redirect both stdout and stderr into a single anonymous pipe }
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength        := SizeOf(SA);
  SA.bInheritHandle := True;

  if not CreatePipe(HReadPipe, HWritePipe, @SA, 0) then
  begin
    QueueDone(-1);
    Exit;
  end;

  try
    { Make the read end non-inheritable so the child cannot inherit it }
    SetHandleInformation(HReadPipe, HANDLE_FLAG_INHERIT, 0);

    FillChar(SI, SizeOf(SI), 0);
    SI.cb          := SizeOf(SI);
    SI.dwFlags     := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdOutput  := HWritePipe;
    SI.hStdError   := HWritePipe;   { stderr merged into same pipe }
    SI.hStdInput   := GetStdHandle(STD_INPUT_HANDLE);

    CmdLine := '"' + FExe + '" ' + FArgs;
    UniqueString(CmdLine);

    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
        CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      QueueDone(-1);
      Exit;
    end;

    { Close the write end in the parent so EOF is signalled when child exits }
    CloseHandle(HWritePipe);
    HWritePipe := 0;

    { Read pipe line-by-line, accumulating partial lines across reads }
    LineAccum := '';
    repeat
      FillChar(Buf, SizeOf(Buf), 0);
      if not ReadFile(HReadPipe, Buf[0], PIPE_BUF, BytesRead, nil) then
        Break;
      if BytesRead = 0 then
        Break;

      { Convert raw bytes to string; OEM output is common from CLI tools }
      SetLength(Raw, BytesRead);
      Move(Buf[0], Raw[1], BytesRead);
      Chunk := string(Raw);

      LineAccum := LineAccum + Chunk;

      { Split accumulated text on LF boundaries; emit complete lines }
      while True do
      begin
        P := Pos(#10, LineAccum);
        if P = 0 then Break;
        Line := Copy(LineAccum, 1, P - 1);
        { Strip CR if present (CRLF output) }
        if (Line <> '') and (Line[Length(Line)] = #13) then
          SetLength(Line, Length(Line) - 1);
        LineAccum := Copy(LineAccum, P + 1, MaxInt);
        QueueLine(Line);
      end;
    until False;

    { Flush any trailing partial line (no trailing LF) }
    if LineAccum <> '' then
      QueueLine(LineAccum);

    WaitForSingleObject(PI.hProcess, INFINITE);
    if not GetExitCodeProcess(PI.hProcess, ExitCode) then
      ExitCode := DWORD(-1);

    QueueDone(Integer(ExitCode));
  finally
    if HWritePipe <> 0 then CloseHandle(HWritePipe);
    if HReadPipe  <> 0 then CloseHandle(HReadPipe);
    if PI.hProcess <> 0 then CloseHandle(PI.hProcess);
    if PI.hThread  <> 0 then CloseHandle(PI.hThread);
  end;
end;

end.
