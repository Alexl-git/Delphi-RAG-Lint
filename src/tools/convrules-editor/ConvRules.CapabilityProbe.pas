unit ConvRules.CapabilityProbe;

{ R2 (owner design 2026-10-25): the pure decisions of the Convert tab's engine
  capability probe. The tab asks the engine its version (`--version`), then its
  capabilities (`info --json`), on a worker behind a wait window; when the wait
  passes INFO_TIMEOUT_MS the window ASKS whether to keep waiting. This unit decides
  which case the question names, what it and the status line say, how an answer is
  read, and whether the result may be cached for the session. No VCL, no engine
  call: pinned by ConvRulesModelTests. }

interface

const
  /// <summary>The oldest engine that has every capability this editor gates on and an
  /// engine has shipped: 1.28.3 added convert_qualify_fix (apply/1 qualify_fixes[]), the
  /// newest of them.</summary>
  /// <remarks>The dated capability keys in ConvRules.Engine and the version that added
  /// each: book_depth / progress_lines 1.20.6, inherited_instances 1.22.0, batch_units
  /// 1.23.0, descendant_warnings 1.25.0, inherited_retype 1.26.0, inherited_code_unconverted
  /// 1.26.7, cast_site_refusal / value_cast_strip_db / uses_reconcile / pas_uses 1.27.0,
  /// pas_uses_resolution 1.28.2, convert_qualify_fix 1.28.3 (CHANGELOG.md). glyph_stitch
  /// is left out on purpose: no engine reports it yet (1.33.0 does not), so no version
  /// could satisfy it. Raise this when the editor starts gating on a newer key.</remarks>
  REQUIRED_ENGINE_VERSION = '1.28.3';
  /// <summary>How long the probe may run before its wait window appears, in milliseconds:
  /// a healthy probe (~0.6 s for both calls) never flashes the window.</summary>
  PROBE_SHOW_AFTER_MS = 2000;
  /// <summary>The features a probe that did not answer leaves off -- the gates the Convert
  /// tab sets from the capability list, named as the user sees them.</summary>
  REDUCED_FEATURES_TEXT = 'batch mode, unit-rules books, inherited-instance notes, the Qualify buttons and pas_uses / cast-site rows';

type
  /// <summary>A drag-lint version's numeric part, e.g. 1.33.0 of "1.33.0-alpha".</summary>
  TEngineVersion = record
    /// <summary>Major number.</summary>
    Major: Integer;
    /// <summary>Minor number.</summary>
    Minor: Integer;
    /// <summary>Patch number.</summary>
    Patch: Integer;
  end;

  /// <summary>What the wait question says about the engine: the version it reported
  /// against REQUIRED_ENGINE_VERSION.</summary>
  TProbeCase = (
    /// <summary>Reported a version at or above the required one: the engine is fine, just slow.</summary>
    pcVersionOk,
    /// <summary>Reported a version below the required one: some features stay off even once it answers.</summary>
    pcVersionTooOld,
    /// <summary>Did not answer `--version` (yet), or answered something unreadable.</summary>
    pcVersionUnknown);

  /// <summary>How the capability probe ended.</summary>
  TProbeOutcome = (
    /// <summary>`info --json` exited 0 with an info object: its capability list is the truth
    /// (an empty one too -- an old engine without the key).</summary>
    poAnswered,
    /// <summary>The engine failed: non-zero exit, no info object, the backstop timeout.</summary>
    poFailed,
    /// <summary>The user chose not to wait; the call was cancelled before it answered.</summary>
    poNotWaited);

/// <summary>The version token of `drag-lint --version` output.</summary>
/// <param name="AOutput">The raw output; other lines (the "(loaded defaults from ...)"
/// line shares the pipe) are ignored.</param>
/// <returns>The text after "drag-lint " on the first line that starts with it, trimmed,
/// e.g. "1.33.0-alpha"; '' when no line does.</returns>
function EngineVersionText(const AOutput: string): string;

/// <summary>Reads the numeric part of a version text.</summary>
/// <param name="AText">E.g. "1.33.0-alpha" or "1.28.3"; a suffix after the patch number
/// (from the first character that is not a digit) is ignored.</param>
/// <param name="AVersion">The three numbers; Default(TEngineVersion) on failure.</param>
/// <returns>True when AText starts with three dot-separated decimal numbers.</returns>
function TryParseEngineVersion(const AText: string; out AVersion: TEngineVersion): Boolean;

/// <summary>Orders two versions numerically (1.28.10 is newer than 1.28.3).</summary>
/// <param name="A">Left version.</param>
/// <param name="B">Right version.</param>
/// <returns>Negative when A is older than B, 0 when equal, positive when newer.</returns>
function CompareEngineVersions(const A, B: TEngineVersion): Integer;

