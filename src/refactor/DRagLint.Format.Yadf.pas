unit DRagLint.Format.Yadf;

{ `drag-lint format` spawns YADF to rewrite a .pas IN PLACE. That makes this the
  only verb in the engine that can destroy the user's work, and until 2026-09-16
  it had NO test coverage anywhere under tests\ and no safety net of any kind.

  Four things were true at once, each individually survivable and together not:

  1. Resolution fell back to TWO HARDCODED WIN32 PATHS -- Win32\Release\EXE\
     YADF.exe and Win32\Debug\EXE\YADF.exe under C:\Projects\YADF. (Written
     without brace-brackets on purpose: a literal closing brace inside a brace
     comment ENDS THE COMMENT, and the prose after it compiles as code. That is
     how this very file first failed to build.) YADF has never been
     built Win32; every real build is Win64. They were dead code that could
     never resolve -- while each carried a `dl:ok hardcoded-absolute-path`
     review reading "an existence-checked dev-box fallback, never the only
     source". That review justified precisely the mechanism that made the
     original defect silent, which is why the constants are DELETED here rather
     than repointed: any hardcoded absolute path re-creates the same failure the
     day the layout moves.
  2. NO VERSION GATE. A YADF old enough to split inline var declarations
     rewrote sources happily.
  3. NO WAY TO LOOK BEFORE LEAPING. `--dry-run` PARSED (it is a global flag) and
     was then IGNORED by DoFormat -- so a user who typed the flag specifically
     to avoid touching the file had it rewritten anyway. `--diff` did not exist.
  4. NO VERIFICATION. A formatter that corrupted the file reported success and
     left the corruption on disk.

  THE VERSION GATE READS THE EXE'S VERSION RESOURCE, NOT `--version`.
  Measured 2026-09-16: `YADF.exe --version` exits 2 with "unknown option
  --version (run yadf --help for the flag list)". The probe the plan proposed is
  not buildable. The version resource needs no cooperation from YADF and costs
  no subprocess.

  AN ABSENT VERSION RESOURCE IS NOT A REFUSAL. A wrapper script has none, and
  refusing everything unverifiable would break `--yadf-path` for no safety gain:
  the real protection is the post-format verification, which runs regardless of
  version. Unknown proceeds with a warning; known-and-too-old is refused. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , Winapi.Windows
  ;

type
  /// <summary>Raised for a failure inside the format pipeline itself (the
  /// target file is missing, a pipe or process could not be created).</summary>
  /// <remarks>A named class rather than a bare <c>Exception</c> so a caller can
  /// handle a formatter problem without also swallowing every unrelated
  /// error -- `raise-bare-exception` is a warning in this repo, and on a verb
  /// that rewrites source it is the difference between "formatting failed" and
  /// "something, somewhere, failed".</remarks>
  EYadfFormatError = class(Exception);

  /// <summary>What `format` should DO once it has resolved and vetted a
  /// formatter.</summary>
  /// <remarks>
  /// <para><c>fmApply</c> rewrites the file (with backup + verification).
  /// <c>fmDryRun</c> resolves, version-checks, reports, and writes nothing --
  /// the scriptable "what would happen" mode. <c>fmDiff</c> formats a COPY and
  /// emits a diff against the original, writing nothing.</para>
  /// <para>Both non-apply modes are kept even though fmDiff subsumes fmDryRun
  /// for a human reader: fmDryRun is the one a script can branch on without
  /// parsing a diff.</para>
  /// </remarks>
  TFormatMode = (fmApply, fmDryRun, fmDiff);

  /// <summary>Outcome of one `format` invocation.</summary>
  /// <remarks>
  /// <para><c>ExitCode</c> distinguishes the refusal REASONS, because "it did
  /// not format" is not actionable on its own. 0 is success; every failure is
  /// one of the named <c>FMT_*</c> constants below -- <c>FMT_SPAWN_ERROR</c>,
  /// <c>FMT_TIMEOUT</c>, <c>FMT_NO_YADF</c>, <c>FMT_BELOW_FLOOR</c> (nothing
  /// was written) and <c>FMT_VERIFY_FAILED</c> (the file was restored).</para>
  /// <para><c>ResolvedPath</c> and <c>YadfVersion</c> are filled whenever they
  /// are known, including on a refusal -- an operator debugging a refusal needs
  /// to see WHICH binary was rejected, which was exactly what the old
  /// single-line failure could not tell them.</para>
  /// </remarks>
  TFormatResult = record
    ExitCode    : Integer;
    StdoutText  : string ;
    Success     : Boolean;
    ResolvedPath: string ;
    YadfVersion : string ;
    DiffText    : string ;
  end;

  /// <summary>Resolves, vets and runs YADF over a single Delphi source file.
  /// </summary>
  /// <remarks>Every entry point is a class function; the type holds no state.
  /// Not thread-safe with respect to the file it is rewriting.</remarks>
  TYadfFormatter = class  // dl:ok high-response@30e2 -- RFC 70 is dominated by SpawnAndCapture's WinAPI call list (CreatePipe/CreateProcessW/ReadFile/WaitForSingleObject); one cohesive operation that splitting would only obscure
    public
      /// <summary>Resolve a YADF, refuse it if too old, then apply / dry-run /
      /// diff it over AFile.</summary>
      /// <param name="AFile">Source file to format. Must exist.</param>
      /// <param name="AYadfPath">Explicit formatter path; when '' the registry
      /// is consulted. There is no hardcoded fallback -- see the unit
      /// header.</param>
      /// <param name="AMode">Apply, dry-run or diff. Only fmApply writes.</param>
      /// <returns>The outcome; see TFormatResult.ExitCode for the reason
      /// codes.</returns>
      /// <exception cref="Exception">AFile does not exist.</exception>
      /// <remarks>
      /// <para>In fmApply the file is backed up, formatted, then RE-PARSED and
      /// compared against the pre-format parse by symbol fingerprint. On
      /// divergence the backup is restored and -5 returned. A formatter is
      /// allowed to change every byte of layout; it is not allowed to change
      /// what the unit DECLARES.</para>
      /// <para>Touches the file system and the registry.</para>
      /// </remarks>
      class function Format(const AFile: string; const AYadfPath: string = '';
                            AMode: TFormatMode = fmApply): TFormatResult;

      /// <summary>The YADF path from HKCU\Software\YADF\ExePath, or ''.</summary>
      /// <returns>An existing file path, or '' when the value is unset, empty
      /// or names a file that is not there.</returns>
      /// <remarks>REGISTRY ONLY, deliberately. The two hardcoded Win32
      /// fallbacks this used to carry are deleted -- see the unit header for
      /// why repointing them was rejected.</remarks>
      class function FindYadfPath: string;

      /// <summary>FileVersion from AExePath's version resource.</summary>
      /// <param name="AExePath">Any file; need not be an exe.</param>
      /// <returns>'a.b.c.d', or '' when the file carries no version resource
      /// (a .bat wrapper, for instance).</returns>
      class function ReadFileVersion(const AExePath: string): string;

      /// <summary>Compares two dotted version strings numerically.</summary>
      /// <returns>&lt;0, 0 or &gt;0. Missing components read as 0, so '1.0'
      /// and '1.0.0.0' compare equal.</returns>
      class function CompareVersionStr(const A, B: string): Integer;
    private
      /// <summary>Kind+qualified-name fingerprint of everything ASource
      /// declares, sorted.</summary>
      /// <remarks>The qualified name carries the parent chain, so this one
      /// string per symbol covers names, kinds AND nesting. Returns nil when
      /// the source does not parse at all, which the caller must distinguish
      /// from "parsed to nothing".</remarks>
      class function SymbolFingerprint(const ASource: TBytes; const AFilePath: string;
                                       out AOk: Boolean): TArray<string>;
      /// <summary>First divergence between two fingerprints, as display text,
      /// or '' when they match.</summary>
      class function FirstDivergence(const ABefore, AAfter: TArray<string>): string;
      /// <summary>A unified-ish diff of two texts.</summary>
      /// <remarks>NOT a minimal-edit diff: it trims the common prefix and
      /// suffix and prints the differing span between them. That is enough to
      /// see what a formatter did, and avoids carrying an LCS implementation
      /// for a display-only feature.</remarks>
      class function SimpleDiff(const ABefore, AAfter, ALabel: string): string;
      class function SpawnAndCapture(const ACmd: string; ATimeoutMs: DWORD; out AOutput: string): Integer;
  end;

const
  /// <summary>The oldest YADF `format` will run.</summary>
  /// <remarks>1.0.6.6 is the release that fixed the inline-var split
  /// (2026-06-14). Below it, YADF silently rewrites
  /// `var A, B: Integer;` into something that no longer compiles the same way,
  /// which is the whole reason this gate exists.</remarks>
  YADF_MIN_VERSION = '1.0.6.6';

  { The TFormatResult.ExitCode vocabulary, named rather than spelled as bare
    negative literals at each assignment. `magic-literal` flagged five of them
    and was right to: -4 and -5 carry the two refusals a caller most needs to
    distinguish, and a reader tracing an exit code should not have to infer
    which is which from surrounding prose. }
  { Read-buffer size for the formatter's captured stdout. Named because
    large-magic-number flagged the bare 4096, and a buffer size is exactly
    the kind of number a reader should not have to guess the units of. }
  PIPE_BUF_BYTES = 4096;

  FMT_SPAWN_ERROR   = -1; /// <summary>The formatter could not be launched, or its output could not be read.</summary>
  FMT_TIMEOUT       = -2; /// <summary>The formatter did not exit within the timeout and was terminated.</summary>
  FMT_NO_YADF       = -3; /// <summary>No usable YADF resolved from --yadf-path or the registry.</summary>
  FMT_BELOW_FLOOR   = -4; /// <summary>The resolved YADF is older than YADF_MIN_VERSION. Nothing was written.</summary>
  FMT_VERIFY_FAILED = -5; /// <summary>Formatting changed what the unit declares. The original was restored.</summary>

implementation

uses
  System.Win.Registry
  , DRagLint.Core.Interfaces
  , DRagLint.Parser.Delphi13
  ;

{ TYadfFormatter }

class function TYadfFormatter.FindYadfPath: string;
const
  REGISTRY_KEY = 'Software\YADF';
  REGISTRY_VAL = 'ExePath';
var
  Reg    : TRegistry;
  RegPath: string   ;
begin
  Result := '';
  RegPath:= '';
  Reg:= TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REGISTRY_KEY) then
    begin
      if Reg.ValueExists(REGISTRY_VAL) then RegPath:= Trim(Reg.ReadString(REGISTRY_VAL));
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
  if (RegPath <> '') and TFile.Exists(RegPath) then Result:= RegPath;
