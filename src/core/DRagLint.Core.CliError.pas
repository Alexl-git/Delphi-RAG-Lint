unit DRagLint.Core.CliError;

/// <summary>The machine-readable REASON behind a CLI exit that shares its exit code with another
/// cause (owner ruling 2026-10-25, walkthrough row A14).</summary>
/// <remarks>
/// <para>Exit codes are unchanged: an unknown verb exits 2, an unknown flag exits 3 (the code
/// menu-tree / menu-drift / ask use for a stale index). A consumer such as featuregen tells them
/// apart by the reason: with --json one JSON object on stderr,
/// {"error":"unknown-flag","message":"...","flag":"--x"}; without --json a stderr line whose first
/// token is error[unknown-flag]:. Reasons: unknown-verb, unknown-flag, stale-index.</para>
/// <para>stdout is never touched, so a --json verb's stdout stays clean (run_json_error_stdout.ps1).</para>
/// </remarks>

interface

const
  /// <summary>Reason: the first positional token is not a verb (exit 2).</summary>
  CLI_ERR_UNKNOWN_VERB = 'unknown-verb';
  /// <summary>Reason: an argument no flag of the verb accepts (exit 3).</summary>
  CLI_ERR_UNKNOWN_FLAG = 'unknown-flag';
  /// <summary>Reason: an index a file of which changed since it was built (exit 3).</summary>
  CLI_ERR_STALE_INDEX = 'stale-index';

/// <summary>Formats the reason line: one JSON object when pAsJson, else a line starting error[reason]:.</summary>
/// <param name="pReason">One of the CLI_ERR_ constants.</param>
/// <param name="pMessage">Human text, appended after the stable token (text) or as "message" (JSON).</param>
/// <param name="pAsJson">True for the JSON object form.</param>
/// <param name="pKey">Optional extra JSON member name (e.g. 'flag', 'verb'); '' for none.</param>
/// <param name="pValue">The extra member's value.</param>
/// <returns>The single line, without a line terminator.</returns>
function CliErrorLine(const pReason, pMessage: string; pAsJson: Boolean; const pKey, pValue: string): string;

/// <summary>Writes CliErrorLine to stderr. Never writes stdout.</summary>
/// <param name="pReason">One of the CLI_ERR_ constants.</param>
/// <param name="pMessage">Human text.</param>
/// <param name="pAsJson">True for the JSON object form.</param>
/// <param name="pKey">Optional extra JSON member name; '' for none.</param>
/// <param name="pValue">The extra member's value.</param>
procedure WriteCliError(const pReason, pMessage: string; pAsJson: Boolean; const pKey, pValue: string);

/// <summary>True when --json appears among the raw command-line tokens (ParseArgs may not have finished).</summary>
/// <returns>True if any ParamStr is exactly --json.</returns>
function CommandLineWantsJson: Boolean;

implementation

uses
  System.SysUtils, System.JSON;

function CliErrorLine(const pReason, pMessage: string; pAsJson: Boolean; const pKey, pValue: string): string;
begin
  if not pAsJson then Exit('error[' + pReason + ']: ' + pMessage);
  var O:= TJSONObject.Create;
  try
    O.AddPair('error', pReason);
    O.AddPair('message', pMessage);
    if pKey <> '' then O.AddPair(pKey, pValue);
    Result:= O.ToJSON;
  finally
    O.Free;
  end;
end;

procedure WriteCliError(const pReason, pMessage: string; pAsJson: Boolean; const pKey, pValue: string);
begin
  Writeln(ErrOutput, CliErrorLine(pReason, pMessage, pAsJson, pKey, pValue));
end;

function CommandLineWantsJson: Boolean;
begin
  for var I:= 1 to ParamCount do
    if ParamStr(I) = '--json' then Exit(True);
  Result:= False;
end;

end.
