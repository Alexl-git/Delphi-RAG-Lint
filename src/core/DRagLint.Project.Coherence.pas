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

const
  /// <summary>The schema_meta key of the PROJECT TAG an index writes into
  /// inbound doc facts (D27, 2026-09-24): the sanitized base name of the
  /// project file a closure scan indexed.</summary>
  /// <remarks>Stamped beside SCAN_TYPE_KEY by both index paths and read by
  /// ProjectTagFor and the multi-project rename, so the tag is a stored fact of
  /// the index and not a property of whatever the .sqlite file happens to be
  /// called. Absent on an index built before 1.18.0 -- ProjectTagFor then falls
  /// back to the DB base name. Lives here (not in DRagLint.CLI) so a unit that
  /// must not link the CLI can read it.</remarks>
  PROJECT_TAG_KEY = 'project_tag';

type
  /// <summary>Coherence verdict for one project member's UnitPath against the
  /// index. Indexed: the path has a files row. IndexFresh: that row's
  /// mtime_unix matches the on-disk file's last-write time (Unix seconds,
  /// local time -- the same basis the indexer stores). CompiledFresh: the
  /// row's last_compiled_unix is at or after mtime_unix (never NULL-stale).
  /// All three are False when Indexed is False.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Project.Coherence.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.Refactor.MultiProjectRename.MissingMembers (DRagLint.Refactor.MultiProjectRename.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Project.Coherence, DRagLint.Refactor.MultiProjectRename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.Refactor.MultiProjectRename.MissingMembers (DRagLint.Refactor.MultiProjectRename.pas)</para>
/// <para>Calls: DateTimeToUnix, DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath, DRagLint.Core.Interfaces.ISymbolStore.GetFileCompiledAt, DRagLint.Core.Interfaces.ISymbolStore.GetFileMTime</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindFileIdByPath"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFileCompiledAt"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFileMTime"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ComputeCoherence(const AStore: ISymbolStore; const AMembers: TArray<TProjectMember>): TArray<TMemberCoherence>;

/// <summary>True when a member is not fully coherent with the index: not
/// indexed, or indexed but stale (index-stale or compile-stale).</summary>
/// <param name="AC">A coherence verdict produced by ComputeCoherence.</param>
/// <returns>(not AC.Indexed) or (not AC.IndexFresh) or (not AC.CompiledFresh).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas)</para>
/// <para>Returns: (not AC.Indexed) or (not AC.IndexFresh) or (not AC.CompiledFresh)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsIncoherent(const AC: TMemberCoherence): Boolean;

/// <summary>AName with every character the tag grammar reserves -- `[`, `]`,
/// `,`, blank, tab -- replaced by '_'.</summary>
/// <param name="AName">A project name as typed or derived.</param>
/// <returns>A name safe inside `[A,B]entry`, trimmed.</returns>
/// <remarks>Pure.</remarks>
function SanitizeProjectTag(const AName: string): string;

/// <summary>True when a stored PROJECT_TAG_KEY value names a DIFFERENT project
/// than AProjectFile -- the index is some other project's closure.</summary>
/// <param name="AStoredTag">The schema_meta project_tag value as read; blank
/// (untagged, cleared by a folder scan, or predating the stamp) never
/// conflicts.</param>
/// <param name="AProjectFile">The .dpr/.dproj the caller would index or act
/// for; compared by SanitizeProjectTag of its base name, case-insensitively.</param>
/// <returns>False for a blank tag or a matching one; True otherwise.</returns>
/// <remarks>Pure. The ONE comparison behind both the multi-project rename's
/// owner check and the `index --project` refusal, so the two cannot disagree
/// about what "another project's index" means.</remarks>
function ProjectTagConflicts(const AStoredTag, AProjectFile: string): Boolean;

implementation

function ProjectTagConflicts(const AStoredTag, AProjectFile: string): Boolean;
begin
  Result:= (Trim(AStoredTag) <> '') and
    not SameText(Trim(AStoredTag), SanitizeProjectTag(TPath.GetFileNameWithoutExtension(AProjectFile)));
end; // function

function SanitizeProjectTag(const AName: string): string;
const
  RESERVED = '[], ' + #9;
var
  I: Integer;
begin
  Result:= Trim(AName);
  for I:= 1 to Length(Result) do
    if Pos(Result[I], RESERVED) > 0 then Result[I]:= '_';
end; // function

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
