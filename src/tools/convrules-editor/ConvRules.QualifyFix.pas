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
    /// <summary>D4: a unit to add to the book as `#use <Unit>` INSTEAD of editing the header ('' = none).
    /// Honoured only when Candidate = ''; the header then stays as it is.</summary>
    UseUnit  : string;
  end;

  /// <summary>D6: the fixes of one book, gathered over a whole run.</summary>
  TQualifyBookFixes = record
    /// <summary>The .rules path (a Convert row's Book).</summary>
    Book : string;
    /// <summary>That book's qualify_fixes[], engine order.</summary>
    Fixes: TArray<TQualifyFix>;
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
    /// <summary>D4: the unit of a `#use` pick ('' for a header edit). For a use outcome NodeIndex is the
    /// index of the `#use` node (inserted, or the existing one when not applied as a duplicate), Before = ''
    /// and After = the `#use` line.</summary>
    UseUnit  : string;
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
/// re-targeted to that outcome's NodeIndex directly; only the side and name are checked.
/// D4: a pick with Candidate = '' and UseUnit set inserts `#use <UseUnit>` (ahead of the first #convert,
/// else appended; Dirty) AFTER all header picks, then moves every earlier outcome's NodeIndex that sits at
/// or behind the insert -- a unit insert shifts every #convert index. A unit the book already has is not
/// added twice (outcome not applied, Reason 'line N already has #use X').</remarks>
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

/// <summary>D4, PURE: the unit a fix's `#use` alternative would add to the book.</summary>
/// <param name="AFix">An engine fix.</param>
/// <param name="AAlternative">The alternative text of the candidate shown (suggestion or fix level).</param>
/// <returns>The unit name when AFix is a `to` side and AAlternative reads `#use <Unit>` (directive
/// case-insensitive, outer blanks ignored, exactly one word after it); '' otherwise. A `from` side's
/// alternative ("add X to the unit's uses") is a .pas edit the editor cannot make, so it is never
/// clickable.</returns>
function QualifyUseUnit(const AFix: TQualifyFix; const AAlternative: string): string;

/// <summary>D4, PURE: the dialog preview of a `#use` pick.</summary>
/// <param name="AUnit">The unit to add; not empty.</param>
/// <returns>'will add to the book: #use &lt;Unit&gt; (the #convert line stays as it is)'.</returns>
function QualifyUsePreviewText(const AUnit: string): string;

/// <summary>D6, PURE: gathers a run's fixes per book for the Qualify-all loop.</summary>
/// <param name="ARows">One entry per Convert results row (Book + its qualify_fixes[]); rows with no book or no fix are ignored.</param>
/// <returns>One entry per distinct book (path compared case-insensitively), in first-seen order. Within
/// a book a fix repeated by another unit's row (same RuleLine, Current, Side and Name, case-insensitive on
/// Name and Side) is kept once -- the FIRST row's fix wins, including its suggestions.</returns>
function GroupQualifyFixes(const ARows: TArray<TQualifyBookFixes>): TArray<TQualifyBookFixes>;

/// <summary>D6, PURE: the status text when the open book had to be left unsaved.</summary>
/// <returns>'Qualify cancelled -- the open book was not saved'.</returns>
function QualifyNotSavedText: string;

/// <summary>D6, PURE: whether a QualifyBook status means the Qualify-all loop must stop.</summary>
/// <param name="AStatus">QualifyBook's result.</param>
/// <returns>True for QualifyNotSavedText and QualifyBookMissingText (both begin 'Qualify cancelled'); False for an applied or skipped status.</returns>
function QualifyIsAborted(const AStatus: string): Boolean;

/// <summary>D6, PURE: the status-bar text of a finished Qualify-all loop.</summary>
/// <param name="AStatuses">QualifyBook's status per book handled, in order.</param>
/// <param name="ABooks">How many books the run had.</param>
/// <param name="AStopped">True when the loop ended early (dialog cancelled or QualifyIsAborted).</param>
/// <returns>'Qualify all (K of N book(s)[, stopped])' then ': status | status' when K &gt; 0.</returns>
function QualifyAllStatusText(const AStatuses: TArray<string>; ABooks: Integer; AStopped: Boolean): string;

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
  USE_DIRECTIVE   = '#use';
  USE_WORDS       = 2;
  CANCELLED_PREFIX = 'Qualify cancelled';

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

