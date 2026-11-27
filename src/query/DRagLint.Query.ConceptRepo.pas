unit DRagLint.Query.ConceptRepo;

{ drag-lint 1.56 -- lane CON-Q: `query --concept` over the field-repository copy that
  `index --project` puts into the project index (DRagLint.Index.RepoCopy): captions, display
  labels, grid column captions, hints, table descriptions; each hit carries its place.
  DRagLint.CLI.DoQueryConcept calls TryRunConceptRepoQuery in ONE line, before its own
  identifier / doc-prose search. This unit runs its own SQL; it adds nothing to the store interface.
  Scaffold created by lane FRAME-1; lane CON-Q owns this unit. }

interface

type
  /// <summary>One `query --concept` request, as DRagLint.CLI parsed it.</summary>
  TConceptRepoQuery = record
    /// <summary>The project index (an existing .sqlite file), the first resolved --db.</summary>
    DbPath: string;
    /// <summary>The --concept words; not empty.</summary>
    Words: string;
    /// <summary>The --kind value (comma-separated); '' = every kind.</summary>
    Kinds: string;
    /// <summary>Row cap; greater than 0.</summary>
    Limit: Integer;
    /// <summary>--json.</summary>
    AsJson: Boolean;
  end;

/// <summary>Answers `query --concept` from the repository copy in the project index, when this
/// unit takes the request.</summary>
/// <param name="pQuery">The request.</param>
/// <param name="pExitCode">The verb's exit code; meaningful only when the result is True.</param>
/// <returns>True = this unit printed the whole answer and the caller exits with pExitCode;
/// False = nothing was printed and the caller runs its own search as before. The scaffold
/// returns False for every request.</returns>
/// <remarks>Read-only. Writes to stdout only when it returns True.</remarks>
function TryRunConceptRepoQuery(const pQuery: TConceptRepoQuery; out pExitCode: Integer): Boolean;

implementation

function TryRunConceptRepoQuery(const pQuery: TConceptRepoQuery; out pExitCode: Integer): Boolean;
begin
  pExitCode:= 0;
  Result:= False;
end;

end.
