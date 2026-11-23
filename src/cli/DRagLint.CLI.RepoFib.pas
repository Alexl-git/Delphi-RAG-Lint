unit DRagLint.CLI.RepoFib;

{ drag-lint 1.54 -- lane TT-FIB: the `repo` sub-verbs of the FIB$ reader inventory. It reads
  the project index, no field repository: DRagLint.CLI.Repo dispatches here before it resolves one.
  Scaffold created by lane FRAME: it accepts no sub-verb until the lane names one. }

interface

const
  /// <summary>This unit's part of the `repo` sub-verb list in the "use one of" message.</summary>
  /// <remarks>Empty = none; otherwise starts with ', ' (', name').</remarks>
  REPO_FIB_SUBS = '';

/// <summary>True for a sub-verb this unit runs.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>False for every name while the unit is a scaffold.</returns>
function IsRepoFibSub(const pSub: string): Boolean;

/// <summary>Runs one of this unit's `repo` sub-verbs.</summary>
/// <param name="pSub">The sub-verb, IsRepoFibSub(pSub) is True.</param>
/// <param name="pProject">--project, '' when absent.</param>
/// <param name="pOutFile">--output, '' when absent.</param>
/// <param name="pJson">--json.</param>
/// <returns>0 = ok; 1 = failure; 2 = usage error. The scaffold returns 2.</returns>
function RunRepoFibVerb(const pSub, pProject, pOutFile: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils;

const
  EXIT_USAGE = 2;
  SUB_VERB   = ''; // the lane names its sub-verb here; featuregen reads it from the SameText below

function IsRepoFibSub(const pSub: string): Boolean;
begin
  Result:= (SUB_VERB <> '') and SameText(pSub, SUB_VERB);
end;

function RunRepoFibVerb(const pSub, pProject, pOutFile: string; pJson: Boolean): Integer;
begin
  if not pJson then Writeln(ErrOutput, 'repo ', pSub, ': not implemented ', pProject, ' ', pOutFile);
  Result:= EXIT_USAGE;
end;

end.