function IsUsePick(const APick: TQualifyPick): Boolean;
begin
  Result:= (APick.Candidate = '') and (APick.UseUnit <> '');
end;

// Index of the `#use AUnit` node, or NOT_FOUND.
function FindUseNode(ABook: TRuleBook; const AUnit: string): Integer;
begin
  Result:= NOT_FOUND;
  for var I: Integer:= 0 to ABook.Nodes.Count - 1 do
    if (ABook.Nodes[I].Kind = rnkUse) and SameText(Trim(ABook.Nodes[I].UseUnit), AUnit) then
      Exit(I);
end;

// Inserts `#use AUnit` ahead of the first #convert (the file-level section, as the Unit Rules tab does), or
// appends it when the book has no header. Every outcome flagged in AShift whose node sits at or behind the
// insert moves down one (their NodeIndex stays the node's index).
function ApplyUse(ABook: TRuleBook; const AUnit: string; var AOutcomes: TArray<TQualifyOutcome>; const AShift: TArray<Boolean>): TQualifyOutcome;
var
  LNode : TRuleNode;
  LHeads: TArray<Integer>;
  LAt   : Integer;
begin
  Result:= Default(TQualifyOutcome);
  Result.UseUnit  := AUnit;
  Result.NodeIndex:= FindUseNode(ABook, AUnit);
  if Result.NodeIndex <> NOT_FOUND then
  begin
    Result.Before:= ABook.Nodes[Result.NodeIndex].Emit;
    Result.After := Result.Before;
    Result.Reason:= Format('line %d already has %s %s', [Result.NodeIndex + 1, USE_DIRECTIVE, AUnit]);
    Exit;
  end;
  LNode:= TRuleNode.Create;
  LNode.Kind   := rnkUse;
  LNode.UseUnit:= AUnit;
  LNode.Dirty  := True;
  LHeads:= ABook.ConvertHeaders;
  if Length(LHeads) = 0 then
  begin
    ABook.Add(LNode);
    LAt:= ABook.Nodes.Count - 1;
  end
  else
  begin
    LAt:= LHeads[0];
    ABook.Nodes.Insert(LAt, LNode);
  end;
  for var J: Integer:= 0 to High(AOutcomes) do
    if AShift[J] and (AOutcomes[J].NodeIndex >= LAt) then
      Inc(AOutcomes[J].NodeIndex);
  Result.NodeIndex:= LAt;
  Result.After    := LNode.Emit;
  Result.Applied  := True;
end;

function ApplyQualifyPicks(ABook: TRuleBook; const APicks: TArray<TQualifyPick>): TArray<TQualifyOutcome>;
var
  LRetarget: Integer;
  LDone    : TArray<Boolean>;
begin
  SetLength(Result, Length(APicks));
  SetLength(LDone, Length(APicks));
  for var I: Integer:= 0 to High(APicks) do
  begin
    if IsUsePick(APicks[I]) then
      Continue;
    LDone[I]:= True;
    LRetarget:= NOT_FOUND;
    for var J: Integer:= 0 to I - 1 do
      if Result[J].Applied and (APicks[J].Fix.RuleLine = APicks[I].Fix.RuleLine) and (APicks[J].Fix.Current = APicks[I].Fix.Current) then
        LRetarget:= Result[J].NodeIndex;
    if (LRetarget <> NOT_FOUND) and (APicks[I].Candidate <> '') then
      Result[I]:= ApplyAt(ABook, LRetarget, APicks[I])
    else
      Result[I]:= ApplyQualifyPick(ABook, APicks[I]);
  end;
  // The #use inserts come last: they shift every node behind them, and the header picks above found theirs first.
  for var I: Integer:= 0 to High(APicks) do
    if IsUsePick(APicks[I]) then
    begin
      Result[I]:= ApplyUse(ABook, APicks[I].UseUnit, Result, LDone);
      LDone[I]:= True;
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
  Result:= CANCELLED_PREFIX + ' -- could not open the run''s book: ' + ExtractFileName(ABook);
end;

function QualifyUseUnit(const AFix: TQualifyFix; const AAlternative: string): string;
var
  LWords: TArray<string>;
begin
  Result:= '';
  if not SameText(AFix.Side, SIDE_TO) then
    Exit;
  LWords:= Trim(AAlternative).Split([' '], TStringSplitOptions.ExcludeEmpty);
  if (Length(LWords) = USE_WORDS) and SameText(LWords[0], USE_DIRECTIVE) then
    Result:= LWords[1];
