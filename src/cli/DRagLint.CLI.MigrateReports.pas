unit DRagLint.CLI.MigrateReports;

{ drag-lint 1.56 -- lane QE-3: verb `migrate-reports`, which rewrites saved reports / snapshots
  (.txt, .csv, graph) from the old command line form to the CLI style one where the old form is
  unambiguous, and lists what it left alone. The verb reads its own flags from the command line.
  Scaffold created by lane FRAME-1; lane QE-3 owns this unit. The verb is NOT in the dispatch chain
  of DRagLint.CLI.pas yet: FRAME-1 adds that line together with the --help / README / AI-USAGE text
  (the docs-sync guard reads the chain), on a request from the lane. }

interface

const
  /// <summary>The verb name this unit runs.</summary>
  MIGRATE_REPORTS_VERB = 'migrate-reports';

/// <summary>Runs `drag-lint migrate-reports ...`.</summary>
/// <returns>0 = ok; 1 = failure; 2 = usage error. The scaffold returns 2.</returns>
/// <remarks>Reads ParamStr itself (ParamStr(1) is the verb). Not thread-safe.</remarks>
function RunMigrateReportsVerb: Integer;

implementation

const
  EXIT_USAGE = 2;

function RunMigrateReportsVerb: Integer;
begin
  Writeln(ErrOutput, MIGRATE_REPORTS_VERB, ': not implemented');
  Result:= EXIT_USAGE;
end;

end.
