unit DRagLint.Diagnostics.CompileCheck;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , System.DateUtils
  , Winapi.Windows
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Outcome of one compile run: the parsed findings, the compiler
  /// process exit code (0 = clean), and the raw merged stdout/stderr text (kept
  /// for diagnostics and fallback parsing).</summary>
  TCompileCheckResult = record
    Findings  : TArray<TCompilerFinding>;
    ExitCode  : Integer                 ;
    StdoutText: string                  ;
  end;

  /// <summary>Compiles a Delphi target out-of-process and turns the compiler's
  /// textual output into structured findings.</summary>
  /// <remarks>Stateless and thin (class methods only): spawn -> capture -> parse.
  /// Used by the CLI compile-check / check-unit / ghost-check commands and the
  /// IDE plugin's live + ghost compile. Not thread-safe (shares no instance
  /// state, but each call spawns a process and reads its pipe synchronously).</remarks>
  TCompileChecker = class
    public
      /// <summary>Compiles ATarget and returns the parsed compiler findings.</summary>
      /// <param name="ATarget">A .dproj (compiled via msbuild) or a .pas/.dpr/.dpk (via dcc64).</param>
      /// <param name="AMsbuildPath">Optional explicit msbuild path; '' uses PATH.</param>
      /// <param name="ARsvarsPath">Optional explicit rsvars.bat; '' uses the default.</param>
      /// <returns>Findings, raw stdout, and the compiler exit code.</returns>
      /// <remarks>Runs an INCREMENTAL compile (msbuild /t:Make; dcc64 without -B):
      /// only changed units and their dependents are recompiled, so it is fast on
      /// large projects. Units that fail to compile lack a valid DCU and are always
      /// re-checked, so current errors are never skipped. Not thread-safe.</remarks>
      class function Run(const ATarget: string; const AMsbuildPath: string = ''; const ARsvarsPath: string = ''): TCompileCheckResult;
      /// <summary>Runs an arbitrary, already-shell-wrapped compiler command line
      /// (a cmd.exe invocation that calls rsvars then dcc and merges stderr) and
      /// parses its findings.</summary>
      /// <param name="ACmd">The full command line to execute.</param>
      /// <returns>Parsed findings, raw output, and the exit code.</returns>
      /// <remarks>Used by check-unit for the single-unit shadow-overlay compile.</remarks>
      class function RunCommand(const ACmd: string): TCompileCheckResult;
      /// <summary>Parses one line of compiler output into a finding.</summary>
      /// <param name="ALine">A single output line.</param>
      /// <param name="AFinding">Receives the parsed finding when the line matches.</param>
      /// <returns>True if the line was a recognized finding.</returns>
      /// <remarks>Recognizes the RAD Studio msbuild dcc wrapper format
      /// (path(line[,col]): severity code: message) and the native dcc64 format
      /// (path(line) Severity: code message).</remarks>
      class function ParseLine(const ALine: string; out AFinding: TCompilerFinding): Boolean;
      /// <summary>Persists findings into the symbol DB, resolving each finding's
      /// path to a files.id where it is indexed (NULL file_id otherwise).</summary>
      /// <param name="AStore">Open symbol store to insert into.</param>
      /// <param name="AFindings">Findings to persist.</param>
      class procedure InsertFindings(const AStore: ISymbolStore; const AFindings: TArray<TCompilerFinding>);
    private
      /// <summary>Spawns ACmd via CreateProcessW with stdout+stderr redirected;
      /// returns the process exit code and the merged output in AOutput.</summary>
      class function SpawnAndCapture(const ACmd: string; out AOutput: string): Integer;
      /// <summary>Canonicalizes a raw severity word (error/fatal/warning/hint/
      /// information) to 'Error'/'Warning'/'Hint'/'Information'.</summary>
      class function NormalizeSeverity(const ARaw: string): string;
  end;

implementation

const
  DEFAULT_RSVARS = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat';

  { TCompileChecker }

  class function TCompileChecker.NormalizeSeverity(const ARaw: string): string;
var
  L: string;
