unit DRagLint.CLI.CheckInit;

{ drag-lint 1.52 -- verb `check-init` (happens-before, rulings HB1-HB7).
  Scaffold created by lane FRAME: DRagLint.CLI.pas parses the flags and calls
  RunCheckInit in ONE dispatch line; everything else lives here. Lane HBSKEL
  owns this unit (its signature is the FRAME contract: changing it needs a
  HANDOVER to the CLI.pas dispatch line). }

interface

/// <summary>Runs `drag-lint check-init &lt;QName&gt; [--at &lt;file&gt;:&lt;line&gt;[:&lt;col&gt;]] --db &lt;db&gt;
/// [--json] [--explain] [--max-routines N]`.</summary>
/// <param name="pTarget">Positional QName (or --qname); '' when only --at names the target.</param>
/// <param name="pAt">--at value `file:line[:col]`, '' when absent.</param>
/// <param name="pDbPath">--db value, '' when absent (the verb resolves or refuses).</param>
/// <param name="pProject">--project value, '' when absent.</param>
/// <param name="pJson">--json (or --format json).</param>
/// <param name="pExplain">--explain: add roots and reasons to the answer.</param>
/// <param name="pMaxRoutines">--max-routines N; 0 = the verb's default budget.</param>
/// <returns>Process exit code: 0 all SET, 1 some MAY-BE-UNSET or NEVER-SET, 2 usage or other error.</returns>
/// <remarks>FRAME stub: prints `check-init: not implemented (1.52 scaffold)` on stderr and returns 2.</remarks>
function RunCheckInit(const pTarget, pAt, pDbPath, pProject: string; pJson, pExplain: Boolean;
  pMaxRoutines: Integer): Integer;

implementation

uses
  System.SysUtils
  ;

function RunCheckInit(const pTarget, pAt, pDbPath, pProject: string; pJson, pExplain: Boolean;
  pMaxRoutines: Integer): Integer;
begin
  Writeln(ErrOutput, 'check-init: not implemented (1.52 scaffold)');
  Result:= 2;
end;

end.
