unit DRagLint.Index.Drift;

/// <summary>Library-drift analysis: which registry library roots have no
/// indexed files in a given SQLite database. Read-only; no registry
/// dependency -- callers pass the root list so the function is testable
/// without a live IDE installation.</summary>
/// <remarks>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

uses
  System.SysUtils
  , DRagLint.Core.Interfaces
  ;

/// <summary>Read-only: returns the subset of ACurrentRoots that BOTH have no
/// indexed file under them in the DB at ADbPath AND contain at least one
/// indexable source file (.pas, .inc, .dfm) on disk (searched recursively
/// with early exit). Roots whose directory holds no source at all are excluded
/// from the result -- they have nothing to index and are not true drift (e.g.
/// DCU/DCP/BPL output folders). ADbPath must exist.</summary>
/// <param name="ADbPath">Path to the SQLite database file. Must exist.</param>
/// <param name="ACurrentRoots">Library root paths to check for coverage.</param>
/// <returns>Subset of ACurrentRoots that have source on disk but no indexed
/// files under them (true drift = forgotten/added source folder).</returns>
/// <remarks>
/// Not thread-safe; call from a single thread. Disk scan uses early
/// exit on first source file found -- no full enumeration of large roots.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.Core.Interfaces.TWalkFilter.Create, DRagLint.Index.Drift.AnalyzeLibraryDrift/4</para>
/// <para>Returns: AnalyzeLibraryDrift(ADbPath, ACurrentRoots, TWalkFilter.Create, Excluded)</para>
/// <para>Pure</para>
/// <para>Overload 1 of 2</para>
/// <para>Directives: overload</para>
/// <seealso cref="DRagLint.Core.Interfaces.TWalkFilter.Create"/>
/// <seealso cref="DRagLint.Index.Drift.AnalyzeLibraryDrift"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AnalyzeLibraryDrift(const ADbPath: string; const ACurrentRoots: TArray<string>): TArray<string>; overload;

/// <summary>As the two-argument overload, but a root that the indexer's walk
/// with AFilter would prune by its own name (an exclude glob such as the
/// manifest's "Win64", a built-in pruned name, a .scanignore marker) is NOT
/// drift: it goes to AExcluded instead of the result.</summary>
/// <param name="ADbPath">Path to the SQLite database file. Must exist.</param>
/// <param name="ACurrentRoots">Library root paths to check for coverage.</param>
/// <param name="AFilter">The walk filter the index section uses
/// (TPlanSection.Filter for a library section).</param>
/// <param name="AExcluded">Out: roots with no indexed file and source on disk
/// that the walk prunes by configuration -- reported, never counted as drift.</param>
/// <returns>Roots with source on disk, no indexed file, and not pruned by
/// AFilter.</returns>
/// <remarks>B-02: without the filter, the four Win64 compiled-lib roots
/// (...\Lib\RX13\Win64) read as "missing" after every full rescan, because the
/// manifest's global exclude "Win64" prunes the walk ROOT itself, so no rescan
/// can ever index them. Not thread-safe; call from a single thread.</remarks>
function AnalyzeLibraryDrift(const ADbPath: string; const ACurrentRoots: TArray<string>; const AFilter: TWalkFilter; out AExcluded: TArray<string>): TArray<string>; overload;

implementation

uses
  System.IOUtils
  , DRagLint.Core   .Indexer
  , DRagLint.Storage.SQLite
  ;

{ ---------------------------------------------------------------------------
  Path normalisation helpers
  --------------------------------------------------------------------------- }

{ 2026-09-02: RESOLVE '..' TOO, because drift compares a ROOT against a STORED
  path and the two sides must be canonicalised the same way. NormalizeStoredPath
  (DRagLint.Storage.SQLite) now expands stored paths to a full path, so a root
  still spelled 'tests\autotest\..\fixtures\reconcile' no longer prefix-matches
  the stored 'tests\fixtures\reconcile\X.pas' -- and every file under it reads as
  drift, i.e. as a source folder someone forgot to index. run_drift.ps1 caught
  exactly that. Folding case and separators but not '..' left the comparison
  half-canonical, which is only ever correct while BOTH sides are equally
  half-canonical. }
