unit DRagLint.CLI.RepoDfmWrite;

{ drag-lint 1.54 -- lane TT-DFMWRITE: the `repo` sub-verbs of repository -> DFM. DRagLint.CLI.Repo
  resolves the repository path and dispatches here in ONE line.
  Scaffold created by lane FRAME: it accepts no sub-verb until the lane names one. }

interface

const
  /// <summary>This unit's part of the `repo` sub-verb list in the "use one of" message.</summary>
  /// <remarks>Empty = none; otherwise starts with ', ' (', name').</remarks>
  REPO_DFMWRITE_SUBS = '';

/// <summary>True for a sub-verb this unit runs.</summary>
/// <param name="pSub">The `repo` sub-verb.</param>
/// <returns>False for every name while the unit is a scaffold.</returns>
function IsRepoDfmWriteSub(const pSub: string): Boolean;

/// <summary>Runs one of this unit's `repo` sub-verbs.</summary>
/// <param name="pSub">The sub-verb, IsRepoDfmWriteSub(pSub) is True.</param>
/// <param name="pPath">The repository file (already resolved from --repo / --project).</param>
/// <param name="pJson">--json.</param>
/// <returns>0 = ok; 1 = failure; 2 = usage error. The scaffold returns 2.</returns>
function RunRepoDfmWriteVerb(const pSub, pPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils;

const
  EXIT_USAGE = 2;
  SUB_VERB   = ''; // the lane names its sub-verb here; featuregen reads it from the SameText below

function IsRepoDfmWriteSub(const pSub: string): Boolean;
begin
  Result:= (SUB_VERB <> '') and SameText(pSub, SUB_VERB);
end;

function RunRepoDfmWriteVerb(const pSub, pPath: string; pJson: Boolean): Integer;
begin
  if not pJson then Writeln(ErrOutput, 'repo ', pSub, ': not implemented ', pPath);
  Result:= EXIT_USAGE;
end;

end.
