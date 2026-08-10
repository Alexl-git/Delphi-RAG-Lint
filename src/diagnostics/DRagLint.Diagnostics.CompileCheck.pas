unit DRagLint.Diagnostics.CompileCheck;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , System.DateUtils
  , System.Win.Registry
  , Winapi.Windows
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Outcome of one compile run: the parsed findings, the compiler
  /// process exit code (0 = clean), and the raw merged stdout/stderr text (kept
  /// for diagnostics and fallback parsing).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas), DRagLint.CLI.DoGhostCheck (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), declaration (DRagLint.Diagnostics.CompileCheck.pas) (+2 more)
  /// Used in units: DRagLint.CLI, DRagLint.Diagnostics.CompileCheck
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCompileCheckResult = record
    Findings  : TArray<TCompilerFinding>;
    ExitCode  : Integer                 ;
    StdoutText: string                  ;
  end;

  /// <summary>Compiles a Delphi target out-of-process and turns the compiler's
  /// textual output into structured findings.</summary>
  /// <remarks>
  /// Stateless and thin (class methods only): spawn -> capture -> parse.
  /// Used by the CLI compile-check / check-unit / ghost-check commands and the
  /// IDE plugin's live + ghost compile. Not thread-safe (shares no instance
  /// state, but each call spawns a process and reads its pipe synchronously).
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas), DRagLint.CLI.DoGhostCheck (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas) (+1 more)
  /// Used in units: DRagLint.CLI, DRagLint.MCP.Server
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCompileChecker = class
    public
      /// <summary>Compiles ATarget and returns the parsed compiler findings.</summary>
      /// <param name="ATarget">A .dproj (compiled via msbuild) or a .pas/.dpr/.dpk (via dcc64).</param>
      /// <param name="AFullBuild">When True, forces a full rebuild (msbuild /t:Build;
      /// dcc64 with -B) instead of the default incremental compile, so DCC re-emits
      /// hints/warnings for already-up-to-date units too. Defaults to False.</param>
      /// <param name="AMsbuildPath">Optional explicit msbuild path; '' uses PATH.</param>
      /// <param name="ARsvarsPath">Optional explicit rsvars.bat; '' uses the default.</param>
      /// <param name="ATargetPlatform">Optional target platform ('Win32' or 'Win64'); when given,
      /// drives msbuild /p:Platform=&lt;p> and resolves the IDE global Library Path for that
      /// platform (registry Search Path + macro expansion), minimized (compiled-DCU dirs,
      /// dedup, existence-filter) to avoid cmdline overflow, and injected via DCC_UnitSearchPath
      /// env var. Empty string means use the .dproj default (typically Win64).</param>
      /// <returns>Findings, raw stdout, and the compiler exit code.</returns>
      /// <remarks>
      /// By default runs an INCREMENTAL compile (msbuild /t:Make; dcc64
      /// without -B): only changed units and their dependents are recompiled, so it
      /// is fast on large projects. Units that fail to compile lack a valid DCU and
      /// are always re-checked, so current errors are never skipped. Pass
      /// AFullBuild=True to force msbuild /t:Build (or dcc64 -B), recompiling every
      /// unit so findings are reported even for units DCC would otherwise skip as
      /// already up to date. Not thread-safe.
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas), DRagLint.CLI.DoGhostCheck (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
      /// Calls: Default, DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine, DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath, DRagLint.Diagnostics.CompileCheck.TCompileChecker.SpawnAndCapture, ExtractFileExt, Format, LowerCase, PChar, SameText, SetEnvironmentVariable
      /// Returns: Default(TCompileCheckResult)
      /// Complexity: 17 (cyclomatic, outer body), 103 lines (full implementation)
      /// Pure
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.SpawnAndCapture"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Run(const ATarget: string; const AFullBuild: Boolean = False; const AMsbuildPath: string = ''; const ARsvarsPath: string = ''; const ATargetPlatform: string = ''): TCompileCheckResult;
      /// <summary>Runs an arbitrary, already-shell-wrapped compiler command line
      /// (a cmd.exe invocation that calls rsvars then dcc and merges stderr) and
      /// parses its findings.</summary>
      /// <param name="ACmd">The full command line to execute.</param>
      /// <returns>Parsed findings, raw output, and the exit code.</returns>
      /// <remarks>
      /// Used by check-unit for the single-unit shadow-overlay compile.
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas)
      /// Calls: Default, DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine, DRagLint.Diagnostics.CompileCheck.TCompileChecker.SpawnAndCapture
      /// Returns: Default(TCompileCheckResult)
      /// Pure
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.SpawnAndCapture"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function RunCommand(const ACmd: string): TCompileCheckResult;
      /// <summary>Parses one line of compiler output into a finding.</summary>
      /// <param name="ALine">A single output line.</param>
      /// <param name="AFinding">Receives the parsed finding when the line matches.</param>
      /// <returns>True if the line was a recognized finding.</returns>
      /// <remarks>
      /// Recognizes the RAD Studio msbuild dcc wrapper format
      /// (path(line[,col]): severity code: message) and the native dcc64 format
      /// (path(line) Severity: code message).
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run (DRagLint.Diagnostics.CompileCheck.pas), DRagLint.Diagnostics.CompileCheck.TCompileChecker.RunCommand (DRagLint.Diagnostics.CompileCheck.pas)
      /// Calls: Default, DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity, DRagLint.Diagnostics.CompileCheck.TCompileChecker.SeverityFromCode, letter, StrToIntDef, Trim, word
      /// Returns: False; True
      /// Mutates: AFinding (out)
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.SeverityFromCode"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ParseLine(const ALine: string; out AFinding: TCompilerFinding): Boolean;
      /// <summary>Persists findings into the symbol DB, resolving each finding's
      /// path to a files.id where it is indexed (NULL file_id otherwise).</summary>
      /// <param name="AStore">Open symbol store to insert into.</param>
      /// <param name="AFindings">Findings to persist.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.InsertCompilerFinding
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.InsertCompilerFinding"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class procedure InsertFindings(const AStore: ISymbolStore; const AFindings: TArray<TCompilerFinding>);
    private
      /// <summary>Resolve IDE library paths for a given platform from the registry,
      /// minimized to compiled-DCU dirs (deduped and existence-filtered) to fit the
      /// command-line limit. Returns a semicolon-separated path list, or empty if
      /// none found or any error occurs (best-effort).</summary>
      /// <param name="APlatform"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run (DRagLint.Diagnostics.CompileCheck.pas)
      /// Calls: blanked, dirs, DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath.ShortPathOf, filter, flags, GetShortPathName, long, LowerCase, Pos, PWideChar, SetString, StringReplace, Trim, Win32
      /// Complexity: 14 (cyclomatic, outer body), 103 lines (full implementation)
      /// Touches: file system, registry
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath.ShortPathOf"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ResolveIdeLibraryPath(const APlatform: string): string;
      /// <summary>Spawns ACmd via CreateProcessW with stdout+stderr redirected;
      /// optionally applies an environment variable block (for DCC_UnitSearchPath injection);
      /// returns the process exit code and the merged output in AOutput.</summary>
      /// <param name="ACmd"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AEnvBlock"><!-- drag-lint:auto type -->Pointer</param>
      /// <param name="AOutput"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Observed: -1; Integer(ExitCode).</returns>
      /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run (DRagLint.Diagnostics.CompileCheck.pas), DRagLint.Diagnostics.CompileCheck.TCompileChecker.RunCommand (DRagLint.Diagnostics.CompileCheck.pas)
      /// Calls: AnsiString, CloseHandle, CreatePipe, CreateProcessW, FillChar, GetExitCodeProcess, GetStdHandle, Integer, PWideChar, ReadFile, SetHandleInformation, UniqueString, WaitForSingleObject
      /// Mutates: AOutput (out)
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function SpawnAndCapture(const ACmd: string; AEnvBlock: Pointer; out AOutput: string): Integer;
      /// <summary>Canonicalizes a raw severity word (error/fatal/warning/hint/
      /// information) to 'Error'/'Warning'/'Hint'/'Information'.</summary>
      /// <param name="ARaw"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: 'Error'; 'Warning'; 'Hint';
      /// 'Information'; ARaw.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine (DRagLint.Diagnostics.CompileCheck.pas)
      /// Calls: LowerCase
      /// Pure
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.RunCommand"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function NormalizeSeverity(const ARaw: string): string;
      /// <summary><!-- drag-lint:auto -->Maps a DCC message code (e.g. 'H2219', 'W1000',
      /// 'E2003', 'F2613') to its severity WORD via the leading letter -- H-&gt;hint,
      /// W-&gt;warning, E/F-&gt;error. The code letter is authoritative for msbuild lines
      /// like "Hint warning H2219" where the severity word ("warning") disagrees with the
      /// real severity (Hint). Falls back to AFallbackWord when the code is
      /// empty/unrecognized.</summary>
      /// <param name="ACode"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AFallbackWord"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: 'hint'; 'warning'; 'error';
      /// AFallbackWord.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine (DRagLint.Diagnostics.CompileCheck.pas)
      /// Calls: UpCase
      /// Pure
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.NormalizeSeverity"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ParseLine"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.ResolveIdeLibraryPath"/>
      /// <seealso cref="DRagLint.Diagnostics.CompileCheck.TCompileChecker.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function SeverityFromCode(const ACode, AFallbackWord: string): string;
  end;