/// <summary>Which case the wait question names for a version text.</summary>
/// <param name="AVersionText">EngineVersionText of the `--version` answer; '' = none yet.</param>
/// <returns>pcVersionUnknown when AVersionText does not parse; otherwise pcVersionOk or
/// pcVersionTooOld by CompareEngineVersions against REQUIRED_ENGINE_VERSION.</returns>
/// <remarks>Only the numbers count: a pre-release of the required version (1.28.3-alpha)
/// is that version -- every pin is an -alpha build.</remarks>
function ProbeCaseFor(const AVersionText: string): TProbeCase;

/// <summary>Reads `info --json` output: is it an info object, and which capabilities
/// does it report true?</summary>
/// <param name="AInfoOutput">Raw output; the JSON is sliced from the first '{' to the last
/// '}' (the "(loaded defaults from ...)" line shares the pipe, before or after).</param>
/// <param name="ACaps">The keys under "capabilities" whose value is JSON true; [] when
/// the object has no such key (an engine older than 1.20.6) or on failure.</param>
/// <returns>True when the output holds a JSON object -- an answer, even with no
/// capabilities; False for no JSON, unparseable JSON or a non-object.</returns>
function TryParseInfoCapabilities(const AInfoOutput: string; out ACaps: TArray<string>): Boolean;

/// <summary>Classifies a finished probe.</summary>
/// <param name="AExitCode">The `info --json` exit code (ENGINE_OUTCOME_CANCELLED after a
/// cancel, ENGINE_OUTCOME_TIMEOUT at the backstop, -1 when it did not start).</param>
/// <param name="AParsed">TryParseInfoCapabilities' result on its output.</param>
/// <param name="AGaveUp">The user chose not to wait (the wait window's Do not wait / Esc / X).</param>
/// <returns>poAnswered when the engine exited 0 with an info object -- even if the user
/// chose not to wait in the same moment (owner design point 3: a real answer wins);
/// else poNotWaited when AGaveUp; else poFailed.</returns>
function ProbeOutcomeFor(AExitCode: Integer; AParsed, AGaveUp: Boolean): TProbeOutcome;

/// <summary>May the probe's result stand for the rest of the session?</summary>
/// <param name="AOutcome">The probe's outcome.</param>
/// <returns>True for poAnswered only. A failed or abandoned probe is NOT cached: the next
/// RefreshBooks (tab switch, Refresh) or Convert probes again (owner design point 4).</returns>
function ProbeIsCached(AOutcome: TProbeOutcome): Boolean;

/// <summary>The wait window's question once the probe has run past INFO_TIMEOUT_MS.</summary>
/// <param name="ACase">ProbeCaseFor of the version answer so far.</param>
/// <param name="AVersionText">That answer's version text ('' when unknown).</param>
/// <returns>One paragraph that names the case -- the right version and still answering,
/// older than REQUIRED_ENGINE_VERSION, or version unknown -- asks "Keep waiting?" and says
/// what not waiting turns off (REDUCED_FEATURES_TEXT) until the next check.</returns>
function WaitQuestionText(ACase: TProbeCase; const AVersionText: string): string;

/// <summary>The status line after a probe; '' when there is nothing to say.</summary>
/// <param name="AOutcome">The probe's outcome.</param>
/// <param name="ACase">ProbeCaseFor of its version answer.</param>
/// <param name="AVersionText">That answer's version text ('' when unknown).</param>
/// <returns>poNotWaited: "Capability check did not finish -- features ... off; they come
/// back on the next check ..."; poFailed: the same with "failed"; poAnswered with
/// pcVersionTooOld: the engine is older than required and the features it lacks are off;
/// poAnswered otherwise: ''.</returns>
function ProbeStatusText(AOutcome: TProbeOutcome; ACase: TProbeCase; const AVersionText: string): string;

implementation

uses
  System.SysUtils
  , System.JSON
  ;

const
  VERSION_PREFIX = 'drag-lint ';
  VERSION_PARTS  = 3;
  QUESTION_TAIL  = ' Keep waiting? If you do not wait, the editor runs without ' + REDUCED_FEATURES_TEXT + ' until the next check.';
  REDUCED_TAIL   = ' -- features off: ' + REDUCED_FEATURES_TEXT + '; they come back on the next check (Refresh, a tab switch or Convert).';

