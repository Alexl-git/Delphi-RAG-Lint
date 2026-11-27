unit DRagLint.CLI.Sbom;

{ drag-lint 1.56 -- lane SBOM-1: the `sbom` verb.
  G-49: `sbom --project X.dproj [--out F]` writes a CycloneDX 1.6 JSON document (DRagLint.Report.CycloneDx).
  Parses its own flags (like uses-recover and syntax-count): DRagLint.CLI.ParseArgs returns before its flag loop
  for this verb, so the flags, the database resolution and the usage text all live here. Keep the accepted flags
  in ONE table named SBOM_FLAG_NAMES, so the docs-sync guard (check 9) can read it once INT teaches it this unit.
  DRagLint.CLI.Run dispatches here in one line. Scaffold created by lane W2FRAME (tranche 2); lane SBOM-1 owns
  this unit. If the lane is cut, INT removes the dispatch line and the verb is unknown again. }

interface

/// <summary>Runs the `sbom` verb from the process command line.</summary>
/// <returns>0 = answered; 1 = failure; 2 = usage error or refusal. The scaffold answers nothing and returns 2.</returns>
/// <remarks>Reads ParamStr(2..ParamCount) itself. The scaffold writes one ERROR line to stderr and nothing to stdout.</remarks>
function RunSbomVerb: Integer;

implementation

const
  EXIT_USAGE = 2;

function RunSbomVerb: Integer;
begin
  Writeln(ErrOutput, 'ERROR: sbom: not built in this engine yet (1.56 lane SBOM-1). Nothing was answered.');
  Result:= EXIT_USAGE;
end;

end.
