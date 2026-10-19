unit ConvRules.QualifyFix;

{ The one-click "qualify #convert" quick fix (A2, spec 2026-10-19-convert-qualify-fix-design).
  Every decision lives here, pure: finding the header an engine fix names in the OPEN
  book, writing the picked candidate into it, and the texts the dialog and the status
  bar show. ConvRules.QualifyForm only displays and collects; ConvRules.MainForm only
  wires. ConvRulesModelTests.dpr pins every rule below. }

interface

uses
  ConvRules.Model
  , ConvRules.ConvertRun
  ;

type
  /// <summary>One fix and the candidate the user picked for it.</summary>
  TQualifyPick = record
    /// <summary>The engine's fix (apply/1 qualify_fixes[] entry).</summary>
    Fix      : TQualifyFix;
    /// <summary>The qualified class picked, one of Fix.Suggestions[].Candidate; '' = no pick (the fix is skipped).</summary>
    Candidate: string;
  end;

  /// <summary>How a fix relates to the open book.</summary>
  /// <remarks>qtFound: one header to edit. qtStale: no header reads the fix's line any more.
  /// qtAmbiguous: several identical headers. qtAlreadyQualified: the named side already
  /// holds one of the candidates. qtWrongSide: the header found does not carry the fix's
  /// class name on the fix's side.</remarks>
  TQualifyTargetState = (qtFound, qtStale, qtAmbiguous, qtAlreadyQualified, qtWrongSide);

  /// <summary>The answer of FindQualifyTarget.</summary>
  TQualifyTarget = record
    /// <summary>See TQualifyTargetState.</summary>
    State    : TQualifyTargetState;
    /// <summary>Index into ABook.Nodes when qtFound / qtAlreadyQualified / qtWrongSide; -1 otherwise.</summary>
    NodeIndex: Integer;
    /// <summary>'' when qtFound; else the user-facing sentence.</summary>
    Reason   : string;
  end;

  /// <summary>What applying one pick did.</summary>
  TQualifyOutcome = record
    /// <summary>True when the header was edited.</summary>
    Applied  : Boolean;
    /// <summary>Index into the book's Nodes of the header concerned; -1 when none was found.</summary>
    NodeIndex: Integer;
    /// <summary>The header line before (Emit).</summary>
    Before   : string;
    /// <summary>The header line after (Emit); = Before when not applied.</summary>
    After    : string;
    /// <summary>Why it was not applied; '' when applied.</summary>
    Reason   : string;
  end;

/// <summary>PURE (reads the book, never changes it): the header in ABook that AFix names.</summary>
/// <param name="ABook">The open rule book; not nil.</param>
/// <param name="AFix">An engine fix: RuleLine / Current as the run saw the book on disk.</param>
/// <returns>In order: (1) Nodes[RuleLine - 1] is a #convert header whose Emit = Current ->
/// qtFound; (2) else exactly one header reads Current (the line moved) -> qtFound; (3) else
/// several -> qtAmbiguous, Reason names the 1-based lines; (4) else a header whose OTHER
/// side equals Current's and whose named side equals any suggestion's Candidate
/// (case-insensitive) -> qtAlreadyQualified with that node; (5) else qtStale ('line N no
/// longer reads "..." -- the book changed since the run; run Convert again'). A found node
/// whose named side is not AFix.Name (case-insensitive) is qtWrongSide.</returns>
function FindQualifyTarget(ABook: TRuleBook; const AFix: TQualifyFix): TQualifyTarget;

/// <summary>Writes one pick into the book.</summary>
/// <param name="ABook">The open rule book; not nil. Changed only when the result is Applied.</param>
/// <param name="APick">The fix and its candidate.</param>
/// <returns>Applied: the named side (FromType for 'from', ToType otherwise) now holds the
/// candidate, the node is Dirty and its Marks are cleared; Units, the other side and every
/// other line are untouched. Not applied (never raises): no candidate ('pick a candidate
/// for line N &lt;side&gt; &lt;name&gt;'), qtAlreadyQualified ('line N already qualified: &lt;line&gt;'), or the
/// target's own Reason.</returns>
function ApplyQualifyPick(ABook: TRuleBook; const APick: TQualifyPick): TQualifyOutcome;

/// <summary>Writes several picks into the book, in order.</summary>
/// <param name="ABook">The open rule book; not nil.</param>
/// <param name="APicks">The picks; one outcome per pick, same order.</param>
/// <returns>One outcome per pick.</returns>
/// <remarks>M1 rule: the two sides of one line share RuleLine and Current, and the first
/// pick changes the line, so the second could no longer find it by text. A pick whose fix
/// has the same RuleLine and Current as an EARLIER APPLIED pick of the same call is
/// re-targeted to that outcome's NodeIndex directly; only the side and name are checked.</remarks>
function ApplyQualifyPicks(ABook: TRuleBook; const APicks: TArray<TQualifyPick>): TArray<TQualifyOutcome>;

