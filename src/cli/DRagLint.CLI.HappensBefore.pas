unit DRagLint.CLI.HappensBefore;

{ drag-lint 1.56 -- lane HB4: the `happens-before` verb.
  G-56: `happens-before --a <site> --b <site>` answers YES / NO / MAY (DRagLint.Query.HappensBefore.Verb).
  Parses its own flags (like uses-recover and syntax-count): DRagLint.CLI.ParseArgs returns before its flag loop
  for this verb, so the flags, the database resolution and the usage text all live here. Keep the accepted flags
  in ONE table named HAPPENS_BEFORE_FLAG_NAMES, so the docs-sync guard (check 9) can read it once INT teaches it this unit.
  DRagLint.CLI.Run dispatches here in one line. Scaffold created by lane W2FRAME (tranche 2); lane HB4 owns
  this unit. If the lane is cut, INT removes the dispatch line and the verb is unknown again. }

interface

/// <summary>Runs the `happens-before` verb from the process command line.</summary>
/// <returns>0 = answered; 1 = failure; 2 = usage error or refusal. The scaffold answers nothing and returns 2.</returns>
/// <remarks>Reads ParamStr(2..ParamCount) itself. The scaffold writes one ERROR line to stderr and nothing to stdout.</remarks>
function RunHappensBeforeVerb: Integer;

implementation

const
  EXIT_USAGE = 2;

function RunHappensBeforeVerb: Integer;
begin
  Writeln(ErrOutput, 'ERROR: happens-before: not built in this engine yet (1.56 lane HB4). Nothing was answered.');
  Result:= EXIT_USAGE;
end;

end.