function NormPath(const APath: string): string;
begin
  if APath = '' then Exit('');
  Result:= LowerCase(ExpandFileName(StringReplace(APath, '/', '\', [rfReplaceAll])));
end;

function NormRoot(const APath: string): string;
begin
  Result:= NormPath(APath);
  if (Result <> '') and (Result[Length(Result)] <> '\') then Result:= Result + '\';
end;

{ ---------------------------------------------------------------------------
  DirHasSource -- recursive, early-exit disk scan
  Checks .pas, .inc, .dfm only; skips hidden/VCS/output subdirs.
  Returns True the moment the first matching file is found.
  --------------------------------------------------------------------------- }

/// <summary>Returns True if ADir (or any subdirectory) contains at least one
/// indexable source file (.pas, .inc, or .dfm). Stops on the first hit --
/// does not enumerate the whole tree.</summary>
/// <remarks>Skips subdirectories named __history, .git, .hg, and Win32/Win64
/// (common Delphi output dirs) to avoid traversing large non-source trees.</remarks>
function DirHasSource(const ADir: string): Boolean; forward;

function ShouldSkipDir(const ADirName: string): Boolean;
var
  LN: string;
begin
  LN:= LowerCase(ADirName);
  Result:= (LN = '__history') or (LN = '.git') or (LN = '.hg') or (LN = 'win32') or (LN = 'win64');
end;

function DirHasSource(const ADir: string): Boolean;
const
  SrcExts: array[0..2] of string = ('.pas', '.inc', '.dfm');
var
  Files  : TArray<string>;
  SubDirs: TArray<string>;
  F      : string        ;
  D      : string        ;
  Ext    : string        ;
  I      : Integer       ;
  DName  : string        ;
begin
  Result:= False;
  if not TDirectory.Exists(ADir) then Exit;

  { Check files in this directory. }
  try
    Files:= TDirectory.GetFiles(ADir, '*', TSearchOption.soTopDirectoryOnly);
  except
    SetLength(Files, 0);
  end;
  for F in Files do
  begin
    Ext:= LowerCase(ExtractFileExt(F));
    for I:= 0 to High(SrcExts) do
      if Ext = SrcExts[I] then
      begin
        Result:= True;
        Exit; { Early exit on first hit }
      end;
  end;

  { Recurse into subdirectories. }
  try
    SubDirs:= TDirectory.GetDirectories(ADir, '*', TSearchOption.soTopDirectoryOnly);
  except
    SetLength(SubDirs, 0);
  end;
  for D in SubDirs do
  begin
    DName:= ExtractFileName(ExcludeTrailingPathDelimiter(D));
    if ShouldSkipDir(DName) then Continue;
    if DirHasSource(D) then
    begin
      Result:= True;
      Exit; { Early exit on first hit in subtree }
    end;
  end;
end; // function

{ ---------------------------------------------------------------------------
  AnalyzeLibraryDrift
  --------------------------------------------------------------------------- }

function AnalyzeLibraryDrift(const ADbPath: string; const ACurrentRoots: TArray<string>): TArray<string>;
var
  Excluded: TArray<string>;
begin
  Result:= AnalyzeLibraryDrift(ADbPath, ACurrentRoots, TWalkFilter.Create, Excluded);
end;

function AnalyzeLibraryDrift(const ADbPath: string; const ACurrentRoots: TArray<string>; const AFilter: TWalkFilter; out AExcluded: TArray<string>): TArray<string>;
var
  Store    : ISymbolStore   ;
  FileIds  : TArray<Int64>  ;
  FilePath : string         ;
  AllPaths : TArray<string> ;
  PathCount: Integer        ;
  NormRoots: TArray<string> ;
  Covered  : TArray<Boolean>;
  R        : Integer        ;
  P        : Integer        ;
  Missing  : TArray<string> ;
  MissCnt  : Integer        ;
  ExclCnt  : Integer        ;
begin
  Result:= nil;
  AExcluded:= nil;
  if Length(ACurrentRoots) = 0 then Exit;

  { Normalise all roots once. }
  SetLength(NormRoots, Length(ACurrentRoots));
  for R:= 0 to High(ACurrentRoots) do NormRoots[R]:= NormRoot(ACurrentRoots[R]);

  { Open the store and enumerate all indexed file paths. }
  Store:= TSQLiteSymbolStore.Create(ADbPath);
  try
    FileIds:= Store.GetAllFileIds;
    PathCount:= Length(FileIds);
    SetLength(AllPaths, PathCount);
    for P:= 0 to PathCount - 1 do
    begin
      FilePath:= Store.GetFilePath(FileIds[P]);
      AllPaths[P]:= NormPath(FilePath);
    end;
  finally
    Store:= nil; { release interface -> free the store }
  end;

  { For each root, check whether at least one indexed path starts with it. }
  SetLength(Covered, Length(ACurrentRoots));
  for R:= 0 to High(ACurrentRoots) do Covered[R]:= False;

  for P:= 0 to PathCount - 1 do
  begin
    for R:= 0 to High(NormRoots) do
    begin
      if not Covered[R] then
        if AllPaths[P].StartsWith(NormRoots[R]) then Covered[R]:= True;
    end;
  end;

  { Collect missing roots in ORIGINAL casing -- but only if the root
    actually contains indexable source on disk. Roots with no source
    (DCU/DCP/BPL output folders, empty dirs) are silently excluded:
    they have nothing to index and are not genuine drift.
    B-02: a root the walk prunes by configuration is not drift either -- no
    rescan can index it -- so it is reported apart, in AExcluded. }
  MissCnt:= 0;
  ExclCnt:= 0;
  SetLength(Missing  , Length(ACurrentRoots));
  SetLength(AExcluded, Length(ACurrentRoots));
  for R:= 0 to High(ACurrentRoots) do
    if (not Covered[R]) and DirHasSource(ACurrentRoots[R]) then
    begin
      if DirPrunedByFilter(ACurrentRoots[R], AFilter) then
      begin
        AExcluded[ExclCnt]:= ACurrentRoots[R];
        Inc(ExclCnt);
      end
      else
      begin
        Missing[MissCnt]:= ACurrentRoots[R];
        Inc(MissCnt);
      end;
    end;
  SetLength(Missing  , MissCnt);
  SetLength(AExcluded, ExclCnt);
  Result:= Missing;
end; // function

end.