/// <summary>PURE: the suggestion the dialog preselects.</summary>
/// <param name="AFix">An engine fix.</param>
/// <returns>The index of Chosen in Suggestions (case-insensitive) when Outcome is
/// 'inferred' and it is there; else -1 (a refused fix starts with no selection).</returns>
function DefaultCandidateIndex(const AFix: TQualifyFix): Integer;

/// <summary>PURE: the header line as it will read after the picks; touches no book.</summary>
/// <param name="ACurrent">The header line as the run saw it.</param>
/// <param name="APicks">The picks of that line (a pick with no Candidate is ignored).</param>
/// <returns>ACurrent with every picked side replaced (the union of the picks); ACurrent
/// itself when nothing is picked or it is not a #convert header.</returns>
function QualifyPreviewText(const ACurrent: string; const APicks: TArray<TQualifyPick>): string;

/// <summary>PURE: the dialog's fix-list row.</summary>
/// <param name="AFix">An engine fix.</param>
/// <returns>'line N  side  name  outcome', then ' -&gt; chosen' when the engine inferred one.</returns>
function QualifyFixRowText(const AFix: TQualifyFix): string;

/// <summary>PURE: the dialog's candidate-list row.</summary>
/// <param name="ASug">One suggestion.</param>
/// <returns>'candidate    { why }'; the bare candidate when the engine gave no reason.</returns>
function QualifyCandidateText(const ASug: TQualifySuggestion): string;

/// <summary>PURE: the status-bar text after an Apply.</summary>
/// <param name="ABookPath">The book's path; only its file name is shown.</param>
/// <param name="AOutcomes">ApplyQualifyPicks' result.</param>
/// <returns>'Qualified N #convert side(s) in &lt;book&gt; (line 1) -- not saved: File &gt; Save, then
/// Convert again' (distinct 1-based lines, 'lines 1, 4' for several), plus '; K skipped:
/// reason; reason' when any outcome was not applied; 'Nothing qualified in &lt;book&gt;:
/// reasons' when none was.</returns>
function QualifyStatusText(const ABookPath: string; const AOutcomes: TArray<TQualifyOutcome>): string;

/// <summary>PURE: whether the book the editor has open is the one a Qualify names.</summary>
/// <param name="AOpenPath">The editor's current file path (may be empty for a new book).</param>
/// <param name="ABook">The run row's book path.</param>
/// <returns>True when the two paths are the same file (case-insensitive); the host applies the
/// picks only then, so a book that failed to load never receives another book's picks.</returns>
function QualifyBookIsOpen(const AOpenPath, ABook: string): Boolean;

/// <summary>PURE: the status text when the run's book could not be opened.</summary>
/// <param name="ABook">The run row's book path; only its file name is shown.</param>
/// <returns>'Qualify cancelled -- could not open the run''s book: &lt;file&gt;'.</returns>
function QualifyBookMissingText(const ABook: string): string;

implementation

uses
  System.SysUtils
  , System.StrUtils
  ;

const
  SIDE_TO         = 'to';
  NOT_FOUND       = -1;
  LIST_SEPARATOR  = ', ';
  REASON_SEPARATOR = '; ';

function SideOf(ANode: TRuleNode; const ASide: string): string;
begin
  Result:= if SameText(ASide, SIDE_TO) then ANode.ToType else ANode.FromType;
end;

function OtherSideOf(ANode: TRuleNode; const ASide: string): string;
begin
  Result:= if SameText(ASide, SIDE_TO) then ANode.FromType else ANode.ToType;
end;

procedure SetSide(ANode: TRuleNode; const ASide, AValue: string);
begin
  if SameText(ASide, SIDE_TO) then
    ANode.ToType:= AValue
  else
    ANode.FromType:= AValue;
end;

function HeaderReads(ANode: TRuleNode; const AText: string): Boolean;
begin
  Result:= (ANode.Kind = rnkConvert) and (ANode.Emit = AText);
end;

function IsCandidate(const AFix: TQualifyFix; const AName: string): Boolean;
begin
  Result:= False;
  for var LSug: TQualifySuggestion in AFix.Suggestions do
    Result:= Result or SameText(LSug.Candidate, AName);
end;

// The target for header ABook.Nodes[AIndex]: qtFound unless its named side is not the fix's class.
function FoundOrWrongSide(ABook: TRuleBook; const AFix: TQualifyFix; AIndex: Integer): TQualifyTarget;
begin
  Result.NodeIndex:= AIndex;
  Result.State    := qtFound;
  Result.Reason   := '';
  if not SameText(SideOf(ABook.Nodes[AIndex], AFix.Side), AFix.Name) then
  begin
    Result.State := qtWrongSide;
    Result.Reason:= Format('line %d: the %s side reads "%s", not "%s" -- qualify by hand',
      [AIndex + 1, AFix.Side, SideOf(ABook.Nodes[AIndex], AFix.Side), AFix.Name]);
  end;
