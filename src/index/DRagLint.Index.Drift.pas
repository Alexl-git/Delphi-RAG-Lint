unit DRagLint.Index.Drift;

/// <summary>Library-drift analysis: which registry library roots have no
/// indexed files in a given SQLite database. Read-only; no registry
/// dependency -- callers pass the root list so the function is testable
/// without a live IDE installation.</summary>
/// <remarks>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

uses
  System.SysUtils;

/// <summary>Read-only: returns the subset of ACurrentRoots that have NO indexed
/// file under them in the DB at ADbPath (case-insensitive, normalized separators
/// + trailing path delimiter). ADbPath must exist. Open the store read-only,
/// enumerate file paths once, test each root by prefix.</summary>
/// <param name="ADbPath">Path to the SQLite database file. Must exist.</param>
/// <param name="ACurrentRoots">Library root paths to check for coverage.</param>
/// <returns>Subset of ACurrentRoots that have no indexed files under them.</returns>
function AnalyzeLibraryDrift(const ADbPath: string;
  const ACurrentRoots: TArray<string>): TArray<string>;

implementation

uses
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite;

function NormPath(const APath: string): string;
begin
  Result := LowerCase(StringReplace(APath, '/', '\', [rfReplaceAll]));
end;

function NormRoot(const APath: string): string;
begin
  Result := NormPath(APath);
  if (Result <> '') and (Result[Length(Result)] <> '\') then
    Result := Result + '\';
end;

function AnalyzeLibraryDrift(const ADbPath: string;
  const ACurrentRoots: TArray<string>): TArray<string>;
var
  Store:       ISymbolStore;
  FileIds:     TArray<Int64>;
  FilePath:    string;
  AllPaths:    TArray<string>;
  PathCount:   Integer;
  NormRoots:   TArray<string>;
  Covered:     TArray<Boolean>;
  R, P:        Integer;
  Missing:     TArray<string>;
  MissCnt:     Integer;
begin
  Result := nil;
  if Length(ACurrentRoots) = 0 then
    Exit;

  { Normalise all roots once. }
  SetLength(NormRoots, Length(ACurrentRoots));
  for R := 0 to High(ACurrentRoots) do
    NormRoots[R] := NormRoot(ACurrentRoots[R]);

  { Open the store and enumerate all indexed file paths. }
  Store := TSQLiteSymbolStore.Create(ADbPath);
  try
    FileIds   := Store.GetAllFileIds;
    PathCount := Length(FileIds);
    SetLength(AllPaths, PathCount);
    for P := 0 to PathCount - 1 do
    begin
      FilePath    := Store.GetFilePath(FileIds[P]);
      AllPaths[P] := NormPath(FilePath);
    end;
  finally
    Store := nil;   { release interface -> free the store }
  end;

  { For each root, check whether at least one indexed path starts with it. }
  SetLength(Covered, Length(ACurrentRoots));
  for R := 0 to High(ACurrentRoots) do
    Covered[R] := False;

  for P := 0 to PathCount - 1 do
  begin
    for R := 0 to High(NormRoots) do
    begin
      if not Covered[R] then
        if AllPaths[P].StartsWith(NormRoots[R]) then
          Covered[R] := True;
    end;
  end;

  { Collect missing roots in ORIGINAL casing. }
  MissCnt := 0;
  SetLength(Missing, Length(ACurrentRoots));
  for R := 0 to High(ACurrentRoots) do
    if not Covered[R] then
    begin
      Missing[MissCnt] := ACurrentRoots[R];
      Inc(MissCnt);
    end;
  SetLength(Missing, MissCnt);
  Result := Missing;
end;

end.