end; // function

class function TYadfFormatter.ReadFileVersion(const AExePath: string): string;
var
  Sz     : DWORD  ;
  Dummy  : DWORD  ;
  Buf    : TBytes ;
  Fixed  : PVSFixedFileInfo;
  Len    : UINT   ;
begin
  Result:= '';
  if not TFile.Exists(AExePath) then Exit;
  Dummy:= 0;
  Sz:= GetFileVersionInfoSizeW(PWideChar(AExePath), Dummy);
  if Sz = 0 then Exit; { no version resource -- a .bat, or an exe built without one }
  SetLength(Buf, Sz);
  if not GetFileVersionInfoW(PWideChar(AExePath), 0, Sz, @Buf[0]) then Exit;
  Fixed:= nil;
  Len  := 0;
  if not VerQueryValueW(@Buf[0], '\', Pointer(Fixed), Len) then Exit;
  if (Fixed = nil) or (Len = 0) then Exit;
  Result:= System.SysUtils.Format('%d.%d.%d.%d',
    [HiWord(Fixed.dwFileVersionMS), LoWord(Fixed.dwFileVersionMS),
     HiWord(Fixed.dwFileVersionLS), LoWord(Fixed.dwFileVersionLS)]);
end; // function

class function TYadfFormatter.CompareVersionStr(const A, B: string): Integer;
var
  PA, PB: TArray<string>;
  I, NA, NB, Count: Integer;
begin
  PA:= A.Split(['.']);
  PB:= B.Split(['.']);
  Count:= Length(PA);
  if Length(PB) > Count then Count:= Length(PB);
  for I:= 0 to Count - 1 do
  begin
      NA:= 0;
    NB:= 0;
    if (I < Length(PA)) then TryStrToInt(Trim(PA[I]), NA);
    if (I < Length(PB)) then TryStrToInt(Trim(PB[I]), NB);
    if NA < NB then Exit(-1);
    if NA > NB then Exit( 1);
  end;
  Result:= 0;
end; // function

class function TYadfFormatter.SymbolFingerprint(const ASource: TBytes; const AFilePath: string;
  out AOk: Boolean): TArray<string>;
var
  Parser: IParser     ;
  PR    : TParseResult;
  L     : TStringList ;
begin
  AOk:= False;
  SetLength(Result, 0);
  try
    Parser:= TDelphi13Parser.Create;
    PR    := Parser.Parse(ASource, AFilePath);
  except  // dl:ok try-except-swallowed@e6d0 -- a parse failure IS the result here: AOk stays False and the caller treats "no fingerprint" as distinct from "no symbols". Re-raising would crash the verb on any unparseable file
    { A parse that THROWS is not a fingerprint of zero symbols -- it is no
      fingerprint at all, and the caller must not read the two as equal. AOk
      stays False, which is the signal; the exception itself carries nothing
      the caller can act on, and letting it escape would turn "this file does
      not parse" into a crash of the whole verb. }
    on E: Exception do Exit;
  end;
  L:= TStringList.Create;
  try
    for var S in PR.Symbols do
      L.Add(IntToStr(Ord(S.Kind)) + '|' + S.QualifiedName);
    L.Sort;
    Result:= L.ToStringArray;
    AOk   := True;
  finally
    L.Free;
  end;
end; // function

class function TYadfFormatter.FirstDivergence(const ABefore, AAfter: TArray<string>): string;
var
  I, N: Integer;
begin
  Result:= '';
  N:= Length(ABefore);
  if Length(AAfter) < N then N:= Length(AAfter);
  for I:= 0 to N - 1 do
    if ABefore[I] <> AAfter[I] then
      Exit(System.SysUtils.Format('first divergence at #%d: before=<%s> after=<%s>',
        [I, ABefore[I], AAfter[I]]));
  if Length(ABefore) > Length(AAfter) then
    Exit(System.SysUtils.Format('%d symbol(s) LOST, first missing: <%s>',
      [Length(ABefore) - Length(AAfter), ABefore[N]]));
  if Length(AAfter) > Length(ABefore) then
    Exit(System.SysUtils.Format('%d symbol(s) APPEARED, first new: <%s>',
      [Length(AAfter) - Length(ABefore), AAfter[N]]));
end; // function

class function TYadfFormatter.SimpleDiff(const ABefore, AAfter, ALabel: string): string;
var
  A, B: TArray<string>;
  Head, TailA, TailB, I: Integer;
  Sb: TStringBuilder;
begin
  A:= ABefore.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  B:= AAfter .Replace(#13#10, #10).Replace(#13, #10).Split([#10]);

  Head:= 0;
  while (Head < Length(A)) and (Head < Length(B)) and (A[Head] = B[Head]) do Inc(Head);

  TailA:= Length(A) - 1;
  TailB:= Length(B) - 1;
  while (TailA >= Head) and (TailB >= Head) and (A[TailA] = B[TailB]) do
  begin
    Dec(TailA);
    Dec(TailB);
  end;

  Sb:= TStringBuilder.Create;
  try
    Sb.AppendLine('--- ' + ALabel + ' (current)');
    Sb.AppendLine('+++ ' + ALabel + ' (formatted)');
    if (TailA < Head) and (TailB < Head) then
    begin
      Sb.AppendLine('@@ no change @@');
      Exit(Sb.ToString);
    end;
    Sb.AppendLine(System.SysUtils.Format('@@ -%d,%d +%d,%d @@',
      [Head + 1, TailA - Head + 1, Head + 1, TailB - Head + 1]));
    for I:= Head to TailA do Sb.AppendLine('-' + A[I]);
    for I:= Head to TailB do Sb.AppendLine('+' + B[I]);
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end; // function

class function TYadfFormatter.SpawnAndCapture(const ACmd: string; ATimeoutMs: DWORD; out AOutput: string): Integer;
var
  SA        : TSecurityAttributes;
  ReadPipe  : THandle            ;
  WritePipe : THandle            ;
  SI        : TStartupInfoW      ;
  PI        : TProcessInformation;
  Buf       : array[0..PIPE_BUF_BYTES - 1] of AnsiChar;
  BytesRead : DWORD              ;
  ExitCode  : DWORD              ;
  SB        : TStringBuilder     ;
  WideCmd   : string             ;
  WaitResult: DWORD              ;
begin
  Result := FMT_SPAWN_ERROR;
  AOutput:= '';

  FillChar(SA, SizeOf(SA), 0);
  SA.nLength             := SizeOf(SA);
  SA.bInheritHandle      := True;
  SA.lpSecurityDescriptor:= nil ;

  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then raise EYadfFormatError.Create('CreatePipe failed');
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);

    FillChar(SI, SizeOf(SI), 0);
    SI.cb         := SizeOf(SI);
    SI.dwFlags    := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow:= SW_HIDE;
    SI.hStdOutput := WritePipe;
    SI.hStdError  := WritePipe;
    SI.hStdInput  := GetStdHandle(STD_INPUT_HANDLE);

    WideCmd:= ACmd;
    UniqueString(WideCmd);

    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True,
                          CREATE_NO_WINDOW, nil, nil, SI, PI) then
      raise EYadfFormatError.CreateFmt('CreateProcessW failed: %d', [GetLastError]);

    CloseHandle(WritePipe);
    WritePipe:= 0;

    SB:= TStringBuilder.Create;
    try
      while ReadFile(ReadPipe, Buf, SizeOf(Buf), BytesRead, nil) and (BytesRead > 0) do
        SB.Append(string(AnsiString(Copy(PAnsiChar(@Buf[0]), 1, BytesRead))));
      AOutput:= SB.ToString;
    finally
      SB.Free;
    end;

    WaitResult:= WaitForSingleObject(PI.hProcess, ATimeoutMs);
    if WaitResult = WAIT_TIMEOUT then
    begin
      TerminateProcess(PI.hProcess, 1);
      Result:= FMT_TIMEOUT;
    end
    else if GetExitCodeProcess(PI.hProcess, ExitCode) then
      Result:= Integer(ExitCode);

    CloseHandle(PI.hThread );
    CloseHandle(PI.hProcess);
  finally
    if ReadPipe  <> 0 then CloseHandle(ReadPipe );
    if WritePipe <> 0 then CloseHandle(WritePipe);
  end;
end; // function

class function TYadfFormatter.Format(const AFile: string; const AYadfPath: string = '';  // dl:ok too-many-exit-points@5d31 -- all ten are GUARD CLAUSES (not-found, below-floor, dry-run, diff, spawn failure, verification failure), which is the remedy the rule itself recommends; consolidating them into nested ifs would bury the refusal paths this verb exists to make obvious
  AMode: TFormatMode = fmApply): TFormatResult;
const
  TIMEOUT_MS = 30000;
var
  ResolvedYadf: string ;
  Cmd         : string ;
  Output      : string ;
  ExitCode    : Integer;
  Ver         : string ;
  TargetFile  : string ;
  BackupFile  : string ;
  BeforeBytes : TBytes ;
  BeforeText  : string ;
  WorkDir     : string ;
begin
  Result.ExitCode    := FMT_SPAWN_ERROR;
  Result.StdoutText  := '';
  Result.Success     := False;
  Result.ResolvedPath:= '';
  Result.YadfVersion := '';
  Result.DiffText    := '';

  if not TFile.Exists(AFile) then raise EYadfFormatError.CreateFmt('File not found: %s', [AFile]);

  if AYadfPath <> '' then ResolvedYadf:= AYadfPath
  else ResolvedYadf:= FindYadfPath;

  { ONE not-found message for both routes. The old code had two, and the one
    that fired for an explicit --yadf-path named neither the registry nor the
    flag -- so an operator whose path was a typo was told the file was missing
    and nothing about how resolution actually works. }
  if (ResolvedYadf = '') or (not TFile.Exists(ResolvedYadf)) then
  begin
    if ResolvedYadf = '' then
      Result.StdoutText:= 'YADF.exe not found. Pass --yadf-path <path>, or set HKCU\Software\YADF\ExePath in the registry.'
    else
      Result.StdoutText:= System.SysUtils.Format(
        'YADF.exe not found at: %s. Pass a --yadf-path that exists, or set HKCU\Software\YADF\ExePath in the registry.',
        [ResolvedYadf]);
    Result.ExitCode    := FMT_NO_YADF;
    Result.ResolvedPath:= ResolvedYadf;
    Exit;
  end;

  Result.ResolvedPath:= ResolvedYadf;
  Ver:= ReadFileVersion(ResolvedYadf);
  Result.YadfVersion := Ver;

  { THE GATE. A KNOWN too-old version is refused before anything is spawned, so
    nothing is written. An UNKNOWN version (no resource -- a wrapper script)
    proceeds with a warning: refusing it would break --yadf-path for no gain,
    because the post-format verification below is what actually protects the
    file. }
  if (Ver <> '') and (CompareVersionStr(Ver, YADF_MIN_VERSION) < 0) then
  begin
    Result.StdoutText:= System.SysUtils.Format(
      'refusing to run YADF %s at %s -- below the required minimum %s. '
      + 'That release predates the inline-var split fix, so it can rewrite a unit into something that no longer means the same thing. '
      + 'Nothing was written. Point --yadf-path (or HKCU\Software\YADF\ExePath) at %s or newer.',
      [Ver, ResolvedYadf, YADF_MIN_VERSION, YADF_MIN_VERSION]);
    Result.ExitCode:= FMT_BELOW_FLOOR;
    Exit;
  end;

  BeforeBytes:= TFile.ReadAllBytes(AFile);
  BeforeText := TEncoding.ANSI.GetString(BeforeBytes);

  if AMode = fmDryRun then
  begin
    Result.StdoutText:= System.SysUtils.Format(
      'DRY RUN -- nothing written.'#13#10'  formatter : %s'#13#10'  version   : %s'#13#10'  would run : "%s" "%s"',
      [ResolvedYadf, (if Ver <> '' then Ver else '(no version resource)'), ResolvedYadf, AFile]);
    Result.ExitCode:= 0;
    Result.Success := True;
    Exit;
  end;

  { fmDiff formats a COPY in a scratch directory so the original is never even
    opened for writing -- "writes nothing" is a property of the code path, not a
    promise to restore afterwards. }
  if AMode = fmDiff then
  begin
    WorkDir   := TPath.Combine(TPath.GetTempPath, 'draglint-fmt-' + TGuid.NewGuid.ToString.Replace('{','').Replace('}',''));
    TDirectory.CreateDirectory(WorkDir);
    try
      TargetFile:= TPath.Combine(WorkDir, TPath.GetFileName(AFile));
      TFile.WriteAllBytes(TargetFile, BeforeBytes);
      Cmd:= System.SysUtils.Format('"%s" "%s"', [ResolvedYadf, TargetFile]);
      try
        ExitCode:= SpawnAndCapture(Cmd, TIMEOUT_MS, Output);
      except
        on E: Exception do
        begin
          Result.StdoutText:= 'Spawn error: ' + E.Message;
          Exit;
        end;
      end;
      if ExitCode <> 0 then
      begin
        Result.ExitCode  := ExitCode;
        Result.StdoutText:= Output;
        Exit;
      end;
      Result.DiffText  := SimpleDiff(BeforeText, TEncoding.ANSI.GetString(TFile.ReadAllBytes(TargetFile)), AFile);
      Result.StdoutText:= Result.DiffText;
      Result.ExitCode  := 0;
      Result.Success   := True;
    finally
      { Best-effort scratch cleanup. A failure here leaves a temp directory and
        changes nothing the caller can see or act on, and re-raising would turn
        a successful --diff into a failure over a leftover folder. }
      try
        TDirectory.Delete(WorkDir, True);
      except  // dl:ok try-except-swallowed@6cec -- best-effort cleanup of our own temp/backup file; the exception carries nothing actionable and re-raising would fail an otherwise successful run
        on E: Exception do ; // dl:ok empty-except, empty-on-handler@1c60 -- scratch dir under GetTempPath; a leak is harmless and re-raising would fail a successful diff
      end;
    end;
    Exit;
  end;

  { fmApply. Backup FIRST: the restore path must exist before the thing that
    might need it runs. }
  BackupFile:= AFile + '.drag-lint-bak';
  TFile.Copy(AFile, BackupFile, True);
  try
    Cmd:= System.SysUtils.Format('"%s" "%s"', [ResolvedYadf, AFile]);
    try
      ExitCode:= SpawnAndCapture(Cmd, TIMEOUT_MS, Output);
    except
      on E: Exception do
      begin
        Result.StdoutText:= 'Spawn error: ' + E.Message;
        TFile.Copy(BackupFile, AFile, True);
        Exit;
      end;
    end;

    if ExitCode <> 0 then
    begin
      TFile.Copy(BackupFile, AFile, True);
      Result.ExitCode  := ExitCode;
      Result.StdoutText:= Output;
      Exit;
    end;

    { THE VERIFICATION. A formatter may change every byte of layout; it may not
      change what the unit DECLARES. Comparing the symbol fingerprint is what
      turns a corrupting formatter from a bug report into a refusal.

      A pre-parse that FAILS disables the check rather than failing the run:
      the file was already unparseable before we touched it, so we have no
      baseline to compare against and refusing would block formatting exactly
      the files most in need of it. A post-parse failure, by contrast, IS a
      corruption signal, because the pre-parse succeeded. }
    var OkBefore, OkAfter: Boolean;
    var FpBefore: TArray<string>:= SymbolFingerprint(BeforeBytes, AFile, OkBefore);
    var AfterBytes: TBytes      := TFile.ReadAllBytes(AFile);
    var FpAfter  : TArray<string>:= SymbolFingerprint(AfterBytes, AFile, OkAfter);

    if OkBefore and (not OkAfter) then
    begin
      TFile.Copy(BackupFile, AFile, True);
      Result.ExitCode  := FMT_VERIFY_FAILED;
      Result.StdoutText:= System.SysUtils.Format(
        'post-format verification FAILED for %s: the file parsed before formatting and does NOT parse after. '
        + 'The original has been restored; nothing was lost. Formatter: %s (%s).',
        [AFile, ResolvedYadf, (if Ver <> '' then Ver else 'no version resource')]);
      Exit;
    end;

    if OkBefore and OkAfter then
    begin
      var Diverged: string:= FirstDivergence(FpBefore, FpAfter);
      if Diverged <> '' then
      begin
        TFile.Copy(BackupFile, AFile, True);
        Result.ExitCode  := FMT_VERIFY_FAILED;
        Result.StdoutText:= System.SysUtils.Format(
          'post-format verification FAILED for %s: the set of declared symbols CHANGED (%s). '
          + 'A formatter may rewrite layout, never declarations. The original has been restored; nothing was lost. Formatter: %s (%s).',
          [AFile, Diverged, ResolvedYadf, (if Ver <> '' then Ver else 'no version resource')]);
        Exit;
      end;
    end;

    Result.ExitCode  := ExitCode;
    Result.StdoutText:= Output;
    if (Ver = '') then
      Result.StdoutText:= Result.StdoutText
        + #13#10'warning: could not read a version from ' + ResolvedYadf
        + ' -- the minimum-version gate could not be applied. Post-format verification still ran.';
    Result.Success:= True;
  finally
    { ACT FIRST, do not stat-then-delete. `stat-gated-destructive` flagged the
      TFile.Exists gate this used to have, and on a DIFFERENT path that rule is
      about data loss; here the risk is the mirror image -- a failed stat (a
      network blip, a permission change) answers False, the delete is skipped,
      and a stale .drag-lint-bak is left beside the user's source looking like
      a real file. Deleting unconditionally and ignoring the "not there" error
      leaves nothing behind either way. }
    try
      TFile.Delete(BackupFile);
    except  // dl:ok try-except-swallowed@6cec -- best-effort cleanup of our own temp/backup file; the exception carries nothing actionable and re-raising would fail an otherwise successful run
      on E: Exception do ; // dl:ok empty-except, empty-on-handler@1c60 -- deleting OUR OWN backup; already-gone is the common case and nothing downstream reads it
    end;
  end;
end; // function

end.
