unit DRagLint.Project.Coherence;

// Computes, for a set of project members (Task 1's TProjectMember), whether
// each one is coherent with a given ISymbolStore: present in the index, and
// not stale relative to the on-disk file or the last compile. Read-only:
// never writes to the store or the filesystem. Consumed by the reconcile-
// project coherence checks (Task 3), which enumerate .pas and .dfm members
// and decide what to do about each incoherent one.

interface

uses
  System.SysUtils
  , System.IOUtils
  , System.DateUtils
  , DRagLint.Core.Interfaces
  , DRagLint.Project.Members
  ;

type
  /// <summary>Coherence verdict for one project member's UnitPath against the
  /// index. Indexed: the path has a files row. IndexFresh: that row's
  /// mtime_unix matches the on-disk file's last-write time (Unix seconds,
  /// local time -- the same basis the indexer stores). CompiledFresh: the
  /// row's last_compiled_unix is at or after mtime_unix (never NULL-stale).
  /// All three are False when Indexed is False.</summary>
  TMemberCoherence = record
    Member       : TProjectMember;
    Indexed      : Boolean       ;
    IndexFresh   : Boolean       ;
    CompiledFresh: Boolean       ;
  end;

  /// <summary>Computes one TMemberCoherence per AMembers entry, in input
  /// order, checking ONLY Member.UnitPath (the .pas) against AStore -- the
  /// sibling .dfm, when present, is a separate member scanned by the caller.
  /// AStore.FindFileIdByPath resolves the files row (Indexed = FileId > 0).
  /// When Indexed, IndexFresh compares AStore.GetFileMTime against the
  /// on-disk mtime computed the same way the indexer does
  /// (DateTimeToUnix(TFile.GetLastWriteTime(...), False)); if UnitPath no
  /// longer exists on disk, IndexFresh is False rather than raising.
  /// CompiledFresh compares AStore.GetFileCompiledAt against the SAME
  /// GetFileMTime value (read once and reused). When not Indexed, IndexFresh
  /// and CompiledFresh are both False.</summary>
  /// <param name="AStore">Symbol store to check members against.</param>
  /// <param name="AMembers">Members to check; one path per record.</param>
  /// <returns>One TMemberCoherence per AMembers entry, same order.</returns>
function ComputeCoherence(const AStore: ISymbolStore; const AMembers: TArray<TProjectMember>): TArray<TMemberCoherence>;

/// <summary>True when a member is not fully coherent with the index: not
/// indexed, or indexed but stale (index-stale or compile-stale).</summary>
/// <param name="AC">A coherence verdict produced by ComputeCoherence.</param>
/// <returns>(not AC.Indexed) or (not AC.IndexFresh) or (not AC.CompiledFresh).</returns>
function IsIncoherent(const AC: TMemberCoherence): Boolean;

implementation

function ComputeCoherence(const AStore: ISymbolStore; const AMembers: TArray<TProjectMember>): TArray<TMemberCoherence>;
var
  I           : Integer;
  FileId      : Int64  ;
  IndexMTime  : Int64  ;
  DiskMTime   : Int64  ;
  HasDiskMTime: Boolean;
begin
  SetLength(Result, Length(AMembers));
  for I:= 0 to High(AMembers) do
  begin
    Result[I].Member       := AMembers[I];
    Result[I].IndexFresh   := False;
    Result[I].CompiledFresh:= False;

    FileId:= AStore.FindFileIdByPath(AMembers[I].UnitPath);
    Result[I].Indexed:= FileId > 0;
    if not Result[I].Indexed then Continue;

    IndexMTime:= AStore.GetFileMTime(FileId);

    HasDiskMTime:= False;
    DiskMTime:= 0;
    try
      if TFile.Exists(AMembers[I].UnitPath) then
      begin
        DiskMTime:= DateTimeToUnix(TFile.GetLastWriteTime(AMembers[I].UnitPath), False);
        HasDiskMTime:= True;
      end;
    except
      HasDiskMTime:= False; // gone/inaccessible on disk -> treat as not fresh
    end;

    Result[I].IndexFresh   := HasDiskMTime and (IndexMTime = DiskMTime);
    Result[I].CompiledFresh:= AStore.GetFileCompiledAt(FileId) >= IndexMTime;
  end; // for
end; // function

function IsIncoherent(const AC: TMemberCoherence): Boolean;
begin
  Result:= (not AC.Indexed) or (not AC.IndexFresh) or (not AC.CompiledFresh);
end;

end.
