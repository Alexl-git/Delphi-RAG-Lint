unit DRagLint.Doc.GitSince;

{ AutoDocument (ADF T5) -- the <since> doc-source's ISOLATED git helper.

  Derives a YYYY-MM-DD date for a declaration line from git, for the OPT-IN
  /// <since> tag. This is the milestone's ONE external dependency (git), so it
  is quarantined here behind a single class function whose contract is:

    * Returns 'YYYY-MM-DD' ONLY when git CONFIDENTLY attributes the line.
    * Returns '' in EVERY failure mode -- git not installed / not on PATH, the
      file untracked / not in a repo, a non-zero exit, empty or unparseable
      output, OR any exception in the spawn / parse. NEVER a guessed or stale
      date. ABSENCE OVER A WRONG FACT (the milestone's no-fabrication rule).

  The whole body is wrapped in try/except -> '' so no git failure can ever crash
  the documenter or leak a partial result. The git subprocess is a cost, so the
  CALLER runs this ONLY when the --since opt-in is set (TDocBatchOptions
  .IncludeSince); when --since is off no spawn happens.

  Spawn idiom: CreateProcessW + a single redirected stdout pipe with a BOUNDED
  timeout (WaitForSingleObject with GIT_TIMEOUT_MS; a timed-out child is
  TerminateProcess'd and treated as a failure -> ''). Modeled on
  DRagLint.Diagnostics.CompileCheck.TCompileChecker.SpawnAndCapture, but
  time-boxed (that one waits INFINITE) and self-contained (returns '' instead of
  raising). }

interface

type
  TGitSince = class
  public
    /// <summary>Authoring date of the commit that INTRODUCED the declaration
    /// at line ALine (1-based) of AFile, as 'YYYY-MM-DD'. Runs
    /// <c>git -C ARepoDir blame --line-porcelain --contents AFile -L ALine,ALine
    /// HEAD -- &lt;file&gt;</c> with a bounded timeout and parses the porcelain
    /// author-time/author-tz.</summary>
    /// <param name="ARepoDir">Repo root passed to <c>git -C</c>. '' -&gt; the
    /// file's own directory (so git discovers the enclosing repo, if any).</param>
    /// <param name="AFile">Path to the WORKING-TREE source file. Passed to git
    /// via --contents so the blame maps ALine to HEAD even when the working tree
    /// has UNCOMMITTED edits above it (e.g. a just-inserted doc-comment) -- this
    /// is what makes the &lt;since&gt; date idempotent across apply+reindex.</param>
    /// <param name="ALine">1-based declaration line to attribute.</param>
    /// <returns>'YYYY-MM-DD' on a confident attribution; '' on ANY failure
    /// (no git, untracked file, uncommitted line, non-zero exit, empty/
    /// unparseable output, timeout, or exception). NEVER a guessed or wrong
    /// date.</returns>
    /// <remarks>Degrades silently: absence over a wrong fact. Spawns a git
    /// subprocess -- the caller must gate this behind the --since opt-in so a
    /// batch run without --since never pays the per-decl process cost.
    /// IDEMPOTENCY: --contents blames the WORKING-TREE line against HEAD's
    /// history, so a declaration keeps its introducing-commit date even after
    /// document --apply inserts comment lines above it; author-time (not the
    /// drifting committer-time) is used, so re-committing the fixture never
    /// changes the emitted date.</remarks>
    class function FirstCommitDate(const ARepoDir, AFile: string; ALine: Integer): string;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  System.RegularExpressions, Winapi.Windows;

const
  // Bounded timeout for the git spawn (ms). A well-behaved `git log -L` on one
  // line returns in a few ms; this cap protects against a hung/paging child.
  GIT_TIMEOUT_MS = 5000;

// Spawns ACmd via CreateProcessW with stdout+stderr redirected into one pipe,
// waits up to GIT_TIMEOUT_MS, and returns the exit code (AOutput = merged
// output). A timed-out child is terminated and reported as -1. Raises on a spawn
// setup failure (no git on PATH -> CreateProcessW fails); the caller catches it.
function SpawnGit(const ACmd: string; out AOutput: string): Integer;
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
  WaitRes  : DWORD                     ;
begin
  Result := -1;
  AOutput:= '';
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then raise Exception.Create('CreatePipe failed');
  try
    // Read end must not be inherited by the child, or the pipe never EOFs.
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmd;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      raise Exception.CreateFmt('CreateProcessW failed: %d', [GetLastError]);
    end;
    // Close the parent's write end so the read loop EOFs when git exits.
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
    // Bounded wait: a git that overruns GIT_TIMEOUT_MS is killed and treated as
    // a failure (-1) so the caller degrades to '' rather than blocking.
    WaitRes:= WaitForSingleObject(PI.hProcess, GIT_TIMEOUT_MS);
    if WaitRes = WAIT_OBJECT_0 then
    begin
      if GetExitCodeProcess(PI.hProcess, ExitCode) then Result:= Integer(ExitCode)
      else Result:= -1;
    end
    else
    begin
      TerminateProcess(PI.hProcess, 1);
      Result:= -1;
    end;
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  finally
    CloseHandle(ReadPipe);
  end; // try
end; // function

// Parses git blame --line-porcelain output for the introducing commit's
// AUTHOR date, returning 'YYYY-MM-DD'. Reads 'author-time <epoch>' and
// 'author-tz <+HHMM>' and formats the author's LOCAL date (epoch + tz offset,
// rendered UTC) to match git's own --date=short. '' on ANY of: missing
// author-time, a zero/absent epoch (a 'Not Committed Yet' line), an unparseable
// value. Never a guessed date -- absence over a wrong fact.
function ParsePorcelainAuthorDate(const AOutput: string): string;
var
  Lines    : TArray<string>;
  Ln       : string        ;
  AuthEpoch: Int64         ;
  TzStr    : string        ;
  TzSign   : Integer       ;
  TzHours  : Integer       ;
  TzMins   : Integer       ;
  TzSeconds: Int64         ;
  HaveTime : Boolean       ;
  DT       : TDateTime     ;
begin
  Result   := '';
  AuthEpoch:= 0;
  TzStr    := '+0000';
  HaveTime := False;
  Lines := AOutput.Replace(#13#10, #10, [rfReplaceAll]).Replace(#13, #10, [rfReplaceAll]).Split([#10]);
  for Ln in Lines do
  begin
    if Ln.StartsWith('author-time ') then
    begin
      if TryStrToInt64(Trim(Copy(Ln, Length('author-time ') + 1, MaxInt)), AuthEpoch) then
        HaveTime := True;
    end
    else if Ln.StartsWith('author-tz ') then
      TzStr := Trim(Copy(Ln, Length('author-tz ') + 1, MaxInt));
  end;
  if (not HaveTime) or (AuthEpoch <= 0) then Exit; // no commit / not-committed-yet

  // Parse the tz as +HHMM / -HHMM; default +0000 on any deviation.
  TzSeconds:= 0;
  if (Length(TzStr) = 5) and ((TzStr[1] = '+') or (TzStr[1] = '-')) then
  begin
    if TzStr[1] = '-' then TzSign := -1 else TzSign := 1;
    if TryStrToInt(Copy(TzStr, 2, 2), TzHours) and TryStrToInt(Copy(TzStr, 4, 2), TzMins) then
      TzSeconds := TzSign * (Int64(TzHours) * 3600 + Int64(TzMins) * 60);
  end;

  // Author's local wall-clock = epoch + tz offset, rendered as a UTC date so no
  // machine-local timezone leaks in (deterministic, idempotent).
  DT := UnixDateDelta + (AuthEpoch + TzSeconds) / SecsPerDay;
  Result := FormatDateTime('yyyy-mm-dd', DT);
  // Final shape guard: only a well-formed date survives.
  if not TRegEx.IsMatch(Result, '^\d{4}-\d{2}-\d{2}$') then Result := '';
end;

class function TGitSince.FirstCommitDate(const ARepoDir, AFile: string; ALine: Integer): string;
var
  RepoDir : string ;
  GitFile : string ;
  Cmd     : string ;
  Output  : string ;
  ExitCode: Integer;
begin
  // Absence over a wrong fact: ANY failure below -> ''. The whole body is
  // wrapped so no git/OS error can escape as an exception or a partial date.
  Result := '';
  try
    if (AFile = '') or (ALine <= 0) then Exit;

    // Repo root for `git -C`. '' -> the file's own directory, so git discovers
    // the enclosing repo (if any); a non-repo dir simply makes git exit non-zero.
    RepoDir := ARepoDir;
    if RepoDir = '' then RepoDir := System.SysUtils.ExtractFileDir(AFile);
    if RepoDir = '' then RepoDir := System.SysUtils.GetCurrentDir;

    // The path git sees: file name relative to RepoDir (git -C makes the pathspec
    // relative to it). Quoting guards spaces. Also used as the --contents path so
    // the blame reconciles the WORKING-TREE line offsets against HEAD.
    GitFile := System.SysUtils.ExtractFileName(AFile);
    if GitFile = '' then Exit;

    // git -C <repo> blame --line-porcelain --contents <workingfile> -L n,n HEAD -- <file>
    // --contents supplies the current working-tree file so git maps ALine (which
    // may sit below UNCOMMITTED doc-comment inserts) back to the HEAD commit that
    // introduced it -- this keeps <since> idempotent across document --apply. The
    // --line-porcelain output carries 'author-time <epoch>' + 'author-tz <+HHMM>'
    // for the introducing commit; we format that as the author's local date.
    Cmd := Format('git -C "%s" blame --line-porcelain --contents "%s" -L %d,%d HEAD -- "%s"',
      [RepoDir, AFile, ALine, ALine, GitFile]);

    ExitCode := SpawnGit(Cmd, Output);
    if ExitCode <> 0 then Exit;              // no git repo / untracked / git error
    if Trim(Output) = '' then Exit;          // no output -> nothing

    // Parse 'author-time <epoch>' and 'author-tz <+HHMM>' from the porcelain. If
    // either is missing/unparseable, degrade to '' (never a guessed date). The
    // line was blamed to 'Not Committed Yet' (a zero/absent author-time) -> '' too.
    Result := ParsePorcelainAuthorDate(Output);
    // Result is either 'YYYY-MM-DD' or '' -- absence over a wrong fact.
  except
    Result := '';                            // ANY exception -> silent degradation
  end;
end;

end.
