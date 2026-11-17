unit DRagLint.CLI.Repo;

{ drag-lint 1.52 -- verb family `repo` (TableTools field repository, PLAN D10/D11;
  docs\superpowers\plans\2026-11-16-tabletools-phase1.md section 6).
  Scaffold created by lane FRAME: DRagLint.CLI.pas parses the flags and calls
  RunRepoVerb in ONE dispatch line; everything else lives here. Lane TTE owns
  this unit (its signature is the FRAME contract). }

interface

/// <summary>Runs `drag-lint repo &lt;sub-verb&gt; ...`: init, info, import-fb, seed-fb,
/// refresh-schema, backup, restore, gen-memtable, gen-param-array, gen-orm, update-orm,
/// gen-dataservice (PLAN D11).</summary>
/// <param name="pSub">The sub-verb (first positional after `repo`), '' when absent.</param>
/// <param name="pRepo">--repo path, '' when absent (then --project decides the default path).</param>
/// <param name="pProject">--project value, '' when absent.</param>
/// <param name="pConnection">--connection Firebird connection string, '' when absent.</param>
/// <param name="pInFile">--in value, '' when absent.</param>
/// <param name="pOutFile">--output value, '' when absent.</param>
/// <param name="pReplace">--replace.</param>
/// <param name="pJson">--json (or --format json).</param>
/// <returns>Process exit code per sub-verb (plan section 6); 1 = usage error.</returns>
/// <remarks>FRAME stub: prints `repo: not implemented (1.52 scaffold)` on stderr and returns 1.</remarks>
function RunRepoVerb(const pSub, pRepo, pProject, pConnection, pInFile, pOutFile: string;
  pReplace, pJson: Boolean): Integer;

implementation

uses
  System.SysUtils
  ;

function RunRepoVerb(const pSub, pRepo, pProject, pConnection, pInFile, pOutFile: string;
  pReplace, pJson: Boolean): Integer;
begin
  Writeln(ErrOutput, 'repo: not implemented (1.52 scaffold)');
  Result:= 1;
end;

end.
