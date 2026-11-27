unit DRagLint.CLI.ChangedSince;

{ drag-lint 1.56 -- lane VCS-1: `lint-all --changed-since <rev>` (gap-plan S4 + G-50): only the findings on
  lines changed since the revision, in an hg or a git working copy (DRagLint.Query.Vcs).
  DRagLint.CLI.DoLintAll makes exactly two calls, both written by W2FRAME:
    1. CheckChangedSince, before the scan: an unknown revision or a folder under no version control is
       refused there, so nobody waits for a whole lint-all to learn the flag was wrong;
    2. KeepFindingsChangedSince, after the --project scope filter and before the report is written.
  Scaffold created by lane W2FRAME (tranche 2): both calls refuse, so the flag never answers with an
  unfiltered report. Lane VCS-1 owns this unit. }

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
    /// neither resolved yet. In KeepFindingsChangedSince: the index the run linted; not empty.</summary>
    DbPath: string;
  end;

/// <summary>Decides, before the scan, whether the run can be narrowed to the revision.</summary>
/// <param name="pRequest">The request; Revision is not empty.</param>
/// <param name="pRefusal">Why not, as one line without the 'ERROR: ' prefix; '' when the result is True.</param>
/// <returns>True = the revision and the working copy were read; False = the caller prints pRefusal and exits 2.
/// The scaffold returns False for every request.</returns>
/// <remarks>Read-only; prints nothing.</remarks>
function CheckChangedSince(const pRequest: TChangedSinceRequest; out pRefusal: string): Boolean;

/// <summary>Keeps the findings that sit on lines changed since the revision.</summary>
/// <param name="pRequest">The request CheckChangedSince accepted, with DbPath set to the linted index.</param>
/// <param name="pFindings">Every finding of the run; replaced by the kept ones when the result is True, left
/// untouched when it is False.</param>
/// <param name="pMessage">True: the note line for the report ('' = none). False: the refusal, as one line
/// without the 'ERROR: ' prefix.</param>
/// <returns>True = pFindings was narrowed; False = the caller prints pMessage and exits 2. The scaffold returns
/// False for every request.</returns>
/// <remarks>Read-only on the index and the working copy; prints nothing.</remarks>
function KeepFindingsChangedSince(const pRequest: TChangedSinceRequest; var pFindings: TArray<TLintFinding>;
  out pMessage: string): Boolean;

implementation

uses
  System.SysUtils;

const
  NOT_BUILT = 'lint-all: --changed-since %s: not built in this engine yet (1.56 lane VCS-1). Nothing was answered.';

function NotBuilt(const pRevision: string): string;
begin
  Result:= Format(NOT_BUILT, [pRevision]);
end;

function CheckChangedSince(const pRequest: TChangedSinceRequest; out pRefusal: string): Boolean;
begin
  pRefusal:= NotBuilt(pRequest.Revision);
  Result:= False;
end;

function KeepFindingsChangedSince(const pRequest: TChangedSinceRequest; var pFindings: TArray<TLintFinding>;
  out pMessage: string): Boolean;
begin
  pMessage:= NotBuilt(pRequest.Revision);
  Result:= False;
end;

end.
