unit DragLint.Plugin.LintOutputParse;

{ Pure (ToolsAPI/VCL-free) parser for one line of `drag-lint lint` text output.
  Split out of DragLint.Plugin.LiveDiagnostics for the same reason
  DragLint.Plugin.SearchParse was: that unit pulls in ToolsAPI and Vcl.ExtCtrls,
  so nothing in it can be exercised by a console harness. Unit-tested by
  tests\lintoutputparse\LintOutputParseTests.dpr.

  WHY THIS EXISTS AT ALL (INBOX-livediag-parser-line1-fallback.md, 2026-08-26).
  The previous parser scanned for the FIRST '[' and then did

      D.Line := StrToIntDef(Trim(LineStr), 1);

  Two things were wrong with that pair, and they compound.

  1. RunCapture gives the child process ONE pipe for stdout and stderr
     (`SI.hStdOutput := WritePipe; SI.hStdError := WritePipe`), so the engine's
     stderr notes INTERLEAVE with its stdout findings mid-word. Observed: a note
     cut after "...they are cle" with a complete finding line spliced in, and its
     tail ("an.") emerging after the summary.

  2. The old guards -- two colons somewhere left of the bracket -- are satisfied
     by "drag-lint: note: ..." and by every Windows path ("C:\..."), so junk
     reached the numeric parse. And THE DEFAULT WAS 1, so an unparseable line
     became a diagnostic on LINE 1 of the user's file: a gutter glyph and a
     squiggle on a line with nothing wrong with it.

  This repo has shipped that exact shape before -- session 29 wrote accepted
  completions to line 1 of the user's source -- which is why the fix is to
  REJECT rather than to default. A dropped line is recoverable; an invented
  finding on line 1 teaches the user to distrust the gutter. }

interface

uses
  System.SysUtils;

/// <summary>Splits one engine output line into its location and its
/// "[sev] rule: message" remainder, but ONLY if the text left of the bracket
/// genuinely ends in <c>:&lt;line&gt;:&lt;col&gt;</c>.</summary>
/// <param name="ALine">One raw line of engine output.</param>
/// <param name="ALineNo">Receives the 1-based source line on success; 0 otherwise.</param>
/// <param name="ACol">Receives the 1-based column on success; 0 otherwise.</param>
/// <param name="ATag">Receives the severity word from between the brackets.</param>
/// <param name="ARest">Receives the trimmed text after the closing bracket.</param>
/// <returns>True only when the line really is a finding.</returns>
/// <remarks>
/// <para>Tries each '[' in turn, left to right, and accepts the first whose left
/// side parses as a location -- so a note that happens to contain brackets no
/// longer captures the line. A line that cannot yield two integers is rejected;
/// nothing is defaulted.</para>
/// <para>Pure and side-effect free. Callers should COUNT rejects and log the
/// count: silently dropping a finding is its own failure mode, and a reject
/// count that tracks the finding count means the parser is eating real output.</para>
/// </remarks>
function TryParseFindingLine(const ALine: string; out ALineNo, ACol: Integer;
  out ATag, ARest: string): Boolean;

type
  /// <summary>One lint-report line, chosen for the IDE Messages pane.</summary>
  /// <remarks>Order is the row's index AS READ: it is both the stable-sort
  /// tiebreak and the row's identity, so a row cannot be posted twice after the
  /// list is reordered.</remarks>
  TPaneRow = record
    FileName: string ;
    Text    : string ;
    RuleId  : string ;
    Line    : Integer;
    Col     : Integer;
    Rank    : Integer;
    Order   : Integer;
  end;