end;

function QualifyUsePreviewText(const AUnit: string): string;
begin
  Result:= Format('will add to the book: %s %s (the #convert line stays as it is)', [USE_DIRECTIVE, AUnit]);
end;

function SameFix(const A, B: TQualifyFix): Boolean;
begin
  Result:= (A.RuleLine = B.RuleLine) and (A.Current = B.Current) and SameText(A.Side, B.Side) and SameText(A.Name, B.Name);
end;

// Index of the group for ABook, or NOT_FOUND.
function GroupOf(const AGroups: TArray<TQualifyBookFixes>; const ABook: string): Integer;
begin
  Result:= NOT_FOUND;
  for var I: Integer:= 0 to High(AGroups) do
    if SameText(AGroups[I].Book, ABook) then
      Exit(I);
end;

function HasFix(const AFixes: TArray<TQualifyFix>; const AFix: TQualifyFix): Boolean;
begin
  Result:= False;
  for var LFix: TQualifyFix in AFixes do
    Result:= Result or SameFix(LFix, AFix);
end;

function GroupQualifyFixes(const ARows: TArray<TQualifyBookFixes>): TArray<TQualifyBookFixes>;
var
  LAt: Integer;
begin
  Result:= nil;
  for var LRow: TQualifyBookFixes in ARows do
  begin
    if (LRow.Book = '') or (Length(LRow.Fixes) = 0) then
      Continue;
    LAt:= GroupOf(Result, LRow.Book);
    if LAt = NOT_FOUND then
    begin
      SetLength(Result, Length(Result) + 1);
      LAt:= High(Result);
      Result[LAt].Book := LRow.Book;
      Result[LAt].Fixes:= nil;
    end;
    for var LFix: TQualifyFix in LRow.Fixes do
      if not HasFix(Result[LAt].Fixes, LFix) then
        Result[LAt].Fixes:= Result[LAt].Fixes + [LFix];
  end;
end;

function QualifyNotSavedText: string;
begin
  Result:= CANCELLED_PREFIX + ' -- the open book was not saved';
end;

function QualifyIsAborted(const AStatus: string): Boolean;
begin
  Result:= StartsText(CANCELLED_PREFIX, AStatus);
end;

function QualifyAllStatusText(const AStatuses: TArray<string>; ABooks: Integer; AStopped: Boolean): string;
begin
  Result:= Format('Qualify all (%d of %d book(s)%s)', [Length(AStatuses), ABooks, if AStopped then ', stopped' else '']);
  if Length(AStatuses) > 0 then
    Result:= Result + ': ' + string.Join(' | ', AStatuses);
end;

function QualifyStatusText(const ABookPath: string; const AOutcomes: TArray<TQualifyOutcome>): string;
var
  LLines  : string;
  LReasons: string;
  LApplied: Integer;
  LSkipped: Integer;
  LLine   : string;
  LUses   : string;
begin
  LLines  := '';
  LReasons:= '';
  LApplied:= 0;
  LSkipped:= 0;
  LUses   := '';
  for var LOut: TQualifyOutcome in AOutcomes do
    if LOut.Applied and (LOut.UseUnit <> '') then
      LUses:= LUses + (if LUses = '' then '' else LIST_SEPARATOR) + LOut.UseUnit
    else if LOut.Applied then
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
  if (LApplied = 0) and (LUses = '') then
    Exit(Format('Nothing qualified in %s: %s', [ExtractFileName(ABookPath), LReasons]));
  if LApplied = 0 then
    Result:= Format('Added %s %s to %s -- not saved: File > Save, then Convert again', [USE_DIRECTIVE, LUses, ExtractFileName(ABookPath)])
  else
  begin
    Result:= Format('Qualified %d #convert side(s) in %s (line%s %s) -- not saved: File > Save, then Convert again',
      [LApplied, ExtractFileName(ABookPath), if Pos(LIST_SEPARATOR, LLines) > 0 then 's' else '', LLines]);
    if LUses <> '' then
      Result:= Result + Format('; added %s %s', [USE_DIRECTIVE, LUses]);
  end;
  if LSkipped > 0 then
    Result:= Result + Format('; %d skipped: %s', [LSkipped, LReasons]);
end;

end.
