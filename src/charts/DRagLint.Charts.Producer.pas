unit DRagLint.Charts.Producer;

{ The report-producer seam (spec P2). Compare obtains every NEW report through this one
  interface. Step 1 has a single producer, TPowerShellProducer, which runs
  charts\src\Ask-Report.ps1 -Plain; later a Delphi producer replaces it question by
  question with no change to Compare. Pure types plus one default-options function: no
  IO here. }

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
    /// <summary>The Ask-Report script; '' resolves it (ResolveAskReportScript).</summary>
    ScriptPath : string;
    /// <summary>Wall-clock limit for one question in milliseconds; 0 waits without limit.</summary>
    TimeoutMs  : Cardinal;
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
    /// <param name="pOptions">Index override, staleness policy, engine, script and timeout.</param>
    /// <returns>Ok with the plain text on success; otherwise Ok False with the exit code and the
    /// reason. Never raises for a refusal or a missing tool.</returns>
    function Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
    /// <summary>Says what this producer is, for diagnostics.</summary>
    /// <returns>For example 'PowerShell Ask-Report.ps1 at C:\...\Ask-Report.ps1'.</returns>
    function Describe: string;
  end;

/// <summary>The options a caller starts from.</summary>
/// <returns>No override, AllowStale False, EnginePath = the running executable, ScriptPath '',
/// TimeoutMs = 10 minutes.</returns>
function DefaultProduceOptions: TProduceOptions;

implementation

uses
  System.SysUtils;

const
  DEFAULT_TIMEOUT_MS = 10 * 60 * 1000;

function DefaultProduceOptions: TProduceOptions;
begin
  Result:= Default(TProduceOptions);
  Result.EnginePath:= ParamStr(0);
  Result.TimeoutMs:= DEFAULT_TIMEOUT_MS;
end;

end.