/// <summary>Chooses which findings a capped Messages pane should show, so that
/// every rule that fired is represented before any rule gets a second row.</summary>
/// <param name="AReportLines">The lint-all report, as read.</param>
/// <param name="ACap">Maximum rows to return; &lt;= 0 yields none.</param>
/// <param name="ATotal">Receives the number of parseable findings seen.</param>
/// <param name="ARulesShown">Receives how many distinct rules got a row.</param>
/// <returns>The chosen rows, worst severity first, then report order.</returns>
/// <remarks>
/// <para>WHY COVERAGE FIRST. The pane used to take the report's first ACap lines.
/// The report is ordered by file and ~83% of a real run is [info], so on ORM3
/// 2000 slots filled with naming hints from the earliest files and `circular-uses`
/// -- 2 architectural warnings at report line 29457 of 49242 -- never appeared at
/// all. The owner reported it as "Messages window doesn't have the circular
/// dependency report at all", and he was right.</para>
/// <para>Severity order ALONE does not fix that: the same run had 27,027
/// warnings, so two more would still have lost. Guaranteeing one row per rule is
/// what makes a rule impossible to hide; depth beyond that is the report's job.</para>
/// <para>Pure and side-effect free.</para>
/// </remarks>
function SelectPaneRows(const AReportLines: TArray<string>; ACap: Integer;
  out ATotal, ARulesShown: Integer): TArray<TPaneRow>;

/// <summary>Maps an engine severity word to its LSP DiagnosticSeverity.</summary>
/// <param name="ATag">The word from between the brackets, e.g. "info".</param>
/// <returns>1 error, 2 warning, 3 info, 4 hint. Unrecognised text yields 3.</returns>
/// <remarks>Substring matching, because the engine has spelled these several
/// ways over time ("warn"/"warning"). Info is the default because it is the
/// least alarming of the four -- an unknown tag should not paint an error.</remarks>
function SeverityFromTag(const ATag: string): Integer;

implementation

uses
  System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults;

function TryParseFindingLine(const ALine: string; out ALineNo, ACol: Integer;
  out ATag, ARest: string): Boolean;
var
  BrOpen, BrClose: Integer; { candidate '[' and its matching ']' }
  Colon1, Colon2 : Integer; { the last two ':' left of the bracket }
  Loc, Loc2      : string ;
begin
  Result := False;
  ALineNo:= 0;
  ACol   := 0;
  ATag   := '';
  ARest  := '';

  BrOpen:= Pos('[', ALine);
  while BrOpen > 0 do
  begin
    BrClose:= PosEx(']', ALine, BrOpen + 1);
    if BrClose = 0 then Exit; { an unclosed bracket ends the search }

    { Left of '[' must be <path>:<line>:<col> -- col after the last ':', line
      after the one before it. BOTH must parse as integers. }
    Loc:= Trim(Copy(ALine, 1, BrOpen - 1));
    Colon2 := LastDelimiter(':', Loc);
    if Colon2 > 1 then
    begin
      Loc2:= Copy(Loc, 1, Colon2 - 1);
      Colon1  := LastDelimiter(':', Loc2);
      if (Colon1 > 1)
         and TryStrToInt(Trim(Copy(Loc2, Colon1 + 1, MaxInt)), ALineNo)
         and TryStrToInt(Trim(Copy(Loc , Colon2 + 1, MaxInt)), ACol) then
      begin
        ATag := Copy(ALine, BrOpen + 1, BrClose - BrOpen - 1);
        ARest:= Trim(Copy(ALine, BrClose + 1, MaxInt));
        Exit(True);
      end;
      { A failed parse must not leave a half-set out-param behind: TryStrToInt
        writes ALineNo before the column test runs, so a line with a good line
        number and a bad column would otherwise return False with ALineNo set. }
      ALineNo:= 0;
      ACol   := 0;
    end;

    BrOpen:= PosEx('[', ALine, BrOpen + 1); { that bracket was not it -- try the next }
  end;
end; // function

function SeverityFromTag(const ATag: string): Integer;
var
  L: string;
begin
  L:= LowerCase(ATag);
  if Pos('error', L) > 0 then Result:= 1
  else if Pos('warn', L) > 0 then Result:= 2
  else if Pos('hint', L) > 0 then Result:= 4
  else Result:= 3; { info }
end;

{ Worst first. An UNRECOGNISED severity sorts LAST, never first: an odd shape
  must not be able to outrank a real error and consume the cap. }
function PaneRank(const ARest: string): Integer;
begin
  if      StartsText('[error]'  , ARest) then Result:= 0
  else if StartsText('[warning]', ARest) then Result:= 1
  else if StartsText('[hint]'   , ARest) then Result:= 2
  else if StartsText('[info]'   , ARest) then Result:= 3
  else Result:= 4;
end;

