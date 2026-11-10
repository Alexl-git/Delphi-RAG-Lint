unit DRagLint.Refactor.VerbShape;

// ---------------------------------------------------------------------------
// The plumbing the design-stage refactor verbs (lazy-init, extract-interface) share: the JSON / text error line and the
// "apply ONE rewritten file through the scratch gate" block. One copy here instead of two (150 DQ item 1; the duplicate-code
// markers of 147 INT). Behaviour-identical to the per-verb code it replaced.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, FireDAC.Comp.Client,
  DRagLint.Refactor.CompileGate;  // dl:ok uses-global-census@4ebc -- the CompileGate globals travel with the gated refactor verbs by design

/// <summary>Prints a verb's error: a JSON object {schema, error, exit_code: 2} when pJson, else `ERROR: message`.</summary>
/// <param name="pJson">True for --json output.</param>
/// <param name="pSchema">The verb's schema id, e.g. 'lazy-init/1'.</param>
/// <param name="pMessage">The error text.</param>
/// <returns>The error exit code, 2.</returns>
/// <remarks>Writes to stdout (the verbs' existing contract); not thread-safe.</remarks>
function ReportVerbError(pJson: Boolean; const pSchema, pMessage: string): Integer;

type
  /// <summary>The arguments of ApplyOneFileThroughScratch that come from the verb's options.</summary>
  TOneFileApplyArgs = record
    /// <summary>The verb's name, shown in the progress lines and the recovery.txt header.</summary>
    Verb: string;
    /// <summary>What follows `--apply: ` in the recovery.txt header (the routine / interface name).</summary>
    HeaderTail: string;
    /// <summary>--project; expanded by the helper.</summary>
    Project: string;
    /// <summary>--platform; '' = Win64.</summary>
    Platform: string;
    /// <summary>--rsvars; '' = the registry's Studio.</summary>
    RsVars: string;
    /// <summary>--build-timeout in seconds as typed; 0 / non-numeric = no limit.</summary>
    BuildTimeout: string;
    /// <summary>--no-backup.</summary>
    NoBackup: Boolean;
    /// <summary>The existing file to rewrite, absolute.</summary>
    FilePath: string;
  end;

/// <summary>Applies ONE rewritten file through the scratch gate and removes the run's scratch build folder.</summary>
/// <param name="pConn">The index connection the gate reads the project's own roots from.</param>
/// <param name="pArgs">The verb's options (see TOneFileApplyArgs).</param>
/// <param name="pBytes">Its full new content, already encoded.</param>
/// <returns>The gate's outcome; the caller maps it to its exit code.</returns>
/// <remarks>Sets the process-wide CompileGate build-timeout global; a locked scratch log is reported to stderr, never fatal.</remarks>
function ApplyOneFileThroughScratch(pConn: TFDConnection; const pArgs: TOneFileApplyArgs; const pBytes: TBytes): TGateOutcome;

implementation

uses
  System.IOUtils, System.JSON, Winapi.Windows,
  DRagLint.Refactor.ScratchGate;

const
  CExitError = 2;
  CMsPerSec  = 1000;

function ReportVerbError(pJson: Boolean; const pSchema, pMessage: string): Integer;
begin
  Result:= CExitError;
  if pJson then
  begin
    var J:= TJSONObject.Create;
    try
      J.AddPair('schema', pSchema);
      J.AddPair('error', pMessage);
      J.AddPair('exit_code', TJSONNumber.Create(CExitError));
      Writeln(J.Format(2));
    finally
      J.Free;
    end;
  end
  else Writeln('ERROR: ', pMessage);
end;

function ApplyOneFileThroughScratch(pConn: TFDConnection; const pArgs: TOneFileApplyArgs; const pBytes: TBytes): TGateOutcome;
begin
  var Secs:= StrToIntDef(pArgs.BuildTimeout, 0);
  GBuildTimeoutMs:= if Secs <= 0 then INFINITE else Cardinal(Secs) * CMsPerSec;
  var Req:= Default(TGateRequest);
  Req.Project := ExpandFileName(pArgs.Project);
  Req.Platform:= pArgs.Platform;
  Req.Verb    := pArgs.Verb;
  Req.RsVars  := if pArgs.RsVars <> '' then ExpandFileName(pArgs.RsVars) else '';
  Req.NoBackup:= pArgs.NoBackup;
  Req.Header  := Format('[%s] %s --apply: %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), pArgs.Verb, pArgs.HeaderTail]);
  Req.LogDir  := FreshScratchName('_build');
  var F: TGateFile;
  F.Path := pArgs.FilePath;
  F.Bytes:= pBytes;
  Req.Files:= [F];
  Result:= ApplyThroughScratch(pConn, Req);
  if not GScratchCited and TDirectory.Exists(Req.LogDir) then
  try
    TDirectory.Delete(Req.LogDir, True);  // dl:ok taint-path-traversal@ff48 -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project
  except
    on EInOutError do Writeln(ErrOutput, 'drag-lint: note: scratch not deleted: ', Req.LogDir); // best effort: a locked log must not change the result
  end;
end;

end.
