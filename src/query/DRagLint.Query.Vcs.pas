unit DRagLint.Query.Vcs;

{ drag-lint 1.56 -- lane VCS-1: the changed-lines API of gap-plan S4: which lines of which files changed since a
  revision, in an hg or a git working copy; it refuses instead of guessing.
  DRagLint.CLI.ChangedSince is its first caller (lint-all --changed-since).

  What "changed since <rev>" means here, for both tools alike:
    * the working copy as it is on disk NOW (committed, staged and uncommitted edits together) against <rev>;
    * a line that was added or modified is changed; a deletion changes no line of the new file;
    * a file that <rev> does not hold -- added, renamed to this name, or not yet tracked and not ignored --
      is changed on every line. A rename is never detected by similarity: that would be a guess;
    * an ignored file is not changed.
  The unit runs `git` / `hg` from PATH, reads their output and writes nothing: no index refresh
  (GIT_OPTIONAL_LOCKS=0), no user diff settings (explicit git options; HGPLAIN=1).
  Every failure is a refusal with a reason: no working copy, two of them in one folder, a tool that does not
  start, a revision the tool does not know, a revset that names several revisions, or tool output this unit
  cannot read. The change counts of S4 (G-41) are not built in 1.56; ReadCommitLog (G-46) lists the commits and their files. }

interface

uses
  System.SysUtils;

type
  /// <summary>The version control tool a working copy belongs to.</summary>
  TVcsKind = (vkNone, vkGit, vkHg);

  /// <summary>One working copy: the tool and the folder that holds its .git or .hg.</summary>
  TVcsWorkingCopy = record
    /// <summary>vkGit or vkHg once FindWorkingCopy answered True; vkNone otherwise.</summary>
    Kind: TVcsKind;
    /// <summary>The absolute root folder, without a trailing path delimiter.</summary>
    Root: string;
  end;

  /// <summary>A run of changed lines in the file as it is on disk; 1-based, both ends included.</summary>
  TVcsLineRange = record
    /// <summary>The first changed line.</summary>
    First: Integer;
    /// <summary>The last changed line; never below First.</summary>
    Last: Integer;
  end;

  /// <summary>One file with changed lines.</summary>
  TVcsChangedFile = record
    /// <summary>The absolute path, with backslashes, in the spelling the tool reported.</summary>
    Path: string;
    /// <summary>True for a file the tool does not track yet: every line counts as changed and Ranges is
    /// empty.</summary>
    WholeFile: Boolean;
    /// <summary>The changed runs, ascending and disjoint; empty when WholeFile is True.</summary>
    Ranges: TArray<TVcsLineRange>;
  end;

  /// <summary>The lines of a working copy that changed since one revision. Read-only answer of
  /// ChangedLinesSince; frozen for later consumers (gap-plan S4).</summary>
  /// <remarks>Reference-counted; holds no handle and no process. Not thread-safe to build, safe to read from
  /// several threads once returned.</remarks>
  IVcsChangedLines = interface
    ['{6B1F3C52-9A4E-4D07-8E21-5C7A90B3D4F1}']
    /// <summary>The working copy the answer was read from.</summary>
    /// <returns>Kind and root folder.</returns>
    function WorkingCopy: TVcsWorkingCopy;
    /// <summary>The revision as the caller wrote it.</summary>
    /// <returns>The text given to ChangedLinesSince.</returns>
    function Revision: string;
    /// <summary>The one changeset the revision names.</summary>
    /// <returns>The tool's full hexadecimal id.</returns>
    function RevisionId: string;
    /// <summary>Every file with at least one changed line, in the order the tool reported them (tracked
    /// files first, then the files not tracked yet).</summary>
    /// <returns>A copy of the list; empty when nothing changed.</returns>
    function Files: TArray<TVcsChangedFile>;
    /// <summary>Whether a path lies inside the working copy's root folder.</summary>
    /// <param name="pPath">A file path; relative paths are read against the current directory. Compared
    /// without regard to case or slash direction.</param>
    /// <returns>True when the path is under the root.</returns>
    function InWorkingCopy(const pPath: string): Boolean;
    /// <summary>Whether any line of a span changed since the revision.</summary>
    /// <param name="pPath">The file, as for InWorkingCopy.</param>
    /// <param name="pFirstLine">The first line of the span, 1-based.</param>
    /// <param name="pLastLine">The last line of the span; a value below pFirstLine means the one line
    /// pFirstLine.</param>
    /// <returns>True when the span overlaps a changed run, or the file is not tracked yet; False for an
    /// unchanged span, an unchanged file and a file outside the working copy.</returns>
    function IsChanged(const pPath: string; pFirstLine, pLastLine: Integer): Boolean;
  end;

/// <summary>The tool's name as the user types it.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>'git', 'hg', or 'none'.</returns>
function VcsKindName(pKind: TVcsKind): string;

