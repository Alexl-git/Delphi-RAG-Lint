unit DRagLint.Lint.MarkerHash;

{ Versioned review-marker hashes for the seven whole-routine metric rules
  (v1511 MARK, Y4 / docs\INBOX-yadf-fp-hunt-151.md FP-4).

  WHY. The 1.51.0 marker hash for a routine metric is HashWindow(header)|metric
  (RuleCatalog.MetricHash). When the ENGINE changes how it counts -- wave 147:
  deep-nesting began counting the statement ifElse node (AstChecks), grammar
  v1.4.4 re-parsed if-with-else statements that cyclomatic / cognitive had read
  as uncounted exprIf -- every reviewed routine whose number moved is reported
  stale although nobody touched it. YADF: 10 of 10 stale markers were that.

  THE NEW HASH keeps the marker grammar (`rule@hhhh`, four hex digits) and
  splits the digits:
    * three = SHA2('v2m|' + header + '|' + metric + '|' + version)
    * one   = SHA2('v2b|' + header + '|' + routine-body tokens + '|' + version)
  where version is the rule's measure-algorithm version (ALGO_VERSIONS).
  The verdict (MarkerVerdict):
    1. the legacy 1.51.0 hash matches          -> verified (old markers, no re-stamp);
    2. the metric part matches at ANY version  -> verified (a body edit that does
       not move the number stays silent -- T3, run_marker_metric_scope check 4);
    3. the body part matches at an OLDER version -> re-measured: the routine is
       unchanged since the stamp and only the counting moved; suppressed;
    4. otherwise                               -> stale (growth under the same
       algorithm, or an edited body under a new one).
  Three hex digits keep a moved metric detected 4095 times in 4096; the body
  digit only decides between "re-measured" and "stale" after an algorithm bump.

  Lives outside DRagLint.Lint.ReviewMarker for the reason RuleCatalog.MetricHash
  does: that unit is mirrored byte-for-byte into YADF (run_reviewmarker_yadf_mirror). }

interface

type
  /// <summary>The outcome of checking one `dl:ok` hash against a finding.</summary>
  /// <remarks>mvRemeasured suppresses like mvVerified: the routine is unchanged
  /// since the review and only the engine's measure-algorithm version moved.
  /// mvLegacy (v152 MARK, ruling B3) also suppresses: a routine-metric marker
  /// stamped under the 1.51.0 "v1" header|metric hash that still matches. Callers
  /// that only ask "is it stale" compare against mvStale and need no change;
  /// callers that report (the CLI lint hint) treat mvRemeasured and mvLegacy
  /// alike via NeedsRestampHint.</remarks>
  TMarkerVerdict = (mvVerified, mvRemeasured, mvLegacy, mvStale);

const
  /// <summary>Rule id of the hint emitted when a still-valid marker was
  /// re-measured under the v2 hash (default ON, severity hint).</summary>
  RULE_MARKER_REMEASURED = 'review-marker-remeasured';

/// <summary>Whether a verdict that suppressed a finding deserves the
/// `review-marker-remeasured` hint.</summary>
/// <param name="AVerdict">The result of MarkerVerdict.</param>
/// <returns>True for mvRemeasured and mvLegacy: the marker still answers for the
/// code but was not stamped under the current hash. False for mvVerified and
/// mvStale (stale has its own review-marker-stale hint).</returns>
function NeedsRestampHint(AVerdict: TMarkerVerdict): Boolean;

/// <summary>The message of the `review-marker-remeasured` hint.</summary>
/// <param name="ARuleId">The marker's rule id.</param>
/// <param name="AVerdict">mvRemeasured or mvLegacy; selects the cause wording.</param>
/// <param name="AFindingLine">1-based anchor line of the suppressed finding, for the
/// re-stamp command.</param>
/// <returns>One ASCII line naming the rule, why it was re-measured and the
/// command that re-stamps it (`allow --fix-line N --fix-rule R`).</returns>
/// <remarks>Pure.</remarks>
function RemeasuredHintText(const ARuleId: string; AVerdict: TMarkerVerdict;
  AFindingLine: Integer): string;