{ '[warning] circular-uses: msg' -> 'circular-uses'. '' when the shape does not
  match, and '' is then simply one more bucket -- so an unparseable row still
  gets a slot instead of the whole class of them disappearing. }
function PaneRuleId(const ARest: string): string;
var
  B, C: Integer;
begin
  Result:= '';
  B:= Pos(']', ARest);
  if B < 1 then Exit;
  C:= PosEx(':', ARest, B);
  if C < 1 then Exit;
  Result:= Trim(Copy(ARest, B + 1, C - B - 1));
end;

function SelectPaneRows(const AReportLines: TArray<string>; ACap: Integer;
  out ATotal, ARulesShown: Integer): TArray<TPaneRow>;
var
  Rows, Chosen: TList<TPaneRow>;
  RuleSeen    : TDictionary<string, Boolean>;
  Taken       : TDictionary<Integer, Boolean>;
  Ln, Loc, Loc2, Rest, FName: string;
  P, C1, C2, LineNo, Col: Integer;
begin
  Result     := nil;
  ATotal     := 0;
  ARulesShown:= 0;
  if ACap <= 0 then Exit;

  Rows    := TList<TPaneRow>.Create;
  Chosen  := TList<TPaneRow>.Create;
  RuleSeen:= TDictionary<string, Boolean>.Create;
  Taken   := TDictionary<Integer, Boolean>.Create;
  try
    for Ln in AReportLines do
    begin
      P:= Pos('  [', Ln); { two spaces before "[severity]" separate location from the rest }
      if P < 2 then Continue;
      Loc := Copy(Ln, 1, P - 1);
      Rest:= Copy(Ln, P + 2, MaxInt);
      C2:= LastDelimiter(':', Loc);
      if C2 < 2 then Continue;
      Col := StrToIntDef(Copy(Loc, C2 + 1, MaxInt), 0);
      Loc2:= Copy(Loc, 1, C2 - 1);
      C1:= LastDelimiter(':', Loc2);
      if C1 < 2 then Continue;
      LineNo:= StrToIntDef(Copy(Loc2, C1 + 1, MaxInt), 0);
      FName := Copy(Loc2, 1, C1 - 1);
      { Reject rather than default -- see this unit's header. A row we cannot
        place is dropped, never posted against line 1. }
      if (FName = '') or (LineNo <= 0) then Continue;
      Inc(ATotal);

      var Row: TPaneRow;
      Row.FileName:= FName;
      Row.Text    := Rest;
      Row.Line    := LineNo;
      Row.Col     := Col;
      Row.Rank    := PaneRank(Rest);
      Row.RuleId  := PaneRuleId(Rest);
      Row.Order   := Rows.Count;
      Rows.Add(Row);
    end;

    { Pass 1 -- one row per rule, in report order. }
    for var R1: TPaneRow in Rows do
      if (Chosen.Count < ACap) and not RuleSeen.ContainsKey(R1.RuleId) then
      begin
        RuleSeen.AddOrSetValue(R1.RuleId, True);
        Taken.AddOrSetValue(R1.Order, True);
        Chosen.Add(R1);
      end;
    ARulesShown:= Chosen.Count;

    { Pass 2 -- fill the remainder, worst severity first. }
    Rows.Sort(TComparer<TPaneRow>.Construct(
      function(const L, R: TPaneRow): Integer
      begin
        Result:= L.Rank - R.Rank;
        if Result = 0 then Result:= L.Order - R.Order;
      end));
    for var R2: TPaneRow in Rows do
    begin
      if Chosen.Count >= ACap then Break;
      if Taken.ContainsKey(R2.Order) then Continue;
      Taken.AddOrSetValue(R2.Order, True);
      Chosen.Add(R2);
    end;

    { Present worst-first, so the top of the pane is the part worth reading. }
    Chosen.Sort(TComparer<TPaneRow>.Construct(
      function(const L, R: TPaneRow): Integer
      begin
        Result:= L.Rank - R.Rank;
        if Result = 0 then Result:= L.Order - R.Order;
      end));
    Result:= Chosen.ToArray;
  finally
    Taken.Free;
    RuleSeen.Free;
    Chosen.Free;
    Rows.Free;
  end;
end;

end.