/// <summary>Finds the working copy a folder belongs to: the nearest folder, from pStartFolder upwards, that
/// holds a .git (folder or file) or a .hg folder.</summary>
/// <param name="pStartFolder">The folder to start in; relative paths are read against the current
/// directory.</param>
/// <param name="pCopy">The working copy when the result is True; Kind = vkNone otherwise.</param>
/// <param name="pRefusal">Why not, as a clause without a final period; '' when the result is True.</param>
/// <returns>False when the folder does not exist, when no parent holds a .git or .hg, and when the nearest
/// such folder holds BOTH (the tool is not chosen for the user).</returns>
/// <remarks>Reads the file system only; starts no process.</remarks>
function FindWorkingCopy(const pStartFolder: string; out pCopy: TVcsWorkingCopy; out pRefusal: string): Boolean;

/// <summary>Asks the tool which single changeset a revision names.</summary>
/// <param name="pCopy">A working copy FindWorkingCopy returned.</param>
/// <param name="pRevision">A revision as the tool reads it (hash, tag, branch, HEAD~3, an hg revset).</param>
/// <param name="pRevisionId">The full hexadecimal id when the result is True.</param>
/// <param name="pRefusal">Why not, as a clause without a final period; '' when the result is True.</param>
/// <returns>False when the text cannot be passed safely (empty, a leading '-', a double quote, a control
/// character, a trailing backslash), the tool does not start, the tool does not know the revision, or an hg
/// revset names no or several changesets.</returns>
/// <remarks>Runs one `git rev-parse` or `hg log`; read-only.</remarks>
function ResolveRevision(const pCopy: TVcsWorkingCopy; const pRevision: string; out pRevisionId: string;
  out pRefusal: string): Boolean;

/// <summary>Reads which lines of the working copy changed since a revision (see the unit header for what
/// counts as changed).</summary>
/// <param name="pCopy">A working copy FindWorkingCopy returned.</param>
/// <param name="pRevision">The revision, as for ResolveRevision.</param>
/// <param name="pChanged">The answer when the result is True; nil otherwise.</param>
/// <param name="pRefusal">Why not, as a clause without a final period; '' when the result is True.</param>
/// <returns>False for every reason ResolveRevision refuses, and when the tool's diff or file list fails or has
/// a shape this unit cannot read. Never a partial answer.</returns>
/// <remarks>Runs the tool three times (revision, diff, files not tracked yet); read-only on the working copy
/// and its repository. Sets GIT_OPTIONAL_LOCKS / HGPLAIN in this process's environment.</remarks>
function ChangedLinesSince(const pCopy: TVcsWorkingCopy; const pRevision: string; out pChanged: IVcsChangedLines;
  out pRefusal: string): Boolean;

type
  /// <summary>One file a commit touched, as the tool lists it (no rename detection: a rename is a deletion
  /// plus an addition).</summary>
  TVcsCommitFile = record
    /// <summary>The absolute path, with backslashes.</summary>
    Path: string;
    /// <summary>'A' added, 'M' modified, 'D' deleted.</summary>
    Status: Char;
  end;

  /// <summary>One non-merge commit and the files it touched.</summary>
  TVcsCommit = record
    /// <summary>The tool's full hexadecimal id.</summary>
    Id: string;
    /// <summary>The files, in the order the tool listed them.</summary>
    Files: TArray<TVcsCommitFile>;
  end;

/// <summary>Reads the non-merge commits of a working copy that came after a point in its history, with the
/// files each touched (the input of co-change counting, G-46).</summary>
/// <param name="pCopy">A working copy FindWorkingCopy returned.</param>
/// <param name="pSince">'' = the whole history; 'YYYY-MM-DD' = commits from that day on (the tool's local
/// time); anything else is a revision as for ResolveRevision, and the commits AFTER it (it is excluded).</param>
/// <param name="pCommits">The commits, in the tool's order, when the result is True; empty otherwise.</param>
/// <param name="pRefusal">Why not, as a clause without a final period; '' when the result is True.</param>
/// <returns>False for every reason ResolveRevision refuses, and when the tool's log fails or has a shape this
/// unit cannot read. Never a partial answer.</returns>
/// <remarks>Runs the tool once (twice for a revision); read-only. Renames are never detected by similarity.</remarks>
function ReadCommitLog(const pCopy: TVcsWorkingCopy; const pSince: string; out pCommits: TArray<TVcsCommit>;
  out pRefusal: string): Boolean;

implementation
uses
  System.Classes, System.Generics.Collections, Winapi.Windows;

const
  GIT_MARKER = '.git';
  HG_MARKER = '.hg';
  DEV_NULL = '/dev/null';
  NEW_SIDE_PREFIX = 'b/';
  READ_CHUNK = 65536;
  MIN_ID_LENGTH = 40; { a git SHA-1 and an hg node are 40 hex digits; a git SHA-256 is longer }
  BYTE_LF = 10;
  BYTE_CR = 13;
  BYTE_TAB = 9;
  MAX_PATH_LONG = 32768; { the longest path Windows returns, in characters }
  GIT_BASE = 'git -c core.quotepath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false ';
  GIT_RESOLVE = GIT_BASE + 'rev-parse --verify --quiet "%s^{commit}"';
  GIT_DIFF = GIT_BASE + 'diff --no-color --no-ext-diff --no-textconv --no-renames --ignore-submodules --unified=0 ' +
    '--src-prefix=a/ --dst-prefix=b/ %s --';
  GIT_UNTRACKED = GIT_BASE + 'ls-files --others --exclude-standard';
  HG_RESOLVE = 'hg log -r "%s" --template "{node}\n"';
  HG_DIFF = 'hg diff -r %s --unified 0 --nodates --config diff.git=false --config diff.noprefix=false';
  HG_UNTRACKED = 'hg status --unknown --no-status';