/// <summary>The hash a NEW `dl:ok` should carry for a finding (what `allow`
/// writes).</summary>
/// <param name="ALines">The finding's file, one entry per line.</param>
/// <param name="ARuleId">The finding's rule id.</param>
/// <param name="AStartLine">1-based anchor line (TLintFinding.StartLine).</param>
/// <param name="AMetric">The finding's measured value; ignored for a non-metric
/// rule.</param>
/// <returns>Four lowercase hex digits: the versioned hash for a routine-metric
/// rule, the 1.51.0 hash (RuleCatalog.MarkerExpectedHash as it was) for every
/// other rule.</returns>
/// <remarks>RuleCatalog.MarkerExpectedHash is to delegate here (HANDOVER INT);
/// this unit never calls it back. Pure apart from the
/// DRAGLINT_TEST_METRIC_ALGO_BUMP test hook (environment read).</remarks>
function ExpectedHash(const ALines: TArray<string>; const ARuleId: string;
  AStartLine, AMetric: Integer): string;

/// <summary>Whether a `dl:ok` hash still answers for a finding.</summary>
/// <param name="ALines">The finding's file, one entry per line.</param>
/// <param name="ARuleId">The finding's rule id.</param>
/// <param name="AMarkerHash">The hash the marker carries (any case).</param>
/// <param name="AStartLine">1-based anchor line (TLintFinding.StartLine).</param>
/// <param name="AMetric">The finding's measured value (TLintFinding.Metric).</param>
/// <returns>mvVerified, mvRemeasured or mvStale -- the order of checks is in the
/// unit comment.</returns>
/// <remarks>The ONE verification every marker checker must use once
/// MarkerExpectedHash delegates to ExpectedHash: comparing a hash for equality with
/// ExpectedHash would reject every legacy marker. Pure apart from the test hook.</remarks>
function MarkerVerdict(const ALines: TArray<string>; const ARuleId, AMarkerHash: string;
  AStartLine, AMetric: Integer): TMarkerVerdict;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Hash,
  System.Generics.Collections,
  DRagLint.Lint.ReviewMarker,
  DRagLint.Lint.RuleCatalog;  // dl:ok circular-uses@cc45 -- implementation-section only, by design (v1511 Y4 HANDOVER): RuleCatalog.MarkerExpectedHash delegates to MarkerHash.ExpectedHash; MarkerHash.LegacyExpectedHash never calls back

type
  TAlgoVersion = record
    RuleId : string;
    Version: Integer;
  end;