end;

// qtAlreadyQualified target, or NodeIndex NOT_FOUND when no header qualifies already.
function AlreadyQualified(ABook: TRuleBook; const AFix: TQualifyFix): TQualifyTarget;
var
  LProbe: TRuleNode;
begin
  Result.State    := qtStale;
  Result.NodeIndex:= NOT_FOUND;
  Result.Reason   := '';
  LProbe:= ABook.ParseLine(AFix.Current);
  try
    if LProbe.Kind <> rnkConvert then
      Exit;
    for var I: Integer:= 0 to ABook.Nodes.Count - 1 do
      if (ABook.Nodes[I].Kind = rnkConvert)
        and SameText(OtherSideOf(ABook.Nodes[I], AFix.Side), OtherSideOf(LProbe, AFix.Side))
        and IsCandidate(AFix, SideOf(ABook.Nodes[I], AFix.Side)) then
      begin
        Result.State    := qtAlreadyQualified;
        Result.NodeIndex:= I;
        Result.Reason   := Format('line %d already qualified: %s', [I + 1, ABook.Nodes[I].Emit]);
        Exit;
      end;
  finally
    LProbe.Free;
  end;
end;

function FindQualifyTarget(ABook: TRuleBook; const AFix: TQualifyFix): TQualifyTarget;
var
  LMatches: TArray<Integer>;
  LLines  : string;
  LAt     : Integer;
begin
  LAt:= AFix.RuleLine - 1;
  if (LAt >= 0) and (LAt < ABook.Nodes.Count) and HeaderReads(ABook.Nodes[LAt], AFix.Current) then
    Exit(FoundOrWrongSide(ABook, AFix, LAt));
  LMatches:= nil;
  for var I: Integer:= 0 to ABook.Nodes.Count - 1 do
    if HeaderReads(ABook.Nodes[I], AFix.Current) then
      LMatches:= LMatches + [I];
  if Length(LMatches) = 1 then
    Exit(FoundOrWrongSide(ABook, AFix, LMatches[0]));
  if Length(LMatches) > 1 then
  begin
    LLines:= '';
    for var LIdx: Integer in LMatches do
      LLines:= LLines + (if LLines = '' then '' else LIST_SEPARATOR) + IntToStr(LIdx + 1);
    Result.State    := qtAmbiguous;
    Result.NodeIndex:= NOT_FOUND;
    Result.Reason   := Format('"%s" is written more than once (lines %s) -- qualify by hand', [AFix.Current, LLines]);
    Exit;
  end;
  Result:= AlreadyQualified(ABook, AFix);
  if Result.State = qtAlreadyQualified then
    Exit;
  Result.State    := qtStale;
  Result.NodeIndex:= NOT_FOUND;
  Result.Reason   := Format('line %d no longer reads "%s" -- the book changed since the run; run Convert again',
    [AFix.RuleLine, AFix.Current]);
end;

// Writes APick into header AIndex when its named side is the fix's class.
function ApplyAt(ABook: TRuleBook; AIndex: Integer; const APick: TQualifyPick): TQualifyOutcome;
var
  LNode: TRuleNode;
begin
  LNode:= ABook.Nodes[AIndex];
  Result.NodeIndex:= AIndex;
  Result.Before   := LNode.Emit;
  Result.After    := Result.Before;
  Result.Applied  := False;
  Result.Reason   := '';
  if not SameText(SideOf(LNode, APick.Fix.Side), APick.Fix.Name) then
  begin
    Result.Reason:= FoundOrWrongSide(ABook, APick.Fix, AIndex).Reason;
    Exit;
  end;
  SetSide(LNode, APick.Fix.Side, APick.Candidate);
  LNode.Dirty:= True;
  LNode.Marks:= nil;
  Result.After  := LNode.Emit;
  Result.Applied:= True;
end;

function ApplyQualifyPick(ABook: TRuleBook; const APick: TQualifyPick): TQualifyOutcome;
var
  LTarget: TQualifyTarget;
begin
  Result:= Default(TQualifyOutcome);
  Result.NodeIndex:= NOT_FOUND;
  if APick.Candidate = '' then
  begin
    Result.Reason:= Format('pick a candidate for line %d %s %s', [APick.Fix.RuleLine, APick.Fix.Side, APick.Fix.Name]);
    Exit;
  end;
  LTarget:= FindQualifyTarget(ABook, APick.Fix);
  if LTarget.State = qtFound then
    Exit(ApplyAt(ABook, LTarget.NodeIndex, APick));
  Result.NodeIndex:= LTarget.NodeIndex;
  Result.Reason   := LTarget.Reason;
  if LTarget.NodeIndex <> NOT_FOUND then
  begin
    Result.Before:= ABook.Nodes[LTarget.NodeIndex].Emit;
    Result.After := Result.Before;
  end;
