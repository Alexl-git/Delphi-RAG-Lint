unit DRagLint.Charts.Producer;

{ The report-producer seam (spec P2). Compare obtains every NEW report through this one
  interface. It began with one producer that ran charts\src\Ask-Report.ps1 -Plain; the
  Delphi producer (DRagLint.Charts.Producer.Delphi) replaced it question by question with no
  change to Compare, and since 2026-10-18 is the only one. Pure types plus one default-options
  function: no IO here. }

interface

uses
  DRagLint.Charts.ReportHeader;

const
  /// <summary>TProduceResult.ExitCode when the index is stale and AllowStale was not set
  /// (Ask-Report's exit 3).</summary>
  PRODUCER_EXIT_STALE = 3;

type
  /// <summary>How a producer should run one question.</summary>
  TProduceOptions = record
    /// <summary>S4: the index to answer from for the OLD side (-DbPath); '' resolves it through
    /// the command's -Project / -In as usual.</summary>
    DbOverride : string;
    /// <summary>S4: pass -AllowStale, so a stale index answers instead of refusing with exit 3.</summary>
    AllowStale : Boolean;
    /// <summary>The engine the producer should use (-Engine); DefaultProduceOptions sets the
    /// running executable.</summary>
    EnginePath : string;
    /// <summary>A file or folder in the charts scripts folder; '' resolves it by layout
    /// (DRagLint.Charts.Tools.ResolveChartsHome).</summary>
    ScriptPath : string;
    /// <summary>The SERVER index (-ServerDbPath); '' lets the producer pair it as usual.</summary>
    ServerDbOverride     : string;
    /// <summary>The SQL-script index (-SqlDbPath); '' lets the producer pair it as usual.</summary>
    SqlDbOverride        : string;
    /// <summary>The other side of crosses-boundary (-CounterpartDb); '' pairs it as usual.</summary>
    CounterpartDbOverride: string;
    /// <summary>Where the bundle folder is made (-OutRoot); '' keeps the producer's default.</summary>
    OutRoot              : string;
    /// <summary>The report-pairs.json to pair indexes from (-PairsFile); '' keeps the default.</summary>
    PairsFile            : string;
  end;

  /// <summary>What a producer made of one question.</summary>
  TProduceResult = record
    /// <summary>True when the question was answered (exit 0).</summary>
    Ok        : Boolean;
    /// <summary>Ask-Report's exit code: 0 answered, 1 refused, 2 setup (or could not run / timed
    /// out), 3 stale index.</summary>
    ExitCode  : Integer;
    /// <summary>The answer in plain form, header first (stdout, UTF-8 decoded).</summary>
    Text      : string;
    /// <summary>The 'ask-report:' message(s) when the exit code is not 0, joined with '; '.</summary>
    Reason    : string;
    /// <summary>The index paths from the INDEX lines, without any '(server)' style suffix.</summary>
    IndexPaths: TArray<string>;
    /// <summary>The path from the BUNDLE line; '' when there is none.</summary>
    BundlePath: string;
  end;

  /// <summary>Produces the plain-form report for one question.</summary>
  /// <remarks>Implementations must be callable from the owning thread only unless they say
  /// otherwise; the result is a value, nothing in it points back at the producer.</remarks>
  IReportProducer = interface
    ['{5D0B7A44-3C1E-4F6A-9B72-A8E4C5130F9D}']
    /// <summary>Answers one question.</summary>
    /// <param name="pCommand">The question and its explicit arguments (a parsed COMMAND line).</param>
    /// <param name="pOptions">Index override, staleness policy, engine and charts folder.</param>
    /// <returns>Ok with the plain text on success; otherwise Ok False with the exit code and the
    /// reason. Never raises for a refusal or a missing tool.</returns>
    function Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
    /// <summary>Says what this producer is, for diagnostics.</summary>
    /// <returns>For example 'Delphi in-process (who-writes)'.</returns>
    function Describe: string;
  end;

/// <summary>The options a caller starts from.</summary>
/// <returns>No override, AllowStale False, EnginePath = the running executable, ScriptPath ''.</returns>
function DefaultProduceOptions: TProduceOptions;

implementation

uses
  System.SysUtils;

function DefaultProduceOptions: TProduceOptions;
begin
  Result:= Default(TProduceOptions);
  Result.EnginePath:= ParamStr(0);
end;

end.