begin
  L:= LowerCase(ARaw);
  if (L = 'error') or (L = 'fatal') then Result:= 'Error'
  else if L = 'warning'     then Result:= 'Warning'
  else if L = 'hint'        then Result:= 'Hint'
  else if L = 'information' then Result:= 'Information'
  else Result:= ARaw;
end;

// Spawn ACmd via CreateProcessW with redirected stdout+stderr.
// Returns process exit code. AOutput receives the merged output.
class function TCompileChecker.SpawnAndCapture(const ACmd: string; out AOutput: string): Integer;
var
  SA       : TSecurityAttributes       ;
  ReadPipe : THandle                   ;
  WritePipe: THandle                   ;
  SI       : TStartupInfoW             ;
  PI       : TProcessInformation       ;
  Buf      : array[0..4095] of AnsiChar;
  BytesRead: DWORD                     ;
  ExitCode : DWORD                     ;
  SB       : TStringBuilder            ;
  WideCmd  : string                    ;
begin
  Result:= -1;
  AOutput:= '';
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then raise Exception.Create('CreatePipe failed');
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput:= GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmd;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      raise Exception.CreateFmt('CreateProcessW failed: %d', [GetLastError]);
    end;
    CloseHandle(WritePipe);
    SB:= TStringBuilder.Create;
    try
      repeat
        BytesRead:= 0;
        if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead]:= #0;
        SB.Append(string(AnsiString(Buf)));
      until False;
      AOutput:= SB.ToString;
    finally
      SB.Free;
    end;
    WaitForSingleObject(PI.hProcess, INFINITE);
    GetExitCodeProcess (PI.hProcess, ExitCode);
    Result:= Integer(ExitCode);
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  finally
    CloseHandle(ReadPipe);
  end; // try
end; // function

class function TCompileChecker.ParseLine(const ALine: string; out AFinding: TCompilerFinding): Boolean;
const
  // dcc64 native: path(line) Severity: [Code] message
  // Example: C:\foo\Bar.pas(42) Warning: W1002 Symbol "Foo" is specific to a platform
  DCC_PATTERN = '^(.+?\.(?:pas|dpr|dpk))\((\d+)\)\s+(Hint|Warning|Error|Fatal|Information):' + '\s*([HWEF]\d+)?\s*(.*)$';

  // msbuild: [indent]path(line[,col]): severity code: message
  // The RAD Studio msbuild dcc wrapper omits the column for most findings and
  // indents the summary copy, e.g.:
  //   Blueprint4.pas(1348): error E2003: Undeclared identifier: 'FOperNames'
  //     Blueprint4.pas(1348): error E2003: ...        (indented duplicate)
  //   C:\foo\Bar.pas(99,5): error E2003: ...          (column sometimes present)
  // So: tolerate leading whitespace, make the column optional, lowercase severity.
  MSB_PATTERN = '^\s*(.+?\.(?:pas|dpr|dpk))\((\d+)(?:,(\d+))?\):\s+' + '(error|warning|hint|fatal|information)\s+([HWEF]\d+):\s+(.*)$';
var
  M: TMatch;
begin
  Result:= False;
  AFinding:= Default(TCompilerFinding);

  // Try msbuild format first (more specific)
  M:= TRegEx.Match(ALine, MSB_PATTERN, [roIgnoreCase]);
  if M.Success then
  begin
    AFinding.RawPath:= M.Groups[1].Value;
    AFinding.LineNo:= StrToIntDef(M.Groups[2].Value, 0);
    AFinding.ColNo := StrToIntDef(M.Groups[3].Value, 0);
    AFinding.Severity:= NormalizeSeverity(M.Groups[4].Value);
    AFinding.Code:= M.Groups[5].Value;
    AFinding.Message:= Trim(M.Groups[6].Value);
    AFinding.FileId:= -1;
    Exit(True);
  end;

  // Try dcc64 native format
  M:= TRegEx.Match(ALine, DCC_PATTERN, [roIgnoreCase]);
  if M.Success then
  begin
    AFinding.RawPath:= M.Groups[1].Value;
    AFinding.LineNo:= StrToIntDef(M.Groups[2].Value, 0);
    AFinding.ColNo:= 0;
    AFinding.Severity:= NormalizeSeverity(M.Groups[3].Value);
    AFinding.Code    := Trim             (M.Groups[4].Value);
    AFinding.Message := Trim             (M.Groups[5].Value);
    AFinding.FileId:= -1;
    Exit(True);
  end;