const
  { Version 1 = the counting of engine 1.51.1 (ifElse counted by deep-nesting,
    grammar v1.4.4 if-with-else counted by cyclomatic and cognitive).
    deep-nesting 2 = lane AST 2fc9770ec, also 1.51.1: control statements only --
    if-expressions and try..finally no longer nest, try..except still does. A marker
    stamped by a 1.51.1 build without that change carries version 1 and is
    re-measured, not stale. Bump an entry whenever its checker, or a grammar
    change, moves the value it reports for unchanged code.
    cyclomatic-complexity 2 / cognitive-complexity 2 = 1.52 GA-1: an if-EXPRESSION
    (exprIf) is a decision point (owner ruling 2026-11-18). }
  ALGO_VERSIONS: array[0..6] of TAlgoVersion = (
    (RuleId: 'too-many-exit-points' ; Version: 1),
    (RuleId: 'cyclomatic-complexity'; Version: 2),
    (RuleId: 'cognitive-complexity' ; Version: 2),
    (RuleId: 'method-too-long'      ; Version: 1),
    (RuleId: 'too-many-locals'      ; Version: 1),
    (RuleId: 'too-many-parameters'  ; Version: 1),
    (RuleId: 'deep-nesting'         ; Version: 2));

  { Test hook: `<rule>:+<n>[,<rule>:+<n>]` -- version + 1 and measured value + n,
    so a runner can simulate an engine change in counting. }
  ALGO_BUMP_ENV = 'DRAGLINT_TEST_METRIC_ALGO_BUMP';
  METRIC_DIGITS = 3;   { hex digits of the metric part; HASH_DIGITS - this = the body part }
  HASH_DIGITS   = 4;   { the marker grammar's hash length }
  BODY_DIGITS   = 8;   { RoutineBodyHash length }
  MAX_ROUTINE_LINES = 20000;
  LAST_ASCII    = #127;

{ The test hook's delta for ARuleId, or -1 when the hook does not name it. }
function TestBump(const ARuleId: string): Integer;
var
  Item, Delta: string;
  Colon      : Integer;
begin
  Result:= -1;
  for Item in GetEnvironmentVariable(ALGO_BUMP_ENV).Split([',']) do
  begin
    Colon:= Pos(':', Item);
    if (Colon = 0) or not SameText(Trim(Copy(Item, 1, Colon - 1)), ARuleId) then Continue;
    Delta:= Trim(Copy(Item, Colon + 1, MaxInt));
    if Delta.StartsWith('+') then Delta:= Copy(Delta, 2, MaxInt);
    Exit(StrToIntDef(Delta, 0));
  end;
end;

{ The measure-algorithm version of a routine-metric rule; 0 for any other rule. }
function MetricAlgoVersion(const ARuleId: string): Integer;
begin
  Result:= 0;
  for var A: TAlgoVersion in ALGO_VERSIONS do
    if SameText(A.RuleId, ARuleId) then
    begin
      Result:= A.Version;
      Break;
    end;
  if (Result > 0) and (TestBump(ARuleId) >= 0) then Inc(Result);
end;

{ The value the CURRENT algorithm reports: AMetric, plus the test hook's delta. }
function CurrentMetric(const ARuleId: string; AMetric: Integer): Integer;
begin
  Result:= AMetric;
  var Bump: Integer:= TestBump(ARuleId);
  if Bump > 0 then Inc(Result, Bump);
end;

function IsIdentStart(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (C > LAST_ASCII);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= IsIdentStart(C) or CharInSet(C, ['0'..'9']);
end;

function IsHeaderWord(const AWord: string): Boolean;
begin
  Result:= MatchText(AWord, ['procedure', 'function', 'constructor', 'destructor', 'operator']);
end;

{ A header word after one of these is a procedural TYPE, not a routine. }
function IsTypePrefix(const APrev: string): Boolean;
begin
  Result:= MatchText(APrev, ['=', ':', '(', ',', 'of', 'to']);
end;

{ The end of the string literal opening at S[AFrom]: the index of its closing quote
  (a doubled quote is an escaped one), or Length(S) when it runs off the line. }
function LiteralEnd(const S: string; AFrom: Integer): Integer;
begin
  Result:= AFrom + 1;
  while Result <= Length(S) do
  begin
    if S[Result] = '''' then
    begin
      if (Result < Length(S)) and (S[Result + 1] = '''') then Inc(Result)
      else Exit;
    end;
    Inc(Result);
  end;
  Result:= Length(S);
end;

type
  { A one-line-at-a-time Delphi token reader that carries block-comment state
    across lines. Comments and whitespace yield nothing; identifiers come back
    lowercased; literals verbatim; a one-line compiler directive lowercased. }
  TTokenReader = record
    InBrace: Boolean;
    InParen: Boolean;
    function Next(const S: string; var I: Integer; out AToken: string): Boolean;
  end;

function TTokenReader.Next(const S: string; var I: Integer; out AToken: string): Boolean;
var
  J: Integer;
begin
  AToken:= '';
  while I <= Length(S) do
  begin
    if InBrace then
      InBrace:= S[I] <> '}'
    else if InParen then
    begin
      if (S[I] = '*') and (I < Length(S)) and (S[I + 1] = ')') then
      begin
        InParen:= False;
        Inc(I);
      end;
    end
    else if (S[I] = '/') and (I < Length(S)) and (S[I + 1] = '/') then
      Break
    else if S[I] = '{' then
    begin
      J:= Pos('}', S, I);
      if (I < Length(S)) and (S[I + 1] = '$') and (J > 0) then
      begin
        AToken:= LowerCase(Copy(S, I, J - I + 1));
        I:= J + 1;
        Exit(True);
      end;
      InBrace:= True;
    end
    else if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = '*') then
    begin
      InParen:= True;
      Inc(I);
    end
    else if S[I] = '''' then
    begin
      J:= LiteralEnd(S, I);
      AToken:= Copy(S, I, J - I + 1);
      I:= J + 1;
      Exit(True);
    end
    else if IsIdentStart(S[I]) then
    begin
      J:= I;
      while (J <= Length(S)) and IsIdentChar(S[J]) do Inc(J);
      AToken:= LowerCase(Copy(S, I, J - I));
      I:= J;
      Exit(True);
    end
    else if not CharInSet(S[I], [' ', #9]) then
    begin
      AToken:= S[I];
      Inc(I);
      Exit(True);
    end;
    Inc(I);
  end;
  Result:= False;
end;

type
  { Where a routine ends. Pending counts routine headers whose body has not closed
    (the anchored routine plus any local routine before its `begin`); Blocks is
    the stack of open begin/try/case/asm/record, True for a body block
    (begin/asm). A body block closing at depth 0 completes one pending routine;
    the anchored routine is done when Pending returns to 0. A header at block
    depth > 0 is an anonymous method inside a body. }
  TRoutineExtent = record
    Blocks : TStack<Boolean>;
    Pending: Integer;
    Done   : Boolean;
    { False when the scan must give up (no body to hash). }
    function Feed(const AWord, APrev: string): Boolean;
  end;

function TRoutineExtent.Feed(const AWord, APrev: string): Boolean;
begin
  Result:= True;
  if (APrev = '.') or (APrev = '&') then Exit;   { a member or escaped identifier }
  if IsHeaderWord(AWord) then
  begin
    if (Blocks.Count = 0) and not IsTypePrefix(APrev) then Inc(Pending);
  end
  else if MatchText(AWord, ['forward', 'external']) then
  begin
    if Blocks.Count > 0 then Exit;
    Dec(Pending);
    Result:= Pending > 0;
  end
  else if MatchText(AWord, ['begin', 'try', 'case', 'asm', 'record']) then
    Blocks.Push(MatchText(AWord, ['begin', 'asm']))
  else if AWord = 'end' then
  begin
    if Blocks.Count = 0 then Exit(False);
    if Blocks.Pop and (Blocks.Count = 0) then
    begin
      Dec(Pending);
      Done:= Pending = 0;
    end;
  end;
end;

{ A hash of a routine's tokens, from its header line (1-based AHeaderLine) to the
  `end` that closes it: eight hex digits, or '' when no routine opens on that line
  or its end is not found (unbalanced blocks, a variant record, a forward
  declaration). Comments, whitespace and identifier case are ignored, so a dl:ok
  edit, re-indent or re-comment does not change it. }
function RoutineBodyHash(const ALines: TArray<string>; AHeaderLine: Integer): string;
var
  SB    : TStringBuilder;
  Reader: TTokenReader;
  Extent: TRoutineExtent;
  Prev  : string;
  Tok   : string;
  I     : Integer;
begin
  Result:= '';
  if (AHeaderLine < 1) or (AHeaderLine > Length(ALines)) then Exit;
  SB:= TStringBuilder.Create;
  Extent:= Default(TRoutineExtent);
  Extent.Blocks:= TStack<Boolean>.Create;
  try
    Reader:= Default(TTokenReader);
    Prev:= '';
    for var LineIdx: Integer:= AHeaderLine - 1 to Min(High(ALines), AHeaderLine + MAX_ROUTINE_LINES) do
    begin
      I:= 1;
      while (not Extent.Done) and Reader.Next(ALines[LineIdx], I, Tok) do
      begin
        SB.Append(Tok).Append(' ');
        if not Extent.Feed(Tok, Prev) then Exit;
        Prev:= Tok;
      end;
      if Extent.Done then Exit(LowerCase(Copy(THashSHA2.GetHashString(SB.ToString), 1, BODY_DIGITS)));
      { The header line must open a routine, or there is no body to hash. }
      if Extent.Pending = 0 then Exit;
    end;
  finally
    Extent.Blocks.Free;
    SB.Free;
  end;
end;

{ The 1.51.0 marker hash (RuleCatalog.MarkerExpectedHash before this unit), kept so
  every marker stamped until now keeps verifying. Never calls MarkerExpectedHash,
  which is to delegate to ExpectedHash. }
function LegacyExpectedHash(const ALines: TArray<string>; const ARuleId: string;
  AStartLine, AMetric: Integer): string;
begin
  Result:= TReviewMarkers.HashWindow(ALines, DocCommentMarkerLine(ALines, AStartLine) - 1);
  if IsRoutineMetricRule(ARuleId) then Result:= MetricHash(Result, AMetric);
end;

function HexPrefix(const AText: string; ADigits: Integer): string;
begin
  Result:= LowerCase(Copy(THashSHA2.GetHashString(AText), 1, ADigits));
end;

{ The two parts of a versioned hash, for header window AWindow. }
function MetricPart(const AWindow: string; AMetric, AVersion: Integer): string;
begin
  Result:= HexPrefix('v2m|' + AWindow + '|' + IntToStr(AMetric) + '|' + IntToStr(AVersion), METRIC_DIGITS);
end;

function BodyPart(const AWindow, ABody: string; AVersion: Integer): string;
begin
  Result:= HexPrefix('v2b|' + AWindow + '|' + ABody + '|' + IntToStr(AVersion), HASH_DIGITS - METRIC_DIGITS);
end;

function ExpectedHash(const ALines: TArray<string>; const ARuleId: string;
  AStartLine, AMetric: Integer): string;
begin
  if not IsRoutineMetricRule(ARuleId) then
    Exit(LegacyExpectedHash(ALines, ARuleId, AStartLine, AMetric));
  var Anchor : Integer:= DocCommentMarkerLine(ALines, AStartLine);
  var Window : string := TReviewMarkers.HashWindow(ALines, Anchor - 1);
  var Version: Integer:= MetricAlgoVersion(ARuleId);
  Result:= MetricPart(Window, CurrentMetric(ARuleId, AMetric), Version) +
           BodyPart(Window, RoutineBodyHash(ALines, Anchor), Version);
end;

function NeedsRestampHint(AVerdict: TMarkerVerdict): Boolean;
begin
  Result:= AVerdict in [mvRemeasured, mvLegacy];
end;

function RemeasuredHintText(const ARuleId: string; AVerdict: TMarkerVerdict;
  AFindingLine: Integer): string;
begin
  var Cause: string:= if AVerdict = mvLegacy
    then 'was stamped under the 1.51.0 hash'
    else 'was stamped under an older measure algorithm';
  Result:= Format('dl:ok marker for "%s" %s; re-measured under the v2 hash and still valid (finding stays suppressed). ' +
                  'Re-stamp it with: allow --fix-line %d --fix-rule %s',
                  [ARuleId, Cause, AFindingLine, ARuleId]);
end;

function MarkerVerdict(const ALines: TArray<string>; const ARuleId, AMarkerHash: string;
  AStartLine, AMetric: Integer): TMarkerVerdict;
begin
  var Hash : string := LowerCase(AMarkerHash);
  var Metric: Integer:= CurrentMetric(ARuleId, AMetric);
  if Hash = LegacyExpectedHash(ALines, ARuleId, AStartLine, Metric) then
    { A non-metric rule's current hash IS the legacy one: verified. For a routine-metric
      rule the current hash is v2, so a legacy match was re-measured (B3 hint). }
    Exit(if IsRoutineMetricRule(ARuleId) then mvLegacy else mvVerified);
  if (not IsRoutineMetricRule(ARuleId)) or (Length(Hash) <> HASH_DIGITS) then Exit(mvStale);
  var Anchor : Integer:= DocCommentMarkerLine(ALines, AStartLine);
  var Window : string := TReviewMarkers.HashWindow(ALines, Anchor - 1);
  var Current: Integer:= MetricAlgoVersion(ARuleId);
  var MPart  : string := Copy(Hash, 1, METRIC_DIGITS);
  for var V: Integer:= Current downto 1 do
    if MPart = MetricPart(Window, Metric, V) then Exit(mvVerified);
  var Body: string:= RoutineBodyHash(ALines, Anchor);
  { No body found: nothing proves the routine unchanged, so no re-measure. }
  if Body = '' then Exit(mvStale);
  var BPart: string:= Copy(Hash, METRIC_DIGITS + 1, MaxInt);
  for var V: Integer:= Current - 1 downto 1 do
    if BPart = BodyPart(Window, Body, V) then Exit(mvRemeasured);
  Result:= mvStale;
end;

end.