implementation

const
  DEFAULT_RSVARS = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat';

  { TCompileChecker }

  class function TCompileChecker.ResolveIdeLibraryPath(const APlatform: string): string;
  var
    Reg       : TRegistry;
    Paths     : TStringList;
    SearchPath: string;
    I         : Integer;
    Path      : string;
    Low       : string;
    PlatKey   : string;
    Seen      : TDictionary<string, Boolean>;
    IsCompiled: Boolean;

    { 8.3-shorten a dir; returns the input unchanged if no short name exists
      (e.g. 8dot3 disabled on the volume). Roughly halves each entry's length. }
    function ShortPathOf(const P: string): string;
    var
      Buf: array[0..1023] of WideChar;
      N  : DWORD;
    begin
      N:= GetShortPathName(PWideChar(P), PWideChar(@Buf[0]), Length(Buf));
      if (N > 0) and (N < Length(Buf)) then SetString(Result, PWideChar(@Buf[0]), N)
      else Result:= P;
    end;

  begin
    Result:= '';
    if APlatform = '' then Exit;

    { Query the IDE registry for the global Library Path:
        HKCU\Software\Embarcadero\BDS\37.0\Library\<Platform>\Search Path
      The raw value is long (often 5k+ chars, 90+ entries). msbuild expands it into
      several dcc flags (-U/-I/-R/...), so it is repeated ~4x on the dcc command
      line; injecting it verbatim overflows the ~32k Windows command-line limit
      (MSB6003 "filename or extension too long" -> dcc never runs). To fit, MINIMIZE:
        - expand $(BDS)/$(Platform); blank any other $(NAME) so it drops below;
        - existence-filter (dead dirs only bloat);
        - drop dirs under \Embarcadero\Studio\37.0\ (RAD defaults already on dcc's
          baseline path via rsvars -- re-injecting them is pure duplication);
        - keep compiled library dirs, drop source dirs (their DCUs cover them, and
          source trees -- esp. DevExpress's ~40 \Sources dirs -- dominate the size);
        - 8.3-shorten each entry; dedup case-insensitively, preserving order.
      NOTE: only the two common macros are expanded here; vendor macros like
      $(DXVCL) are blanked (their dirs then drop). Adequate for Win32 (literal
      paths); a fuller expansion would reuse TProjectResolver. }
    Reg:= TRegistry.Create(KEY_READ);
    Paths:= TStringList.Create;
    Seen:= TDictionary<string, Boolean>.Create;
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      PlatKey:= 'Software\Embarcadero\BDS\37.0\Library\' + APlatform;

      if Reg.OpenKey(PlatKey, False) then
      try
        if Reg.ValueExists('Search Path') then
        begin
          SearchPath:= Reg.ReadString('Search Path');
          { Split ONLY on ';' -- StrictDelimiter stops DelimitedText from also
            breaking on the spaces in paths like 'C:\Program Files (x86)\...'. }
          Paths.Delimiter:= ';';
          Paths.StrictDelimiter:= True;
          Paths.DelimitedText:= SearchPath;

          for I:= 0 to Paths.Count - 1 do
          begin
            Path:= Trim(Paths[I]);
            if Path = '' then Continue;

            { Expand the two common macros; blank any remaining $(NAME) so an
              unresolved-macro path becomes invalid and is dropped by the
              existence check below. }
            Path:= StringReplace(Path, '$(BDS)', 'C:\Program Files (x86)\Embarcadero\Studio\37.0', [rfReplaceAll, rfIgnoreCase]);
            Path:= StringReplace(Path, '$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase]);
            Path:= TRegEx.Replace(Path, '\$\([A-Za-z0-9_]+\)', '');

            if not TDirectory.Exists(Path) then Continue;

            Low:= LowerCase(Path);
            { Drop RAD-provided dirs -- already on dcc's baseline search path. }
            if Pos('\embarcadero\studio\37.0\', Low) > 0 then Continue;
            { Keep compiled-DCU library dirs; otherwise drop source trees. }
            IsCompiled:= (Pos('\library\rs', Low) > 0) or (Pos('\library\win', Low) > 0);
            if (not IsCompiled) and ((Pos('\source', Low) > 0) or (Pos('\src', Low) > 0)) then Continue;

            Path:= ShortPathOf(Path);

            { Dedup case-insensitively, preserving first-seen order (dcc uses the
              first match, so order is significant). }
            Low:= LowerCase(Path);
            if Seen.ContainsKey(Low) then Continue;
            Seen.Add(Low, True);

            if Result <> '' then Result:= Result + ';';
            Result:= Result + Path;
          end;
        end;
      finally
        Reg.CloseKey;
      end;
    finally
      Seen.Free;
      Paths.Free;
      Reg.Free;
    end;
  end;

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

// Maps a DCC message code (e.g. 'H2219', 'W1000', 'E2003', 'F2613') to its
// severity WORD via the leading letter -- H->hint, W->warning, E/F->error.
// The code letter is authoritative for msbuild lines like "Hint warning H2219"
// where the severity word ("warning") disagrees with the real severity (Hint).
// Falls back to AFallbackWord when the code is empty/unrecognized.
class function TCompileChecker.SeverityFromCode(const ACode, AFallbackWord: string): string;
begin
  if ACode = '' then Exit(AFallbackWord);
  case UpCase(ACode[1]) of
    'H': Result:= 'hint';
    'W': Result:= 'warning';
    'E', 'F': Result:= 'error';
  else
    Result:= AFallbackWord;
  end;
end;

// Spawn ACmd via CreateProcessW with redirected stdout+stderr.
// AEnvBlock: optional environment variable block (nil = inherit parent process).
// Returns process exit code. AOutput receives the merged output.
class function TCompileChecker.SpawnAndCapture(const ACmd: string; AEnvBlock: Pointer; out AOutput: string): Integer;
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
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, AEnvBlock, nil, SI, PI) then
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
  // CRITICAL: the wrapper emits DCC HINTS with TWO severity words --
  //   uMain.pas(74): Hint warning H2219: Private symbol 'X' declared but never used
  // The leading DCC severity ("Hint ") is optional and precedes the msbuild
  // severity word. Without tolerating it, EVERY hint (H-code) is silently
  // dropped -- so make that first word optional, then derive the true severity
  // from the [HWEF] code letter (authoritative), not the possibly-misleading
  // second word ("warning" in "Hint warning H2219").
  // So: tolerate leading whitespace, an optional leading severity word, and an
  // optional column.
  MSB_PATTERN = '^\s*(.+?\.(?:pas|dpr|dpk))\((\d+)(?:,(\d+))?\):\s+' + '(?:(?:hint|warning|error|fatal|information)\s+)?(error|warning|hint|fatal|information)\s+([HWEF]\d+):\s+(.*)$';
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
    AFinding.Code:= M.Groups[5].Value;
    { Derive severity from the [HWEF] code letter, NOT the severity word: the
      msbuild wrapper writes hints as "Hint warning H2219", where the matched
      word (Group 4) is "warning" but the finding is really a Hint. The code
      letter (H/W/E/F) is authoritative. Fall back to the word if the code is
      somehow empty. }
    AFinding.Severity:= NormalizeSeverity(SeverityFromCode(AFinding.Code, M.Groups[4].Value));
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

class function TCompileChecker.Run(const ATarget: string; const AFullBuild: Boolean = False; const AMsbuildPath: string = ''; const ARsvarsPath: string = ''; const ATargetPlatform: string = ''): TCompileCheckResult;
var
  RsVars   : string                 ;
  Cmd      : string                 ;
  RawOutput: string                 ;
  Line     : string                 ;
  Lines    : TStringList            ;
  F        : TCompilerFinding       ;
  Findings : TList<TCompilerFinding>;
  Ext      : string                 ;
  LibPath  : string                 ;
  Plat     : string                 ;
begin
  Result:= Default(TCompileCheckResult);
  RsVars:= ARsvarsPath;
  if RsVars = '' then RsVars:= DEFAULT_RSVARS;

  { RAD Studio's DCC msbuild task rejects a lower-case platform ("Platform not
    supported:win32", MSB4018) before dcc even runs -- it wants the exact-case
    name. --platform typically arrives lower-cased, so normalize the two Windows
    targets before building /p:Platform. }
  Plat:= ATargetPlatform;
  if SameText(Plat, 'Win32') then Plat:= 'Win32'
  else if SameText(Plat, 'Win64') then Plat:= 'Win64';

  Ext:= LowerCase(ExtractFileExt(ATarget));
  if Ext = '.dproj' then
  begin
    if AFullBuild then
    begin
      { Full Build (/t:Build): recompiles EVERY unit regardless of DCU freshness,
        so DCC re-emits hints/warnings for already-up-to-date units too. Slower
        than Make on a large project; used by refresh-findings to keep
        compiler_findings complete rather than just delta-updated. }
      if AMsbuildPath <> '' then
        if ATargetPlatform <> '' then
          Cmd:= Format('cmd.exe /c "call "%s" && "%s" "%s" /v:normal /t:Build /p:Platform=%s /nologo"', [RsVars, AMsbuildPath, ATarget, Plat])
        else
          Cmd:= Format('cmd.exe /c "call "%s" && "%s" "%s" /v:normal /t:Build /nologo"', [RsVars, AMsbuildPath, ATarget])
      else
        if ATargetPlatform <> '' then
          Cmd:= Format('cmd.exe /c "call "%s" && msbuild "%s" /v:normal /t:Build /p:Platform=%s /nologo"', [RsVars, ATarget, Plat])
        else
          Cmd:= Format('cmd.exe /c "call "%s" && msbuild "%s" /v:normal /t:Build /nologo"', [RsVars, ATarget]);
    end
    else
    begin
      { Incremental Compile (/t:Make), NOT a full Build (/t:Build): Make only
        recompiles changed units + their dependents, reusing existing DCUs --
        seconds vs minutes on a large project. A unit that fails to compile has no
        valid DCU, so Make always re-checks it; current errors are never missed. }
      if AMsbuildPath <> '' then
        if ATargetPlatform <> '' then
          Cmd:= Format('cmd.exe /c "call "%s" && "%s" "%s" /v:normal /t:Make /p:Platform=%s /nologo"', [RsVars, AMsbuildPath, ATarget, Plat])
        else
          Cmd:= Format('cmd.exe /c "call "%s" && "%s" "%s" /v:normal /t:Make /nologo"', [RsVars, AMsbuildPath, ATarget])
      else
        if ATargetPlatform <> '' then
          Cmd:= Format('cmd.exe /c "call "%s" && msbuild "%s" /v:normal /t:Make /p:Platform=%s /nologo"', [RsVars, ATarget, Plat])
        else
          Cmd:= Format('cmd.exe /c "call "%s" && msbuild "%s" /v:normal /t:Make /nologo"', [RsVars, ATarget]);
    end;
  end
  else
  begin
    if AFullBuild then
    begin
      { -B: full build, recompiling every unit so DCC re-emits hints even for
        units it would otherwise treat as already up to date. }
      Cmd:= Format('cmd.exe /c "call "%s" && dcc64 -B -Q "%s" 2>&1"', [RsVars, ATarget]);
    end
    else
    begin
      { -Q quiet, no -B: incremental compile (reuse DCUs), not build-all-units. }
      Cmd:= Format('cmd.exe /c "call "%s" && dcc64 -Q "%s" 2>&1"', [RsVars, ATarget]);
    end;
  end;

  { Resolve and inject IDE library paths if a platform is specified and building a .dproj.
    Set DCC_UnitSearchPath in the current process; it will be inherited by the spawned child.
    The .dproj's DCC_UnitSearchPath property ends with `;$(DCC_UnitSearchPath)`, so the env
    var is appended cleanly without requiring .dproj edits. }
  if (ATargetPlatform <> '') and (Ext = '.dproj') then
  begin
    LibPath:= ResolveIdeLibraryPath(Plat);
    if LibPath <> '' then
      SetEnvironmentVariable(PChar('DCC_UnitSearchPath'), PChar(LibPath));
  end;

  Result.ExitCode:= SpawnAndCapture(Cmd, nil, RawOutput);
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
  Result.ExitCode:= SpawnAndCapture(ACmd, nil, RawOutput);
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