type
  TDiffSide = (dsNone, dsDeleted, dsFile);

  TVcsChangedLines = class(TInterfacedObject, IVcsChangedLines)
  private
    FCopy: TVcsWorkingCopy;
    FRevision: string;
    FRevisionId: string;
    FFiles: TArray<TVcsChangedFile>;
    FIndex: TDictionary<string, Integer>;
    FRootKey: string;
  public
    constructor Create(const pCopy: TVcsWorkingCopy; const pRevision, pRevisionId: string);
    destructor Destroy; override;
    function AddFile(const pRelativePath: string): Integer;
    procedure AddRange(pFile, pFirst, pCount: Integer);
    procedure MarkWhole(pFile: Integer);
    function WorkingCopy: TVcsWorkingCopy;
    function Revision: string;
    function RevisionId: string;
    function Files: TArray<TVcsChangedFile>;
    function InWorkingCopy(const pPath: string): Boolean;
    function IsChanged(const pPath: string; pFirstLine, pLastLine: Integer): Boolean;
  end;

function PathKey(const pPath: string): string;
begin
  Result:= StringReplace(pPath, '/', '\', [rfReplaceAll]);
  try
    Result:= ExpandFileName(Result);
  except
    on E: Exception do Result:= StringReplace(pPath, '/', '\', [rfReplaceAll]); { unparseable: compared as given }
  end;
  if Result.Contains('~') then { an 8.3 short name (a TEMP folder) and its long form are one path }
  begin
    var Long: string;
    SetLength(Long, MAX_PATH_LONG);
    var Got: Cardinal:= GetLongPathNameW(PWideChar(Result), PWideChar(Long), MAX_PATH_LONG);
    if (Got > 0) and (Got < MAX_PATH_LONG) then Result:= Copy(Long, 1, Got);
  end;
  Result:= LowerCase(Result);
end;

{ TVcsChangedLines }

constructor TVcsChangedLines.Create(const pCopy: TVcsWorkingCopy; const pRevision, pRevisionId: string);
begin
  inherited Create;
  FCopy:= pCopy;
  FRevision:= pRevision;
  FRevisionId:= pRevisionId;
  FIndex:= TDictionary<string, Integer>.Create;
  FRootKey:= IncludeTrailingPathDelimiter(PathKey(pCopy.Root));
end;

destructor TVcsChangedLines.Destroy;
begin
  FIndex.Free;
  inherited;
end;

function TVcsChangedLines.AddFile(const pRelativePath: string): Integer;
begin
  var Full: string:= IncludeTrailingPathDelimiter(FCopy.Root) + StringReplace(pRelativePath, '/', '\', [rfReplaceAll]);
  var Key: string:= PathKey(Full);
  if FIndex.TryGetValue(Key, Result) then Exit;
  Result:= Length(FFiles);
  SetLength(FFiles, Result + 1);
  FFiles[Result].Path:= Full;
  FFiles[Result].WholeFile:= False;
  FFiles[Result].Ranges:= nil;
  FIndex.Add(Key, Result);
end;

procedure TVcsChangedLines.AddRange(pFile, pFirst, pCount: Integer);
begin
  var Range: TVcsLineRange;
  Range.First:= pFirst;
  Range.Last:= pFirst + pCount - 1;
  if (pFile < 0) or (pFile > High(FFiles)) then Exit;
  FFiles[pFile].Ranges:= FFiles[pFile].Ranges + [Range];
end;

procedure TVcsChangedLines.MarkWhole(pFile: Integer);
begin
  if (pFile < 0) or (pFile > High(FFiles)) then Exit;
  FFiles[pFile].WholeFile:= True;
  FFiles[pFile].Ranges:= nil;
end;

function TVcsChangedLines.WorkingCopy: TVcsWorkingCopy;
begin
  Result:= FCopy;
end;

function TVcsChangedLines.Revision: string;
begin
  Result:= FRevision;
end;

function TVcsChangedLines.RevisionId: string;
begin
  Result:= FRevisionId;
end;

function TVcsChangedLines.Files: TArray<TVcsChangedFile>;
begin
  Result:= Copy(FFiles);
end;

function TVcsChangedLines.InWorkingCopy(const pPath: string): Boolean;
begin
  Result:= (pPath <> '') and PathKey(pPath).StartsWith(FRootKey);
end;

function TVcsChangedLines.IsChanged(const pPath: string; pFirstLine, pLastLine: Integer): Boolean;
begin
  Result:= False;
  var At: Integer;
  if (pPath = '') or not FIndex.TryGetValue(PathKey(pPath), At) then Exit;
  if FFiles[At].WholeFile then Exit(True);
  var Last: Integer:= if pLastLine < pFirstLine then pFirstLine else pLastLine;
  for var Range: TVcsLineRange in FFiles[At].Ranges do
    if (Range.First <= Last) and (Range.Last >= pFirstLine) then Exit(True);
end;

{ the tool process }

/// <summary>Runs one command line in a folder and collects its standard output as bytes.</summary>
/// <param name="pCommand">The whole command line; the program is searched on PATH.</param>
/// <param name="pFolder">The working directory of the child.</param>
/// <param name="pWithErrors">True: standard error lands in the same bytes; False: it is discarded.</param>
/// <param name="pOutput">Everything the child wrote.</param>
/// <param name="pExitCode">The child's exit code.</param>
/// <param name="pStartError">The Windows error when the process did not start.</param>
/// <returns>False when the process could not be started.</returns>
/// <remarks>The child reads NUL, so it can never wait for input. Waits for the child without a time limit:
/// a diff of a large working copy has no honest upper bound.</remarks>
function RunTool(const pCommand, pFolder: string; pWithErrors: Boolean; out pOutput: TBytes; out pExitCode: Integer;
  out pStartError: Cardinal): Boolean;
var
  Security: TSecurityAttributes;
  ReadEnd, WriteEnd, NulHandle: THandle;
  Startup: TStartupInfoW;
  Process: TProcessInformation;
begin
  Result:= False;
  pOutput:= nil;
  pExitCode:= -1;
  pStartError:= 0;
  Security.nLength:= SizeOf(Security);
  Security.bInheritHandle:= True;
  Security.lpSecurityDescriptor:= nil;
  NulHandle:= CreateFileW('NUL', GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @Security,
    OPEN_EXISTING, 0, 0);
  if NulHandle = INVALID_HANDLE_VALUE then
  begin
    pStartError:= GetLastError;
    Exit;
  end;
  try
    if not CreatePipe(ReadEnd, WriteEnd, @Security, 0) then
    begin
      pStartError:= GetLastError;
      Exit;
    end;
    try
      SetHandleInformation(ReadEnd, HANDLE_FLAG_INHERIT, 0); { an inherited read end keeps the pipe open for ever }
      FillChar(Startup, SizeOf(Startup), 0);
      Startup.cb:= SizeOf(Startup);
      Startup.dwFlags:= STARTF_USESTDHANDLES;
      Startup.hStdInput:= NulHandle;
      Startup.hStdOutput:= WriteEnd;
      Startup.hStdError:= if pWithErrors then WriteEnd else NulHandle;
      FillChar(Process, SizeOf(Process), 0);
      var CommandLine: string:= pCommand;
      UniqueString(CommandLine);
      var Started: Boolean:= CreateProcessW(nil, PWideChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW, nil,
        PWideChar(pFolder), Startup, Process);
      if not Started then pStartError:= GetLastError;
      CloseHandle(WriteEnd); { the parent's copy: the read loop ends when the child's copy closes }
      WriteEnd:= 0;
      if not Started then Exit;
      try
        var Collected: TBytesStream:= TBytesStream.Create;
        try
          var Chunk: TBytes;
          SetLength(Chunk, READ_CHUNK);
          var Got: DWORD:= 0;
          while ReadFile(ReadEnd, Chunk[0], READ_CHUNK, Got, nil) and (Got > 0) do
            Collected.WriteBuffer(Chunk[0], Got);
          pOutput:= Copy(Collected.Bytes, 0, Collected.Size);
        finally
          Collected.Free;
        end;
        WaitForSingleObject(Process.hProcess, INFINITE);
        var Code: DWORD:= 0;
        if GetExitCodeProcess(Process.hProcess, Code) then pExitCode:= Integer(Code);
        Result:= True;
      finally
        CloseHandle(Process.hProcess);
        CloseHandle(Process.hThread);
      end;
    finally
      if WriteEnd <> 0 then CloseHandle(WriteEnd);
      CloseHandle(ReadEnd);
    end;
  finally
    CloseHandle(NulHandle);
  end;
end;

/// <summary>Decodes tool output: git writes UTF-8 (core.quotepath=false), hg the ANSI code page.</summary>
function DecodeBytes(const pBytes: TBytes; pFirst, pCount: Integer; pKind: TVcsKind): string;
begin
  if pCount <= 0 then Exit('');
  if pKind = vkGit then
    try
      Exit(TEncoding.UTF8.GetString(pBytes, pFirst, pCount));
    except
      on E: EEncodingError do Result:= ''; { not UTF-8: read as ANSI below }
    end;
  Result:= TEncoding.ANSI.GetString(pBytes, pFirst, pCount);
end;

/// <summary>The first non-empty line of tool output, for a refusal.</summary>
function FirstLine(const pBytes: TBytes; pKind: TVcsKind): string;
begin
  Result:= '';
  for var Line: string in DecodeBytes(pBytes, 0, Length(pBytes), pKind).Split([#10]) do
    if Trim(Line) <> '' then Exit(Trim(Line));
end;

/// <summary>Makes the tool read-only and deaf to the user's own settings, for every child of this process:
/// git takes no optional lock (no index refresh), hg ignores aliases, defaults and diff options.</summary>
procedure PrepareEnvironment(pKind: TVcsKind);
begin
  if pKind = vkGit then SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0')
  else SetEnvironmentVariable('HGPLAIN', '1');
end;

function IsHexId(const pText: string): Boolean;
begin
  Result:= Length(pText) >= MIN_ID_LENGTH;
  for var Ch: Char in pText do
    if not CharInSet(Ch, ['0'..'9', 'a'..'f', 'A'..'F']) then Exit(False);
end;

/// <summary>Runs one tool command for a working copy; a start failure or a non-zero exit is a refusal.</summary>
function RunFor(const pCopy: TVcsWorkingCopy; const pCommand, pWhat: string; out pOutput: TBytes;
  out pRefusal: string): Boolean;
begin
  pRefusal:= '';
  var ExitCode: Integer;
  var StartError: Cardinal;
  PrepareEnvironment(pCopy.Kind);
  if not RunTool(pCommand, pCopy.Root, False, pOutput, ExitCode, StartError) then
  begin
    pRefusal:= Format('%s could not be started in %s (Windows error %d; is it on PATH?)',
      [VcsKindName(pCopy.Kind), pCopy.Root, StartError]);
    Exit(False);
  end;
  if ExitCode <> 0 then
  begin
    pRefusal:= Format('%s could not read %s of the working copy %s (exit code %d)',
      [VcsKindName(pCopy.Kind), pWhat, pCopy.Root, ExitCode]);
    Exit(False);
  end;
  Result:= True;
end;

{ the unified diff }

function StartsWithAscii(const pBytes: TBytes; pFirst, pCount: Integer; const pPrefix: AnsiString): Boolean;
begin
  Result:= pCount >= Length(pPrefix);
  if not Result then Exit;
  for var i: Integer:= 1 to Length(pPrefix) do
    if pBytes[pFirst + i - 1] <> Ord(pPrefix[i]) then Exit(False);
end;

/// <summary>Reads '-a[,b] +c[,d]' out of a hunk header '@@ -a,b +c,d @@'; an absent count is 1.</summary>
function ParseHunkHeader(const pHeader: string; out pOldCount, pNewFirst, pNewCount: Integer): Boolean;
const
  HEADER_WORDS = 4; { '@@', the old side, the new side, '@@' }
  SIDE_PARTS = 2; { first line and count }

  function ReadSide(const pSide: string; pSign: Char; out pFirst, pCount: Integer): Boolean;
  begin
    pFirst:= 0;
    pCount:= 1;
    Result:= (pSide <> '') and (pSide[1] = pSign);
    if not Result then Exit;
    var Parts: TArray<string>:= pSide.Substring(1).Split([',']);
    var HasCount: Boolean:= Length(Parts) = SIDE_PARTS;
    Result:= ((Length(Parts) = 1) or HasCount) and TryStrToInt(Parts[0], pFirst) and (pFirst >= 0);
    if Result and HasCount then Result:= TryStrToInt(Parts[1], pCount) and (pCount >= 0);
  end;

begin
  var Words: TArray<string>:= pHeader.Split([' ']);
  var OldFirst: Integer;
  Result:= (Length(Words) >= HEADER_WORDS) and (Words[0] = '@@') and (Words[HEADER_WORDS - 1].StartsWith('@@'))
    and ReadSide(Words[1], '-', OldFirst, pOldCount) and ReadSide(Words[2], '+', pNewFirst, pNewCount);
end;

/// <summary>Adds the changed runs of a zero-context unified diff to the answer.</summary>
/// <returns>False with pRefusal when the diff has a shape this routine does not know; never a partial
/// reading.</returns>
/// <remarks>Only header lines are decoded. A hunk's body is skipped by its counted lines, so source text that
/// begins with '+++ ' or '@@ ' is never read as a header, and source bytes in any code page are harmless.</remarks>
function ReadDiff(const pDiff: TBytes; pInto: TVcsChangedLines; out pRefusal: string): Boolean;
var
  Kind: TVcsKind;
  Side: TDiffSide;
  Current, OldLeft, NewLeft, LineNo: Integer;

  function Refuse(const pWhy: string): Boolean;
  begin
    pRefusal:= Format('the %s diff could not be read at its line %d (%s)', [VcsKindName(Kind), LineNo, pWhy]);
    Result:= False;
  end;

  function ReadBodyLine(pFirst, pCount: Integer): Boolean;
  begin
    Result:= True;
    var Mark: Char:= ' '; { an empty line is an empty context line }
    if pCount > 0 then Mark:= Chr(pDiff[pFirst]);
    case Mark of
      '-': Dec(OldLeft);
      '+': Dec(NewLeft);
      ' ':
        begin
          Dec(OldLeft);
          Dec(NewLeft);
        end;
      '\': ; { "\ No newline at end of file" }
    else
      Result:= False;
    end;
    if (OldLeft < 0) or (NewLeft < 0) then Result:= False;
  end;

  function ReadNewSide(pFirst, pCount: Integer): Boolean;
  const
    PREFIX_LENGTH = 4; { '+++ ' }
  begin
    var Name: string:= DecodeBytes(pDiff, pFirst + PREFIX_LENGTH, pCount - PREFIX_LENGTH, Kind);
    var Tab: Integer:= Pos(Chr(BYTE_TAB), Name);
    if Tab > 0 then Name:= Copy(Name, 1, Tab - 1);
    if Name = DEV_NULL then
    begin
      Side:= dsDeleted;
      Exit(True);
    end;
    if not Name.StartsWith(NEW_SIDE_PREFIX) or (Length(Name) = Length(NEW_SIDE_PREFIX)) then
      Exit(Refuse('a file name without the b/ prefix'));
    Side:= dsFile;
    Current:= pInto.AddFile(Copy(Name, Length(NEW_SIDE_PREFIX) + 1, MaxInt));
    Result:= True;
  end;

  function ReadHunk(pFirst, pCount: Integer): Boolean;
  begin
    var NewFirst, NewCount: Integer;
    if not ParseHunkHeader(DecodeBytes(pDiff, pFirst, pCount, Kind), OldLeft, NewFirst, NewCount) then
    begin
      OldLeft:= 0;
      Exit(Refuse('a hunk header that is not @@ -a,b +c,d @@'));
    end;
    NewLeft:= NewCount;
    if Side = dsNone then Exit(Refuse('a hunk before any file name'));
    if (Side = dsFile) and (NewCount > 0) then pInto.AddRange(Current, NewFirst, NewCount);
    Result:= True;
  end;

begin
  Result:= True;
  pRefusal:= '';
  Kind:= pInto.WorkingCopy.Kind;
  Side:= dsNone;
  Current:= -1;
  OldLeft:= 0;
  NewLeft:= 0;
  LineNo:= 0;
  var At: Integer:= 0;
  var Total: Integer:= Length(pDiff);
  while At < Total do
  begin
    var Stop: Integer:= At;
    while (Stop < Total) and (pDiff[Stop] <> BYTE_LF) do Inc(Stop);
    var Count: Integer:= Stop - At;
    if (Count > 0) and (pDiff[At + Count - 1] = BYTE_CR) then Dec(Count);
    Inc(LineNo);
    if (OldLeft > 0) or (NewLeft > 0) then
    begin
      if not ReadBodyLine(At, Count) then Exit(Refuse('a hunk body that does not match its header'));
    end
    else if StartsWithAscii(pDiff, At, Count, 'diff ') then Side:= dsNone
    else if StartsWithAscii(pDiff, At, Count, '+++ ') and not ReadNewSide(At, Count) then Exit(False)
    else if StartsWithAscii(pDiff, At, Count, '@@ ') and not ReadHunk(At, Count) then Exit(False);
    At:= Stop + 1;
  end;
  if (OldLeft > 0) or (NewLeft > 0) then Result:= Refuse('a hunk that ends before its counted lines');
end;

/// <summary>Marks every listed path (one per line, relative to the root) as changed on every line.</summary>
procedure ReadUntracked(const pList: TBytes; pInto: TVcsChangedLines);
begin
  var Text: string:= DecodeBytes(pList, 0, Length(pList), pInto.WorkingCopy.Kind);
  for var Line: string in Text.Split([#10]) do
  begin
    var Name: string:= Line.TrimRight([#13]);
    if Name <> '' then pInto.MarkWhole(pInto.AddFile(Name));
  end;
end;

{ the public surface }

function VcsKindName(pKind: TVcsKind): string;
begin
  case pKind of
    vkGit: Result:= 'git';
    vkHg: Result:= 'hg';
  else
    Result:= 'none';
  end;
end;

function FindWorkingCopy(const pStartFolder: string; out pCopy: TVcsWorkingCopy; out pRefusal: string): Boolean;
begin
  Result:= False;
  pCopy.Kind:= vkNone;
  pCopy.Root:= '';
  pRefusal:= '';
  var Start: string:= ExcludeTrailingPathDelimiter(ExpandFileName(pStartFolder));
  if not DirectoryExists(Start) then
  begin
    pRefusal:= Format('the folder %s does not exist', [Start]);
    Exit;
  end;
  var Folder: string:= Start;
  repeat
    var GitHere: string:= IncludeTrailingPathDelimiter(Folder) + GIT_MARKER;
    var HasGit: Boolean:= DirectoryExists(GitHere) or FileExists(GitHere); { a linked worktree has a .git FILE }
    var HasHg: Boolean:= DirectoryExists(IncludeTrailingPathDelimiter(Folder) + HG_MARKER);
    if HasGit and HasHg then
    begin
      pRefusal:= Format('the folder %s holds both a .git and a .hg, and the tool is not chosen for you', [Folder]);
      Exit;
    end;
    if HasGit or HasHg then
    begin
      pCopy.Kind:= if HasGit then vkGit else vkHg;
      pCopy.Root:= Folder;
      Exit(True);
    end;
    var Parent: string:= ExtractFileDir(Folder);
    if (Parent = '') or SameText(Parent, Folder) then Break;
    Folder:= Parent;
  until False;
  pRefusal:= Format('the folder %s is under no version control (no .git or .hg in it or in any parent folder)',
    [Start]);
end;

/// <summary>Whether a revision can be put between double quotes on a command line unchanged.</summary>
function IsPassableRevision(const pRevision: string): Boolean;
begin
  Result:= (pRevision <> '') and (pRevision = Trim(pRevision)) and (pRevision[1] <> '-')
    and (pRevision[Length(pRevision)] <> '\');
  for var Ch: Char in pRevision do
    if (Ch < ' ') or (Ch = '"') then Exit(False);
end;

/// <summary>Reads the one changeset id out of the tool's answer to the revision question.</summary>
/// <returns>False with pRefusal when the tool failed, or named no or several changesets.</returns>
function PickRevisionId(const pCopy: TVcsWorkingCopy; const pRevision: string; const pOutput: TBytes;
  pExitCode: Integer; out pRevisionId: string; out pRefusal: string): Boolean;
begin
  pRevisionId:= '';
  pRefusal:= '';
  var Tool: string:= VcsKindName(pCopy.Kind);
  var Ids: TArray<string>:= nil;
  if pExitCode = 0 then
    for var Line: string in DecodeBytes(pOutput, 0, Length(pOutput), pCopy.Kind).Split([#10]) do
      if IsHexId(Trim(Line)) then Ids:= Ids + [Trim(Line)]; { a warning line of the tool is not an id }
  Result:= Length(Ids) = 1;
  if Result then pRevisionId:= Ids[0]
  else if Length(Ids) > 1 then
    pRefusal:= Format('"%s" names %d changesets in the %s working copy %s; give one', [pRevision, Length(Ids), Tool,
      pCopy.Root])
  else
  begin
    var Said: string:= if pExitCode = 0 then 'it names no changeset' else FirstLine(pOutput, pCopy.Kind);
    pRefusal:= Format('unknown revision "%s" in the %s working copy %s', [pRevision, Tool, pCopy.Root]);
    if (pExitCode <> 0) and (Said <> '') then pRefusal:= pRefusal + Format(' (%s: %s)', [Tool, Said])
    else if Said <> '' then pRefusal:= pRefusal + Format(' (%s)', [Said]);
  end;
end;

function ResolveRevision(const pCopy: TVcsWorkingCopy; const pRevision: string; out pRevisionId: string;
  out pRefusal: string): Boolean;
begin
  Result:= False;
  pRevisionId:= '';
  pRefusal:= '';
  if pCopy.Kind = vkNone then
  begin
    pRefusal:= 'no working copy was given';
    Exit;
  end;
  if not IsPassableRevision(pRevision) then
  begin
    pRefusal:= Format('"%s" is not a revision name this flag passes on (empty, a leading "-", a double quote, ' +
      'a control character or a trailing backslash)', [pRevision]);
    Exit;
  end;
  var Output: TBytes;
  var ExitCode: Integer;
  var StartError: Cardinal;
  PrepareEnvironment(pCopy.Kind);
  var Command: string:= Format(if pCopy.Kind = vkGit then GIT_RESOLVE else HG_RESOLVE, [pRevision]);
  if RunTool(Command, pCopy.Root, True, Output, ExitCode, StartError) then
    Result:= PickRevisionId(pCopy, pRevision, Output, ExitCode, pRevisionId, pRefusal)
  else
    pRefusal:= Format('%s could not be started in %s (Windows error %d; is it on PATH?)',
      [VcsKindName(pCopy.Kind), pCopy.Root, StartError]);
end;

function ChangedLinesSince(const pCopy: TVcsWorkingCopy; const pRevision: string; out pChanged: IVcsChangedLines;
  out pRefusal: string): Boolean;
begin
  Result:= False;
  pChanged:= nil;
  var RevisionId: string;
  if not ResolveRevision(pCopy, pRevision, RevisionId, pRefusal) then Exit;
  var IsGit: Boolean:= pCopy.Kind = vkGit;
  var Diff, Untracked: TBytes;
  if not RunFor(pCopy, Format(if IsGit then GIT_DIFF else HG_DIFF, [RevisionId]), 'the diff', Diff, pRefusal) then Exit;
  if not RunFor(pCopy, if IsGit then GIT_UNTRACKED else HG_UNTRACKED, 'the files not tracked yet', Untracked,
    pRefusal) then Exit;
  var Answer: TVcsChangedLines:= TVcsChangedLines.Create(pCopy, pRevision, RevisionId);
  var Keep: IVcsChangedLines:= Answer; { the interface owns it from here }
  if not ReadDiff(Diff, Answer, pRefusal) then Exit;
  ReadUntracked(Untracked, Answer);
  pChanged:= Keep;
  Result:= True;
end;

{ the commit log (G-46) }

const
  GIT_LOG = GIT_BASE + 'log --no-merges --no-renames --name-status --no-color --format=@@%%H %s';
  HG_LOG = 'hg log -r "%s and not merge()" --template "@@{node}\n{file_mods %% ''M {file}\n''}' +
    '{file_adds %% ''A {file}\n''}{file_dels %% ''D {file}\n''}"';
  DATE_LENGTH = 10;
  DAY_DASH_1 = 5; { the dashes of YYYY-MM-DD }
  DAY_DASH_2 = 8;
  COMMIT_MARK = '@@';
  ENTRY_MIN_LENGTH = 3; { 'A x': the status, one separator, a name }
  ENTRY_PATH_AT = 3;
  REFUSAL_SHOWN = 60;

/// <summary>Whether a text is a calendar day written YYYY-MM-DD.</summary>
function IsIsoDay(const pText: string): Boolean;
begin
  Result:= (Length(pText) = DATE_LENGTH) and (pText[DAY_DASH_1] = '-') and (pText[DAY_DASH_2] = '-');
  if Result then
    for var K:= 1 to DATE_LENGTH do
      if (K <> DAY_DASH_1) and (K <> DAY_DASH_2) and not CharInSet(pText[K], ['0'..'9']) then Exit(False);
end;

/// <summary>Reads the '@@id' blocks and their 'S path' lines (S = A, M or D; one tab or space after it).</summary>
function ReadLogText(const pCopy: TVcsWorkingCopy; const pText: string; out pCommits: TArray<TVcsCommit>;
  out pRefusal: string): Boolean;
begin
  pCommits:= nil;
  pRefusal:= '';
  Result:= True;
  var Root: string:= IncludeTrailingPathDelimiter(pCopy.Root);
  var Done:= TList<TVcsCommit>.Create;
  var Files:= TList<TVcsCommitFile>.Create;
  try
    var Open: Boolean:= False;
    var Current:= Default(TVcsCommit);
    for var Line: string in pText.Split([#10]) do
    begin
      var Row: string:= Line.TrimRight([#13]);
      if Row = '' then Continue;
      if Row.StartsWith(COMMIT_MARK) then
      begin
        if Open then
        begin
          Current.Files:= Files.ToArray;
          Done.Add(Current);
        end;
        Files.Clear;
        Open:= True;
        Current.Id:= Copy(Row, Length(COMMIT_MARK) + 1, MaxInt);
      end
      else if Open and (Length(Row) >= ENTRY_MIN_LENGTH) and CharInSet(Row[1], ['A', 'M', 'D'])
        and CharInSet(Row[2], [#9, ' ']) then
      begin
        var Entry: TVcsCommitFile;
        Entry.Status:= Row[1];
        Entry.Path:= Root + StringReplace(Copy(Row, ENTRY_PATH_AT, MaxInt), '/', '\', [rfReplaceAll]);
        Files.Add(Entry);
      end
      else
      begin
        pRefusal:= Format('the %s log could not be read at "%s"', [VcsKindName(pCopy.Kind), Copy(Row, 1, REFUSAL_SHOWN)]);
        Exit(False);
      end;
    end;
    if Open then
    begin
      Current.Files:= Files.ToArray;
      Done.Add(Current);
    end;
    pCommits:= Done.ToArray;
  finally
    Files.Free;
    Done.Free;
  end;
end;
function ReadCommitLog(const pCopy: TVcsWorkingCopy; const pSince: string; out pCommits: TArray<TVcsCommit>;
  out pRefusal: string): Boolean;
begin
  Result:= False;
  pCommits:= nil;
  pRefusal:= '';
  if pCopy.Kind = vkNone then
  begin
    pRefusal:= 'no working copy was given';
    Exit;
  end;
  var IsGit: Boolean:= pCopy.Kind = vkGit;
  var Range: string;
  if pSince = '' then
    Range:= if IsGit then 'HEAD' else 'ancestors(.)'
  else if IsIsoDay(pSince) then
    Range:= if IsGit then Format('--since="%s 00:00:00" HEAD', [pSince]) else Format('date(''>%s'') and ancestors(.)', [pSince])
  else
  begin
    var Id: string;
    if not ResolveRevision(pCopy, pSince, Id, pRefusal) then Exit;
    Range:= if IsGit then Id + '..HEAD' else Format('ancestors(.) - ancestors(%s)', [Id]);
  end;
  var Output: TBytes;
  if not RunFor(pCopy, Format(if IsGit then GIT_LOG else HG_LOG, [Range]), 'the commit log', Output, pRefusal) then Exit;
  Result:= ReadLogText(pCopy, DecodeBytes(Output, 0, Length(Output), pCopy.Kind), pCommits, pRefusal);
end;

end.