function EngineVersionText(const AOutput: string): string;
begin
  Result:= '';
  for var LLine: string in AOutput.Split([#13, #10], TStringSplitOptions.ExcludeEmpty) do
    if LLine.Trim.StartsWith(VERSION_PREFIX) then
      Exit(LLine.Trim.Substring(Length(VERSION_PREFIX)).Trim);
end;

function TryParseEngineVersion(const AText: string; out AVersion: TEngineVersion): Boolean;
var
  LNums: array[0..VERSION_PARTS - 1] of Integer;
begin
  AVersion:= Default(TEngineVersion);
  var LPos: Integer:= 1;
  for var I: Integer:= 0 to VERSION_PARTS - 1 do
  begin
    if I > 0 then
    begin
      if (LPos > Length(AText)) or (AText[LPos] <> '.') then
        Exit(False);
      Inc(LPos);
    end;
    var LStart: Integer:= LPos;
    while (LPos <= Length(AText)) and CharInSet(AText[LPos], ['0'..'9']) do
      Inc(LPos);
    if not TryStrToInt(Copy(AText, LStart, LPos - LStart), LNums[I]) then
      Exit(False);
  end;
  AVersion.Major:= LNums[0];
  AVersion.Minor:= LNums[1];
  AVersion.Patch:= LNums[2];
  Result:= True;
end;

function CompareEngineVersions(const A, B: TEngineVersion): Integer;
begin
  Result:= A.Major - B.Major;
  if Result = 0 then
    Result:= A.Minor - B.Minor;
  if Result = 0 then
    Result:= A.Patch - B.Patch;
end;

function ProbeCaseFor(const AVersionText: string): TProbeCase;
var
  LHave, LNeed: TEngineVersion;
begin
  if not TryParseEngineVersion(AVersionText, LHave) then
    Exit(pcVersionUnknown);
  TryParseEngineVersion(REQUIRED_ENGINE_VERSION, LNeed);
  Result:= if CompareEngineVersions(LHave, LNeed) >= 0 then pcVersionOk else pcVersionTooOld;
end;

function TryParseInfoCapabilities(const AInfoOutput: string; out ACaps: TArray<string>): Boolean;
var
  Root: TJSONValue ;
  Caps: TJSONObject;
begin
  ACaps := nil;
  Result:= False;
  // The "(loaded defaults from ...)" stderr line shares the pipe, before or after.
  var LFirst: Integer:= Pos('{', AInfoOutput);
  var LLast : Integer:= LastDelimiter('}', AInfoOutput);
  if (LFirst = 0) or (LLast < LFirst) then
    Exit;
  Root:= TJSONObject.ParseJSONValue(Copy(AInfoOutput, LFirst, LLast - LFirst + 1));
  try
    Result:= Root is TJSONObject;
    if Result and TJSONObject(Root).TryGetValue<TJSONObject>('capabilities', Caps) then
      for var LPair: TJSONPair in Caps do
        if LPair.JsonValue is TJSONTrue then
          ACaps:= ACaps + [LPair.JsonString.Value];
  finally
    Root.Free;
  end; // try
end; // function

function ProbeOutcomeFor(AExitCode: Integer; AParsed, AGaveUp: Boolean): TProbeOutcome;
begin
  if (AExitCode = 0) and AParsed then
    Result:= poAnswered
  else if AGaveUp then
    Result:= poNotWaited
  else
    Result:= poFailed;
end;

function ProbeIsCached(AOutcome: TProbeOutcome): Boolean;
begin
  Result:= AOutcome = poAnswered;
end;

function WaitQuestionText(ACase: TProbeCase; const AVersionText: string): string;
begin
  case ACase of
    pcVersionOk:
      Result:= Format('The engine is version %s (%s or newer is needed) and is still working on the capability check -- the machine may be busy.',
        [AVersionText, REQUIRED_ENGINE_VERSION]);
    pcVersionTooOld:
      Result:= Format('The engine is version %s, older than the %s this editor needs, and has not finished the capability check. Features it lacks stay off even once it answers.',
        [AVersionText, REQUIRED_ENGINE_VERSION]);
  else
    Result:= 'The engine did not report its version and has not finished the capability check.';
  end; // case
  Result:= Result + QUESTION_TAIL;
end;

function ProbeStatusText(AOutcome: TProbeOutcome; ACase: TProbeCase; const AVersionText: string): string;
begin
  case AOutcome of
    poNotWaited:
      Result:= 'Capability check did not finish' + REDUCED_TAIL;
    poFailed:
      Result:= 'Capability check failed (the engine did not answer info --json)' + REDUCED_TAIL;
  else
    Result:= if ACase = pcVersionTooOld then
      Format('Engine %s is older than %s, the oldest this editor fully supports: the features it lacks are off.', [AVersionText, REQUIRED_ENGINE_VERSION])
    else '';
  end; // case
end;

end.