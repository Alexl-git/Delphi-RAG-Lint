unit DRagLint.CLI.ChangedSince;

{ drag-lint 1.56 -- lane VCS-1: `lint-all --changed-since <rev>` (gap-plan S4 + G-50): only the findings on
  lines changed since the revision, in an hg or a git working copy (DRagLint.Query.Vcs).
  DRagLint.CLI.DoLintAll makes exactly two calls, both written by W2FRAME:
    1. CheckChangedSince, before the scan: an unknown revision or a folder under no version control is
       refused there, so nobody waits for a whole lint-all to learn the flag was wrong;
    2. KeepFindingsChangedSince, after the --project scope filter and before the report is written.
  The working copy is the one that holds the --project file's folder; without --project, the one that holds
  the current directory (as git and hg themselves read it). It is never taken from the --db path: an index
  may live anywhere. Lane VCS-1 owns this unit. }

interface

uses
  DRagLint.Core.Model;

type
  /// <summary>One `lint-all --changed-since` request, as DRagLint.CLI.DoLintAll knows it.</summary>
  TChangedSinceRequest = record
    /// <summary>The --changed-since value; not empty.</summary>
    Revision: string;
    /// <summary>The --project file, '' when the run has none.</summary>
    ProjectPath: string;
    /// <summary>The project index. In CheckChangedSince: the --db value or the --project default, '' when
    /// neither resolved yet. In KeepFindingsChangedSince: the index the run linted; not empty. Not read by
    /// this unit in 1.56: the working copy is found from ProjectPath or the current directory.</summary>
    DbPath: string;
  end;

/// <summary>Decides, before the scan, whether the run can be narrowed to the revision.</summary>
/// <param name="pRequest">The request; Revision is not empty.</param>
/// <param name="pRefusal">Why not, as one line without the 'ERROR: ' prefix; '' when the result is True.</param>
/// <returns>True = a git or hg working copy was found and its tool knows the revision as one changeset;
/// False = the caller prints pRefusal and exits 2 (no working copy, both a .git and a .hg in one folder, the
/// tool does not start, unknown revision, a revset naming several changesets).</returns>
/// <remarks>Read-only; prints nothing. Runs `git rev-parse` or `hg log` once.</remarks>
function CheckChangedSince(const pRequest: TChangedSinceRequest; out pRefusal: string): Boolean;

/// <summary>Keeps the findings that sit on lines changed since the revision.</summary>
/// <param name="pRequest">The request CheckChangedSince accepted, with DbPath set to the linted index.</param>
/// <param name="pFindings">Every finding of the run; replaced by the kept ones when the result is True, left
/// untouched when it is False. A finding is kept when its span StartLine..EndLine (StartLine alone when
/// EndLine is smaller) overlaps a changed run of its file, or its file is not in the revision at all (added,
/// renamed, not tracked yet). Dropped: findings on unchanged lines, in files outside the working copy, and
/// findings that name no file.</param>
/// <param name="pMessage">True: the note line for the report, with the kept and the dropped counts. False:
/// the refusal, as one line without the 'ERROR: ' prefix.</param>
/// <returns>True = pFindings was narrowed; False = the caller prints pMessage and exits 2 (every reason of
/// CheckChangedSince, and a diff the tool could not produce or this engine could not read).</returns>
/// <remarks>Read-only on the working copy; prints nothing. The diff is the working copy on disk against the
/// revision, so the lines match what lint-all just scanned.</remarks>
function KeepFindingsChangedSince(const pRequest: TChangedSinceRequest; var pFindings: TArray<TLintFinding>;
  out pMessage: string): Boolean;

implementation

uses
  System.SysUtils, DRagLint.Query.Vcs;

const
  REFUSED = 'lint-all: --changed-since %s: %s. Nothing was answered.';
  KEPT_NOTE = 'lint-all: --changed-since %s (%s %s, working copy %s) -- %d of %d finding(s) are on lines changed ' +
    'since it, in %d changed file(s); dropped: %d on unchanged lines, %d outside the working copy, %d without a file';
  SHORT_ID = 12;

/// <summary>The folder the working copy is looked up from.</summary>
function StartFolder(const pRequest: TChangedSinceRequest): string;
begin
  Result:= if pRequest.ProjectPath <> '' then ExtractFileDir(ExpandFileName(pRequest.ProjectPath)) else GetCurrentDir;
end;

function CheckChangedSince(const pRequest: TChangedSinceRequest; out pRefusal: string): Boolean;
begin
  var WorkingCopy: TVcsWorkingCopy;
  var Why, RevisionId: string;
  Result:= FindWorkingCopy(StartFolder(pRequest), WorkingCopy, Why)
    and ResolveRevision(WorkingCopy, pRequest.Revision, RevisionId, Why);
  pRefusal:= if Result then '' else Format(REFUSED, [pRequest.Revision, Why]);
end;

function KeepFindingsChangedSince(const pRequest: TChangedSinceRequest; var pFindings: TArray<TLintFinding>;
  out pMessage: string): Boolean;
begin
  var WorkingCopy: TVcsWorkingCopy;
  var Why: string;
  var Changed: IVcsChangedLines;
  Result:= FindWorkingCopy(StartFolder(pRequest), WorkingCopy, Why)
    and ChangedLinesSince(WorkingCopy, pRequest.Revision, Changed, Why);
  if not Result then
  begin
    pMessage:= Format(REFUSED, [pRequest.Revision, Why]);
    Exit;
  end;
  var Kept: TArray<TLintFinding>;
  SetLength(Kept, Length(pFindings));
  var KeptCount: Integer:= 0;
  var Unchanged: Integer:= 0;
  var Outside: Integer:= 0;
  var NoFile: Integer:= 0;
  for var Finding: TLintFinding in pFindings do
    if Finding.FilePath = '' then Inc(NoFile)
    else if not Changed.InWorkingCopy(Finding.FilePath) then Inc(Outside)
    else if Changed.IsChanged(Finding.FilePath, Finding.StartLine, Finding.EndLine) then
    begin
      Kept[KeptCount]:= Finding;
      Inc(KeptCount);
    end
    else Inc(Unchanged);
  SetLength(Kept, KeptCount);
  var ShortId: string:= Copy(Changed.RevisionId(), 1, SHORT_ID);
  var FileCount: Integer:= Length(Changed.Files());
  pMessage:= Format(KEPT_NOTE, [pRequest.Revision, VcsKindName(WorkingCopy.Kind), ShortId, WorkingCopy.Root, KeptCount,
    Length(pFindings), FileCount, Unchanged, Outside, NoFile]);
  pFindings:= Kept;
end;

end.
