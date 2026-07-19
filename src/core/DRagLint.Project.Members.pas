unit DRagLint.Project.Members;

// Pairs each project-owned .pas path with its sibling .dfm file (same base
// name, same directory) when one exists on disk. Read-only: does not parse
// .dpr/.dproj content and does not itself walk a compile closure -- callers
// pass in the closure's file list (e.g. TReconcileResult.ClosureFiles from
// DRagLint.Index.Reconcile). Consumed by the reconcile-project coherence
// checks (Task 3) to know which project members have a visual form
// counterpart.

interface

uses
  System.SysUtils
  , System.IOUtils
  ;

type
  /// <summary>One project-owned source file and its optional sibling .dfm.</summary>
  TProjectMember = record
    /// <summary>The .pas path as given (casing preserved).</summary>
    UnitPath: string;
    /// <summary>Absolute path to the sibling .dfm when HasDfm is True; '' otherwise.</summary>
    DfmPath: string;
    /// <summary>True when a same-base-name .dfm exists on disk beside UnitPath.</summary>
    HasDfm: Boolean;
  end;

  /// <summary>Pairs each .pas path in AUnitPaths with its sibling .dfm (same
  /// base name, same directory) when that .dfm exists on disk. The `.pas`
  /// extension check is case-insensitive; non-`.pas` entries pass through
  /// unchanged with HasDfm = False. Pure aside from the TFile.Exists disk
  /// check.</summary>
  /// <param name="AUnitPaths">Paths to pair, typically a project's compile closure.</param>
  /// <returns>One TProjectMember per input path, in the same order.</returns>
function PairDfmSiblings(const AUnitPaths: TArray<string>): TArray<TProjectMember>;

implementation

function PairDfmSiblings(const AUnitPaths: TArray<string>): TArray<TProjectMember>;
var
  I      : Integer;
  Path   : string ;
  DfmCand: string ;
begin
  SetLength(Result, Length(AUnitPaths));
  for I:= 0 to High(AUnitPaths) do
  begin
    Path:= AUnitPaths[I];
    Result[I].UnitPath:= Path;
    Result[I].DfmPath:= '';
    Result[I].HasDfm:= False;
    if SameText(TPath.GetExtension(Path), '.pas') then
    begin
      DfmCand:= TPath.ChangeExtension(Path, '.dfm');
      if TFile.Exists(DfmCand) then
      begin
        Result[I].DfmPath:= DfmCand;
        Result[I].HasDfm:= True;
      end;
    end;
  end; // for
end; // function

end.