end;

function ApplyQualifyPicks(ABook: TRuleBook; const APicks: TArray<TQualifyPick>): TArray<TQualifyOutcome>;
var
  LRetarget: Integer;
begin
  SetLength(Result, Length(APicks));
  for var I: Integer:= 0 to High(APicks) do
  begin
    LRetarget:= NOT_FOUND;
    for var J: Integer:= 0 to I - 1 do
      if Result[J].Applied and (APicks[J].Fix.RuleLine = APicks[I].Fix.RuleLine) and (APicks[J].Fix.Current = APicks[I].Fix.Current) then
        LRetarget:= Result[J].NodeIndex;
    if (LRetarget <> NOT_FOUND) and (APicks[I].Candidate <> '') then
      Result[I]:= ApplyAt(ABook, LRetarget, APicks[I])
    else
      Result[I]:= ApplyQualifyPick(ABook, APicks[I]);
  end;
end;

function DefaultCandidateIndex(const AFix: TQualifyFix): Integer;
begin
  Result:= NOT_FOUND;
  if not SameText(AFix.Outcome, 'inferred') then
    Exit;
  for var I: Integer:= 0 to High(AFix.Suggestions) do
    if SameText(AFix.Suggestions[I].Candidate, AFix.Chosen) then
      Exit(I);
end;

function QualifyPreviewText(const ACurrent: string; const APicks: TArray<TQualifyPick>): string;
var
  LBook: TRuleBook;
  LNode: TRuleNode;
  LDone: Boolean;
begin
  Result:= ACurrent;
  LBook:= TRuleBook.Create;
  try
    LNode:= LBook.ParseLine(ACurrent);
    try
      if LNode.Kind <> rnkConvert then
        Exit;
      LDone:= False;
      for var LPick: TQualifyPick in APicks do
        if LPick.Candidate <> '' then
        begin
          SetSide(LNode, LPick.Fix.Side, LPick.Candidate);
          LDone:= True;
        end;
      if LDone then
      begin
        LNode.Dirty:= True;
        Result:= LNode.Emit;
      end;
    finally
      LNode.Free;
    end;
  finally
    LBook.Free;
  end;
end;

function QualifyFixRowText(const AFix: TQualifyFix): string;
begin
  Result:= Format('line %d  %s  %s  %s', [AFix.RuleLine, AFix.Side, AFix.Name, AFix.Outcome]);
  if AFix.Chosen <> '' then
    Result:= Result + ' -> ' + AFix.Chosen;
end;

function QualifyCandidateText(const ASug: TQualifySuggestion): string;
begin
  Result:= ASug.Candidate;
  if ASug.Why <> '' then
    Result:= Result + '    { ' + ASug.Why + ' }';
end;

function QualifyBookIsOpen(const AOpenPath, ABook: string): Boolean;
begin
  Result:= (AOpenPath <> '') and SameText(AOpenPath, ABook);
end;

function QualifyBookMissingText(const ABook: string): string;
begin
  Result:= 'Qualify cancelled -- could not open the run''s book: ' + ExtractFileName(ABook);
end;

function QualifyStatusText(const ABookPath: string; const AOutcomes: TArray<TQualifyOutcome>): string;
var
  LLines  : string;
  LReasons: string;
  LApplied: Integer;
  LSkipped: Integer;
  LLine   : string;
begin
  LLines  := '';
  LReasons:= '';
  LApplied:= 0;
  LSkipped:= 0;
  for var LOut: TQualifyOutcome in AOutcomes do
    if LOut.Applied then
    begin
      Inc(LApplied);
      LLine:= IntToStr(LOut.NodeIndex + 1);
      if not MatchText(LLine, LLines.Split([LIST_SEPARATOR])) then
        LLines:= LLines + (if LLines = '' then '' else LIST_SEPARATOR) + LLine;
    end
    else
    begin
      Inc(LSkipped);
      LReasons:= LReasons + (if LReasons = '' then '' else REASON_SEPARATOR) + LOut.Reason;
    end;
  if LApplied = 0 then
    Exit(Format('Nothing qualified in %s: %s', [ExtractFileName(ABookPath), LReasons]));
  Result:= Format('Qualified %d #convert side(s) in %s (line%s %s) -- not saved: File > Save, then Convert again',
    [LApplied, ExtractFileName(ABookPath), if Pos(LIST_SEPARATOR, LLines) > 0 then 's' else '', LLines]);
  if LSkipped > 0 then
    Result:= Result + Format('; %d skipped: %s', [LSkipped, LReasons]);
end;

end.