end; // function

class function TCompileChecker.Run(const ATarget: string; const AMsbuildPath: string = ''; const ARsvarsPath: string = ''): TCompileCheckResult;
var
  RsVars   : string                 ;
  Cmd      : string                 ;
  RawOutput: string                 ;
  Line     : string                 ;
  Lines    : TStringList            ;
  F        : TCompilerFinding       ;
  Findings : TList<TCompilerFinding>;
  Ext      : string                 ;
begin
  Result:= Default(TCompileCheckResult);
  RsVars:= ARsvarsPath;
  if RsVars = '' then RsVars:= DEFAULT_RSVARS;

  Ext:= LowerCase(ExtractFileExt(ATarget));
  if Ext = '.dproj' then
  begin
    { Incremental Compile (/t:Make), NOT a full Build (/t:Build): Make only
      recompiles changed units + their dependents, reusing existing DCUs --
      seconds vs minutes on a large project. A unit that fails to compile has no
      valid DCU, so Make always re-checks it; current errors are never missed. }
    if AMsbuildPath <> '' then Cmd:= Format('cmd.exe /c "call "%s" && "%s" "%s" /v:normal /t:Make /nologo"', [RsVars, AMsbuildPath, ATarget])
    else Cmd:= Format('cmd.exe /c "call "%s" && msbuild "%s" /v:normal /t:Make /nologo"', [RsVars, ATarget]);
  end
  else
  begin
    { -Q quiet, no -B: incremental compile (reuse DCUs), not build-all-units. }
    Cmd:= Format('cmd.exe /c "call "%s" && dcc64 -Q "%s" 2>&1"', [RsVars, ATarget]);
  end;

  Result.ExitCode:= SpawnAndCapture(Cmd, RawOutput);
  Result.StdoutText:= RawOutput;

  Lines:= TStringList.Create;
  Findings:= TList<TCompilerFinding>.Create;
  try
    Lines.Text:= RawOutput;
    for Line in Lines do
      if ParseLine(Line, F) then Findings.Add(F);
    Result.Findings:= Findings.ToArray;
  finally
    Lines.Free;
    Findings.Free;
  end;
end; // function

class function TCompileChecker.RunCommand(const ACmd: string): TCompileCheckResult;
var
  RawOutput: string                 ;
  Line     : string                 ;
  Lines    : TStringList            ;
  F        : TCompilerFinding       ;
  Findings : TList<TCompilerFinding>;
begin
  Result:= Default(TCompileCheckResult);
  Result.ExitCode:= SpawnAndCapture(ACmd, RawOutput);
  Result.StdoutText:= RawOutput;

  Lines:= TStringList.Create;
  Findings:= TList<TCompilerFinding>.Create;
  try
    Lines.Text:= RawOutput;
    for Line in Lines do
      if ParseLine(Line, F) then Findings.Add(F);
    Result.Findings:= Findings.ToArray;
  finally
    Lines.Free;
    Findings.Free;
  end;
end; // function

class procedure TCompileChecker.InsertFindings(const AStore: ISymbolStore; const AFindings: TArray<TCompilerFinding>);
var
  F     : TCompilerFinding;
  FileId: Int64           ;
  Rec   : TCompilerFinding;
begin
  for F in AFindings do
  begin
    Rec:= F;
    // Attempt to resolve file_id from the indexed files table.
    FileId:= AStore.FindFileIdByPath(F.RawPath);
    if FileId > 0 then Rec.FileId:= FileId
    else Rec.FileId:= -1; // not indexed; store with NULL file_id
    AStore.InsertCompilerFinding(Rec);
  end;
end;

end.
