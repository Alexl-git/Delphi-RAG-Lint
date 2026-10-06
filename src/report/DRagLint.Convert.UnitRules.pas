unit DRagLint.Convert.UnitRules;

{
  convert-apply's UNIT RULES (1.20.6): a rule book's #unuse / #use / #useswap
  lines applied to ONE unit's uses clauses.

  The parser has read the three directives since 1.14 (DRagLint.Convert.Rules,
  rkUnuse / rkUse / rkUseSwap), but nothing on the convert-apply path consumed
  them, so a book of #useswap lines validated, ran and changed nothing. This
  unit is the missing step; convert-apply calls PlanUnitRules for the unit it
  converts and folds the edits into the same plan as the #convert surfaces.

  THE CONTRACT (the converter/editor team reads exactly this):
    * #unuse Old                     -- remove Old from whichever clause holds it;
    * #use New                       -- add New to the IMPLEMENTATION uses when it
                                        is absent from BOTH clauses (a clause is
                                        created when the unit has none);
    * #useswap Old -> New1[, New2]   -- when the unit uses Old: remove Old and add
                                        each New that is absent from both clauses,
                                        into the section Old was in. A unit that
                                        does not use Old gets NO edit from the swap.
  Names compare case-insensitively. A unit the book both adds and removes is
  KEPT (ADD wins), the same normalisation the editor's
  ConvRules.Units.NormalizeUnitSets applies, #convert block units included.

  WHY THE SOURCE TEXT AND NOT THE INDEX. The index stores each uses entry's
  name span and section (TUnitUse), but not the commas, the comments, the
  "in '...'" paths or the conditional directives between entries -- which are
  exactly what a byte-preserving removal has to see. So the unit's own bytes,
  read at plan time, are lexed here; that also makes the plan immune to a
  stale index.

  LAYOUT. Every byte outside the removed entries and their one adjacent comma
  is kept. A line left holding only whitespace is dropped; removing a clause's
  last entry drops the whole 'uses ... ;' (and one of two blank lines that
  would otherwise pile up around it). An added name is appended after the
  clause's last unconditional entry, as find-unit does.

  REFUSAL, never a guess: an entry inside a $IF / $IFDEF region, or a removal
  whose comma lies across a conditional directive, refuses the WHOLE unit with
  a named reason (Ok=False) and plans no edit at all.
}

interface

uses
  DRagLint.Convert.Rules,
  DRagLint.Refactor.TextEdit;

type
  /// <summary>One uses-clause change a unit rule makes to the unit being
  /// converted -- one row of convert-apply's apply/1 'uses' array.</summary>
  /// <remarks>
  /// Action is 'remove' or 'add'. Section is 'interface' or 'implementation'.
  /// Line is 1-based in the unit AS READ, before any edit: a removed entry's
  /// own line; for an add, the line the name is written onto (the entry it is
  /// appended after, or the first entry it replaces), or the section keyword's
  /// line when a new uses clause is created. Rule is the book line that asked
  /// for the change, normalised to '#unuse Old', '#use New' or
  /// '#useswap Old -&gt; New1, New2'. UnitName is spelled as written in the
  /// unit for a removal and as written in the book for an add.
  /// Action 'skipped' (1.23.0, C13 N4) is a removal convert-apply did NOT make
  /// because it would strand instances that --only left out; the row has no
  /// edit behind it, Line/Section are the kept entry's, and Reason says why
  /// ('would leave N unconverted instance(s) of T'). Reason is '' otherwise.
  /// </remarks>
  TUsesChange = record
    Action  : string;
    UnitName: string;
    Section : string;
    Line    : Integer;
    Rule    : string;
    Reason  : string;
  end;

  /// <summary>The outcome of PlanUnitRules for one unit.</summary>
  /// <remarks>
  /// Ok=False means the unit is REFUSED: Error names the reason, and Edits and
  /// Changes are both empty -- nothing is planned for the unit at all. Refused
  /// is True for every such deliberate refusal (the unit cannot be rewritten
  /// safely -- apply/1 refused=true) and False only for the planner's own
  /// internal defect (an edit it failed to produce). Ok=True
  /// with no Edits is the normal answer for a unit the book does not touch.
  /// Edits target the unit only, in the whole-line shape TTextEditApplier
  /// applies (a tekDeleteLines of each changed clause's lines plus a
  /// tekInsertLines of its new text, or a tekInsertLines for a created clause).
  /// </remarks>
  TUsesPlan = record
    Ok     : Boolean;
    Refused: Boolean;
    Error  : string;
    Edits  : TArray<TTextEdit>;
    Changes: TArray<TUsesChange>;
  end;

/// <summary>True when ARules holds at least one unit rule (#unuse, #use or
/// #useswap).</summary>
/// <param name="ARules">The parsed rule book.</param>
/// <returns>True when convert-apply has uses clauses to change for any unit
/// it is run on; False for a book of #convert blocks alone.</returns>
/// <remarks>Pure.</remarks>
function BookHasUnitRules(const ARules: TConversionRuleSet): Boolean;

/// <summary>Plans the uses-clause edits ARules' unit rules make to one unit,
/// folding in the units convert-apply's #convert blocks add, so every uses
/// change to the unit comes from one planner and no unit is added twice.</summary>
/// <param name="AUnitPas">The unit's path; the edits' FilePath, and the name
/// used in a refusal message.</param>
/// <param name="AText">The unit's full text as read from disk (any mix of
/// CRLF / LF / CR line breaks; line numbers are counted the way
/// TTextEditApplier counts them).</param>
/// <param name="ARules">The parsed rule book. Only #unuse / #use / #useswap
/// act; #convert blocks' trailing units count as ADDS for the ADD-wins
/// normalisation but are not added by this routine.</param>
/// <param name="AExtraAdds">Units a #convert block needs added (the To
/// types' declaring units). Added once each, like #use, but into the
/// implementation uses when the unit has one, else the interface uses, else a
/// new implementation clause -- the section TFindUnitRefactoring.Build picks.
/// They produce edits but no TUsesChange row: they are the #convert surface,
/// not a unit rule.</param>
/// <param name="AInterfaceAdds">The units of AExtraAdds that must go to the
/// INTERFACE uses because a retyped field of their To type is declared in the
/// interface section (C13 a). Requested first, so a #use of the same unit does
/// not pull it into the implementation. Default nil: every extra add takes the
/// section rule above.</param>
/// <returns>The plan; see TUsesPlan. Ok=False (with Error) when the text is
/// not a unit with interface and implementation sections, when a clause
/// cannot be read, when an entry to remove sits in a conditional region, when
/// a removal would cross a conditional directive, or when an add has no
/// unconditional entry to follow.</returns>
/// <remarks>Pure: reads nothing but its arguments and writes nothing. The
/// contract (remove Old, add each New once in any case, keep Old's section) is
/// pinned by tests\autotest\run_convert_apply_unit_rules.ps1.</remarks>
function PlanUnitRules(const AUnitPas, AText: string; const ARules: TConversionRuleSet;
  const AExtraAdds: TArray<string>; const AInterfaceAdds: TArray<string> = nil): TUsesPlan;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults,
  System.Generics.Collections;

const
  SECTION_INTF = 'interface';
  SECTION_IMPL = 'implementation';
  LF           = #10;
  CRLF         = #13#10;
  QUOTE        = '''';
  TRIPLE_QUOTE = '''''''';
  DIR_OPEN_LEN = 2;  // brace + dollar
  PAR_OPEN_LEN = 3;  // paren + star + dollar

type
  TTokKind = (tkIdent, tkString, tkSym, tkEof);

  { One significant token. Offsets are 1-based into the LF-normalised text;
    Stop is exclusive. Depth counts the $IF / $IFDEF regions open at the token. }
  TTok = record
    Kind : TTokKind;
    Start: Integer;
    Stop : Integer;
    Text : string;
    Depth: Integer;
  end;

  TUsesEntry = record
    Name : string;
    Start: Integer;
    Stop : Integer;
    Depth: Integer;
  end;

  { One section's uses clause. Commas[i] sits between Entries[i] and
    Entries[i + 1]. KwLine is the section keyword's line, kept for a clause
    that has to be created. }
  TUsesClause = record
    Section: string;
    Present: Boolean;
    KwLine : Integer;
    Start  : Integer;
    Stop   : Integer;
    Entries: TArray<TUsesEntry>;
    Commas : TArray<TTok>;
  end;

  TSpan = record
    Start: Integer;
    Stop : Integer;
  end;

  { A small Pascal lexer: skips whitespace and comments, records every
    compiler directive and tracks the conditional-region depth. It lexes only
    as far as the parser asks, which is the implementation uses clause. }
  TUsesLexer = class
  private
    FText      : string;
    FPos       : Integer;
    FDepth     : Integer;
    FDirectives: TList<Integer>;
    procedure Directive(AStart, ABodyStart: Integer; const ACloser: string);
    procedure SkipTo(const ACloser: string);
    procedure SkipTrivia;
    function IsMultiLineOpener: Boolean;
    procedure ReadString;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    function Next: TTok;
    function DirectiveIn(AFrom, ATo: Integer): Boolean;
  end;

function IsIdentStart(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsBlank(const S: string): Boolean;
var
  C: Char;
begin
  for C in S do
    if C > ' ' then Exit(False);
  Result:= True;
end;

constructor TUsesLexer.Create(const AText: string);
begin
  inherited Create;
  FText      := AText;
  FPos       := 1;
  FDirectives:= TList<Integer>.Create;
end;

destructor TUsesLexer.Destroy;
begin
  FDirectives.Free;
  inherited Destroy;
end;

procedure TUsesLexer.SkipTo(const ACloser: string);
var
  P: Integer;
begin
  P:= Pos(ACloser, FText, FPos);
  if P = 0 then FPos:= Length(FText) + 1
  else FPos:= P + Length(ACloser);
end;

procedure TUsesLexer.Directive(AStart, ABodyStart: Integer; const ACloser: string);
var
  P   : Integer;
  Name: string;
begin
  FDirectives.Add(AStart);
  P:= ABodyStart;
  while (P <= Length(FText)) and IsIdentChar(FText[P]) do Inc(P);
  Name:= UpperCase(Copy(FText, ABodyStart, P - ABodyStart));
  if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
    Inc(FDepth)
  else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (FDepth > 0) then
    Dec(FDepth);
  FPos:= ABodyStart;
  SkipTo(ACloser);
end;

procedure TUsesLexer.SkipTrivia;
var
  C, D: Char;
begin
  while FPos <= Length(FText) do
  begin
    C:= FText[FPos];
    D:= if FPos < Length(FText) then FText[FPos + 1] else #0;
    if C <= ' ' then
      Inc(FPos)
    else if (C = '/') and (D = '/') then
      SkipTo(LF)
    else if (C = '{') and (D = '$') then
      Directive(FPos, FPos + DIR_OPEN_LEN, '}')
    else if C = '{' then
      SkipTo('}')
    else if (C = '(') and (D = '*') then
    begin
      if Copy(FText, FPos, PAR_OPEN_LEN) = '(*$' then
        Directive(FPos, FPos + PAR_OPEN_LEN, '*)')
      else
        SkipTo('*)');
    end
    else
      Break;
  end;
end;

{ A Delphi 12+ multi-line string opens with three quotes and NOTHING but
  blanks after them on the line. Four quotes ('''') is the ordinary literal
  holding one quote, and '''abc' a literal starting with one -- neither opens
  a multi-line string. }
function TUsesLexer.IsMultiLineOpener: Boolean;
var
  P: Integer;
begin
  if Copy(FText, FPos, Length(TRIPLE_QUOTE)) <> TRIPLE_QUOTE then Exit(False);
  P:= FPos + Length(TRIPLE_QUOTE);
  while (P <= Length(FText)) and CharInSet(FText[P], [' ', #9]) do Inc(P);
  Result:= (P > Length(FText)) or (FText[P] = LF);
end;

procedure TUsesLexer.ReadString;
begin
  if IsMultiLineOpener then
  begin
    { Delphi 12+ multi-line string: runs to the next triple quote. }
    Inc(FPos, Length(TRIPLE_QUOTE));
    SkipTo(TRIPLE_QUOTE);
    Exit;
  end;
  Inc(FPos);
  while FPos <= Length(FText) do
  begin
    if FText[FPos] = LF then Break;  { unterminated: stop at the line end }
    if FText[FPos] = QUOTE then
    begin
      if (FPos < Length(FText)) and (FText[FPos + 1] = QUOTE) then
        Inc(FPos, Length(QUOTE + QUOTE))
      else
      begin
        Inc(FPos);
        Break;
      end;
    end
    else
      Inc(FPos);
  end;
end;

function TUsesLexer.Next: TTok;
var
  C: Char;
begin
  SkipTrivia;
  Result:= Default(TTok);
  Result.Start:= FPos;
  Result.Depth:= FDepth;
  if FPos > Length(FText) then
  begin
    Result.Kind:= tkEof;
    Result.Stop:= FPos;
    Exit;
  end;
  C:= FText[FPos];
  if (C = '&') and (FPos < Length(FText)) and IsIdentStart(FText[FPos + 1]) then
    Inc(FPos);
  if IsIdentStart(FText[FPos]) then
  begin
    Result.Kind:= tkIdent;
    Result.Start:= FPos;
    while (FPos <= Length(FText)) and IsIdentChar(FText[FPos]) do Inc(FPos);
  end
  else if C = QUOTE then
  begin
    Result.Kind:= tkString;
    ReadString;
  end
  else if CharInSet(C, ['0'..'9']) then
  begin
    Result.Kind:= tkSym;
    while (FPos <= Length(FText)) and IsIdentChar(FText[FPos]) do Inc(FPos);
  end
  else
  begin
    Result.Kind:= tkSym;
    Inc(FPos);
  end;
  Result.Stop:= FPos;
  Result.Text:= Copy(FText, Result.Start, Result.Stop - Result.Start);
end;

function TUsesLexer.DirectiveIn(AFrom, ATo: Integer): Boolean;
var
  P: Integer;
begin
  for P in FDirectives do
    if (P >= AFrom) and (P < ATo) then Exit(True);
  Result:= False;
end;

function IsWord(const T: TTok; const AWord: string): Boolean;
begin
  Result:= (T.Kind = tkIdent) and SameText(T.Text, AWord);
end;

function IsSym(const T: TTok; const ASym: string): Boolean;
begin
  Result:= (T.Kind = tkSym) and (T.Text = ASym);
end;

{ Reads 'Name[.Name...] [in 'path']' (, ...) ';' after an already-consumed
  'uses' token. False on any other shape. }
function ParseClause(ALex: TUsesLexer; const AUsesTok: TTok; var AClause: TUsesClause): Boolean;
var
  T      : TTok;
  E      : TUsesEntry;
  Entries: TList<TUsesEntry>;
  Commas : TList<TTok>;
begin
  Result := False;
  Entries:= TList<TUsesEntry>.Create;
  Commas := TList<TTok>.Create;
  try
    AClause.Start:= AUsesTok.Start;
    repeat
      T:= ALex.Next;
      if T.Kind <> tkIdent then Exit;
      E:= Default(TUsesEntry);
      E.Name := T.Text;
      E.Start:= T.Start;
      E.Stop := T.Stop;
      E.Depth:= T.Depth;
      T:= ALex.Next;
      while IsSym(T, '.') do
      begin
        T:= ALex.Next;
        if T.Kind <> tkIdent then Exit;
        E.Name:= E.Name + '.' + T.Text;
        E.Stop:= T.Stop;
        T:= ALex.Next;
      end;
      if IsWord(T, 'in') then
      begin
        T:= ALex.Next;
        if T.Kind <> tkString then Exit;
        E.Stop:= T.Stop;
        T:= ALex.Next;
      end;
      Entries.Add(E);
      if IsSym(T, ',') then
        Commas.Add(T)
      else if not IsSym(T, ';') then
        Exit;
    until IsSym(T, ';');
    AClause.Stop   := T.Stop;
    AClause.Present:= True;
    AClause.Entries:= Entries.ToArray;
    AClause.Commas := Commas.ToArray;
    Result:= True;
  finally
    Commas.Free;
    Entries.Free;
  end;
end;

type
  { The unit's text, LF-normalised, and its line starts: every line question
    the planner asks, and the rebuild of one uses clause's lines into edits. }
  TUnitText = class
  private
    FFilePath  : string;
    FText      : string;
    FLineStarts: TList<Integer>;
  public
    constructor Create(const AFilePath, AText: string);
    destructor Destroy; override;
    function LineOf(AOfs: Integer): Integer;
    function LineStop(ALine: Integer): Integer;
    function LineIsBlank(ALine: Integer): Boolean;
    function EmitRegion(const AC: TUsesClause; ASpans: TList<TSpan>; AInsAt: Integer;
      const AInsText: string; AWhole: Boolean; AEdits: TList<TTextEdit>): Integer;
    property Text: string read FText;
  end;

  { One planning run. A class so the many small steps share the lexed unit
    and the accumulating plan instead of passing a dozen parameters. }
  TUnitRulePlanner = class
  private
    FUnitPas   : string;
    FUnitName  : string;
    FUnit      : TUnitText;
    FText      : string;
    FLex       : TUsesLexer;
    FClauses   : array[0..1] of TUsesClause;
    FEdits     : TList<TTextEdit>;
    FChanges   : TList<TUsesChange>;
    FRemoveRule: TDictionary<string, string>;
    FAddSet    : TDictionary<string, Boolean>;
    FAdds      : array[0..1] of TList<TUsesChange>;
    FError     : string;
    FRefused   : Boolean;
    function ReadUnit: Boolean;
    procedure Normalise(const ARules: TConversionRuleSet; const AExtraAdds: TArray<string>);
    function IsPresent(const AName: string): Boolean;
    function SectionOf(const AName: string): Integer;
    procedure RequestAdd(const AName: string; ASection: Integer; const ARule: string);
    procedure RequestAdds(const ARules: TConversionRuleSet; const AExtraAdds, AInterfaceAdds: TArray<string>);
    function Refuse(const AMsg: string): Boolean;
    function RemovalSpans(const AC: TUsesClause; AIdx, ALastKept: Integer;
      AClaimed: TList<Integer>; ASpans: TList<TSpan>): Boolean;
    function MarkRemovals(const AC: TUsesClause; out ARemoved: TArray<Boolean>;
      out ALastKept: Integer): Boolean;
    function RecordChanges(const AC: TUsesClause; const ARemoved: TArray<Boolean>;
      AAdds: TList<TUsesChange>; AAddLine, AEmitted: Integer): Boolean;
    function PlanClause(AIdx: Integer): Boolean;
  public
    constructor Create(const AUnitPas, AText: string);
    destructor Destroy; override;
    function Run(const ARules: TConversionRuleSet; const AExtraAdds, AInterfaceAdds: TArray<string>): TUsesPlan;
  end;

function SwapRuleText(const R: TConversionRule): string;
begin
  Result:= '#useswap ' + R.UnitName + ' -> ' + String.Join(', ', R.UnitsAdd);
end;

constructor TUnitRulePlanner.Create(const AUnitPas, AText: string);
begin
  inherited Create;
  FUnitPas:= AUnitPas;
  FUnit   := TUnitText.Create(AUnitPas, AText);
  FText   := FUnit.Text;
  FLex    := TUsesLexer.Create(FText);
  FEdits  := TList<TTextEdit>.Create;
  FChanges:= TList<TUsesChange>.Create;
  FRemoveRule:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  FAddSet    := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FAdds[0]:= TList<TUsesChange>.Create;
  FAdds[1]:= TList<TUsesChange>.Create;
  FClauses[0]:= Default(TUsesClause);
  FClauses[1]:= Default(TUsesClause);
  FClauses[0].Section:= SECTION_INTF;
  FClauses[1].Section:= SECTION_IMPL;
end;

destructor TUnitRulePlanner.Destroy;
begin
  FAdds[1].Free;
  FAdds[0].Free;
  FAddSet.Free;
  FRemoveRule.Free;
  FChanges.Free;
  FEdits.Free;
  FLex.Free;
  FUnit.Free;
  inherited Destroy;
end;

constructor TUnitText.Create(const AFilePath, AText: string);
var
  I: Integer;
begin
  inherited Create;
  FFilePath  := AFilePath;
  FText      := AText.Replace(#13#10, LF).Replace(#13, LF);
  FLineStarts:= TList<Integer>.Create;
  FLineStarts.Add(1);
  for I:= 1 to Length(FText) do
    if FText[I] = LF then FLineStarts.Add(I + 1);
end;

destructor TUnitText.Destroy;
begin
  FLineStarts.Free;
  inherited Destroy;
end;

function TUnitText.LineOf(AOfs: Integer): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Lo:= 0;
  Hi:= FLineStarts.Count - 1;
  while Lo < Hi do
  begin
    Mid:= (Lo + Hi + 1) div 2;
    if FLineStarts[Mid] <= AOfs then Lo:= Mid else Hi:= Mid - 1;
  end;
  Result:= Lo + 1;
end;

{ Offset of the LF ending ALine (or Length + 1 for the last line). }
function TUnitText.LineStop(ALine: Integer): Integer;
begin
  if ALine < FLineStarts.Count then Result:= FLineStarts[ALine] - 1
  else Result:= Length(FText) + 1;
end;

function TUnitText.LineIsBlank(ALine: Integer): Boolean;
begin
  if (ALine < 1) or (ALine > FLineStarts.Count) then Exit(False);
  Result:= IsBlank(Copy(FText, FLineStarts[ALine - 1], LineStop(ALine) - FLineStarts[ALine - 1]));
end;

{ A deliberate refusal: the unit cannot be rewritten safely (apply/1
  refused=true). Always returns False, for Exit(Refuse(...)). }
function TUnitRulePlanner.Refuse(const AMsg: string): Boolean;
begin
  FError  := Format('%s: %s -- unit rules not applied to this unit', [ExtractFileName(FUnitPas), AMsg]);
  FRefused:= True;
  Result  := False;
end;

{ Finds 'unit', 'interface', 'implementation' and the uses clause straight
  after each section keyword. }
function TUnitRulePlanner.ReadUnit: Boolean;
var
  T: TTok;
begin
  T:= FLex.Next;
  if not IsWord(T, 'unit') then Exit(Refuse('not a unit (unit rules apply to a unit''s interface and implementation uses)'));
  T:= FLex.Next;
  FUnitName:= T.Text;
  T:= FLex.Next;
  while IsSym(T, '.') do
  begin
    T:= FLex.Next;
    FUnitName:= FUnitName + '.' + T.Text;
    T:= FLex.Next;
  end;
  while (T.Kind <> tkEof) and not IsWord(T, SECTION_INTF) do T:= FLex.Next;
  if T.Kind = tkEof then Exit(Refuse('no interface section found'));
  FClauses[0].KwLine:= FUnit.LineOf(T.Start);
  T:= FLex.Next;
  if IsWord(T, 'uses') then
  begin
    if not ParseClause(FLex, T, FClauses[0]) then
      Exit(Refuse(Format('could not read the interface uses clause (line %d)', [FUnit.LineOf(T.Start)])));
    T:= FLex.Next;
  end;
  while (T.Kind <> tkEof) and not IsWord(T, SECTION_IMPL) do T:= FLex.Next;
  if T.Kind = tkEof then Exit(Refuse('no implementation section found'));
  FClauses[1].KwLine:= FUnit.LineOf(T.Start);
  T:= FLex.Next;
  if IsWord(T, 'uses') and not ParseClause(FLex, T, FClauses[1]) then
    Exit(Refuse(Format('could not read the implementation uses clause (line %d)', [FUnit.LineOf(T.Start)])));
  Result:= True;
end;

{ ADD wins: every unit the book adds anywhere -- #use, a #useswap New, a
  #convert block's trailing units, the #convert To types' units -- is never
  removed, exactly as the editor's NormalizeUnitSets folds them. }
procedure TUnitRulePlanner.Normalise(const ARules: TConversionRuleSet; const AExtraAdds: TArray<string>);
var
  R: TConversionRule;
  U: string;
begin
  for R in ARules.Rules do
    case R.Kind of
      rkUse    : FAddSet.AddOrSetValue(R.UnitName, True);
      rkUseSwap, rkConvert:
        for U in R.UnitsAdd do FAddSet.AddOrSetValue(U, True);
    end;
  for U in AExtraAdds do FAddSet.AddOrSetValue(U, True);
  for R in ARules.Rules do
    if (R.UnitName <> '') and not FAddSet.ContainsKey(R.UnitName) and not FRemoveRule.ContainsKey(R.UnitName) then
      case R.Kind of
        rkUnuse  : FRemoveRule.Add(R.UnitName, '#unuse ' + R.UnitName);
        rkUseSwap: FRemoveRule.Add(R.UnitName, SwapRuleText(R));
      end;
end;

function TUnitRulePlanner.IsPresent(const AName: string): Boolean;
var
  S: Integer;
  E: TUsesEntry;
  C: TUsesChange;
begin
  for S:= 0 to 1 do
  begin
    for E in FClauses[S].Entries do
      if SameText(E.Name, AName) and not FRemoveRule.ContainsKey(E.Name) then Exit(True);
    for C in FAdds[S] do
      if SameText(C.UnitName, AName) then Exit(True);
  end;
  Result:= False;
end;

{ The section AName is used in: 0 interface (preferred when in both), 1
  implementation, -1 absent. }
function TUnitRulePlanner.SectionOf(const AName: string): Integer;
var
  S: Integer;
  E: TUsesEntry;
begin
  for S:= 0 to 1 do
    for E in FClauses[S].Entries do
      if SameText(E.Name, AName) then Exit(S);
  Result:= -1;
end;

procedure TUnitRulePlanner.RequestAdd(const AName: string; ASection: Integer; const ARule: string);
var
  C: TUsesChange;
begin
  if (Trim(AName) = '') or SameText(AName, FUnitName) or IsPresent(AName) then Exit;
  C:= Default(TUsesChange);
  C.Action  := 'add';
  C.UnitName:= Trim(AName);
  C.Section := FClauses[ASection].Section;
  C.Rule    := ARule;
  FAdds[ASection].Add(C);
end;

procedure TUnitRulePlanner.RequestAdds(const ARules: TConversionRuleSet; const AExtraAdds, AInterfaceAdds: TArray<string>);
var
  R: TConversionRule;
  U: string;
  S: Integer;
begin
  { C13 a: a To type whose retyped field is declared in the interface needs
    its unit THERE -- requested before any rule, so IsPresent then keeps a
    #use or the section rule below from adding it a second time }
  for U in AInterfaceAdds do RequestAdd(U, 0, '');
  for R in ARules.Rules do
    case R.Kind of
      rkUse: RequestAdd(R.UnitName, 1, '#use ' + R.UnitName);
      rkUseSwap:
      begin
        { a swap depends on Old: a unit that does not use it is not touched }
        S:= SectionOf(R.UnitName);
        if S < 0 then Continue;
        for U in R.UnitsAdd do RequestAdd(U, S, SwapRuleText(R));
      end;
    end;
  { the #convert surface's own uses-add: TFindUnitRefactoring's section rule }
  S:= 1;
  if (Length(FClauses[1].Entries) = 0) and (Length(FClauses[0].Entries) > 0) then S:= 0;
  for U in AExtraAdds do RequestAdd(U, S, '');
end;

{ The spans that remove entry AIdx and ONE adjacent comma: the following comma
  when a kept entry comes later, else the preceding one -- falling back to the
  other side when the preferred comma is conditional, already taken, or has a
  directive between it and the entry. False when neither side is safe. }
function TUnitRulePlanner.RemovalSpans(const AC: TUsesClause; AIdx, ALastKept: Integer;
  AClaimed: TList<Integer>; ASpans: TList<TSpan>): Boolean;
var
  E: TUsesEntry;

  function Span(AStart, AStop: Integer): TSpan;
  begin
    Result.Start:= AStart;
    Result.Stop := AStop;
  end;

  function TryFollow: Boolean;
  var
    Cm: TTok;
    P : Integer;
  begin
    Result:= False;
    if AIdx >= Length(AC.Commas) then Exit;
    Cm:= AC.Commas[AIdx];
    if (Cm.Depth > 0) or AClaimed.Contains(AIdx) or FLex.DirectiveIn(E.Start, Cm.Start) then Exit;
    P:= Cm.Stop;
    while (P <= Length(FText)) and CharInSet(FText[P], [' ', #9]) do Inc(P);
    if IsBlank(Copy(FText, E.Stop, Cm.Start - E.Stop)) then
      ASpans.Add(Span(E.Start, P))
    else
    begin
      ASpans.Add(Span(E.Start, E.Stop));
      ASpans.Add(Span(Cm.Start, P));
    end;
    AClaimed.Add(AIdx);
    Result:= True;
  end;

  function TryPrecede: Boolean;
  var
    Cm: TTok;
    P : Integer;
  begin
    Result:= False;
    if AIdx = 0 then Exit;
    Cm:= AC.Commas[AIdx - 1];
    if (Cm.Depth > 0) or AClaimed.Contains(AIdx - 1) or FLex.DirectiveIn(Cm.Start, E.Stop) then Exit;
    if IsBlank(Copy(FText, Cm.Stop, E.Start - Cm.Stop)) then
      ASpans.Add(Span(Cm.Start, E.Stop))
    else
    begin
      P:= E.Start;
      while (P > 1) and CharInSet(FText[P - 1], [' ', #9]) do Dec(P);
      if (P = 1) or (FText[P - 1] = LF) then P:= E.Start;  { keep a line's indent }
      ASpans.Add(Span(Cm.Start, Cm.Stop));
      ASpans.Add(Span(P, E.Stop));
    end;
    AClaimed.Add(AIdx - 1);
    Result:= True;
  end;

begin
  E:= AC.Entries[AIdx];
  if AIdx < ALastKept then Result:= TryFollow or TryPrecede
  else Result:= TryPrecede or TryFollow;
end;

{ Rebuilds the clause's lines with ASpans deleted and AInsText inserted at
  AInsAt (0 = none), then emits one delete + insert pair for those lines. A
  line whose every non-blank character was deleted is dropped whole. AWhole:
  the whole clause goes; when it owns its lines they are simply deleted. }
function TUnitText.EmitRegion(const AC: TUsesClause; ASpans: TList<TSpan>; AInsAt: Integer;
  const AInsText: string; AWhole: Boolean; AEdits: TList<TTextEdit>): Integer;
var
  FirstLine, LastLine, RegStart, RegStop, L, P, LS, LE, Kept: Integer;
  Mask   : TArray<Boolean>;
  Sp     : TSpan;
  Dropped: Boolean;
  SB     : TStringBuilder;
  E      : TTextEdit;
  AllGone: Boolean;
begin
  Result   := AEdits.Count;
  FirstLine:= LineOf(AC.Start);
  LastLine := LineOf(AC.Stop - 1);
  RegStart := FLineStarts[FirstLine - 1];
  RegStop  := LineStop(LastLine);
  E:= Default(TTextEdit);
  E.FilePath:= FFilePath;
  if AWhole and IsBlank(Copy(FText, RegStart, AC.Start - RegStart)) and IsBlank(Copy(FText, AC.Stop, RegStop - AC.Stop)) then
  begin
    E.Kind   := tekDeleteLines;
    E.Line   := FirstLine;
    E.EndLine:= LastLine;
    if LineIsBlank(FirstLine - 1) and LineIsBlank(LastLine + 1) then E.EndLine:= LastLine + 1;
    AEdits.Add(E);
    Exit(AEdits.Count - Result);
  end;
  SetLength(Mask, RegStop - RegStart + 1);
  for Sp in ASpans do
    for P:= Max(Sp.Start, RegStart) to Min(Sp.Stop, RegStop + 1) - 1 do Mask[P - RegStart]:= True;
  SB:= TStringBuilder.Create;
  try
    Kept:= 0;
    for L:= FirstLine to LastLine do
    begin
      LS:= FLineStarts[L - 1];
      LE:= LineStop(L);
      { drop a line emptied by the deletions, unless it merges into a neighbour }
      AllGone:= not IsBlank(Copy(FText, LS, LE - LS)) and not ((AInsAt >= LS) and (AInsAt <= LE));
      for P:= LS to LE - 1 do
        if (FText[P] > ' ') and not Mask[P - RegStart] then AllGone:= False;
      Dropped:= AllGone and ((L = FirstLine) or not Mask[LS - 1 - RegStart]) and
                ((L = LastLine) or not Mask[LE - RegStart]);
      if Dropped then Continue;
      for P:= LS to LE - 1 do
      begin
        if P = AInsAt then SB.Append(AInsText);
        if not Mask[P - RegStart] then SB.Append(FText[P]);
      end;
      if LE = AInsAt then SB.Append(AInsText);
      Inc(Kept);
      if (L < LastLine) and not Mask[LE - RegStart] then SB.Append(LF);
    end;
    if SB.ToString <> Copy(FText, RegStart, RegStop - RegStart) then
    begin
      E.Kind   := tekDeleteLines;
      E.Line   := FirstLine;
      E.EndLine:= LastLine;
      AEdits.Add(E);
      if Kept > 0 then
      begin
        E.Kind   := tekInsertLines;
        E.Line   := FirstLine - 1;
        E.EndLine:= 0;
        E.Text   := SB.ToString.Replace(LF, CRLF);
        AEdits.Add(E);
      end;
    end;
  finally
    SB.Free;
  end;
  Result:= AEdits.Count - Result;
end;

{ Marks the clause's entries the book removes and finds the last KEPT one
  (-1 when every entry goes). False -- refused -- when an entry to remove sits
  inside a conditional region: whether it is compiled in is not knowable here. }
function TUnitRulePlanner.MarkRemovals(const AC: TUsesClause; out ARemoved: TArray<Boolean>;
  out ALastKept: Integer): Boolean;
var
  I: Integer;
begin
  SetLength(ARemoved, Length(AC.Entries));
  ALastKept:= -1;
  for I:= 0 to High(AC.Entries) do
  begin
    ARemoved[I]:= FRemoveRule.ContainsKey(AC.Entries[I].Name);
    if ARemoved[I] and (AC.Entries[I].Depth > 0) then
      Exit(Refuse(Format('"%s" sits inside a conditional ({$IF...}) region of the %s uses clause',
        [AC.Entries[I].Name, AC.Section])));
    if not ARemoved[I] then ALastKept:= I;
  end;
  Result:= True;
end;

{ Records the clause's change rows. THE INVARIANT: a row never exists without
  an edit that realises it -- AEmitted = 0 with rows to report is a planner
  defect, so the unit is refused rather than reported with a phantom change. }
function TUnitRulePlanner.RecordChanges(const AC: TUsesClause; const ARemoved: TArray<Boolean>;
  AAdds: TList<TUsesChange>; AAddLine, AEmitted: Integer): Boolean;
var
  I : Integer;
  Ch: TUsesChange;
  A : TUsesChange;
begin
  if AEmitted = 0 then
  begin
    { a planner defect, NOT a refusal: the message is Refuse's, the flag is not }
    Result  := Refuse(Format('internal: the %s uses change produced no edit', [AC.Section]));
    FRefused:= False;
    Exit;
  end;
  for I:= 0 to High(AC.Entries) do
    if ARemoved[I] then
    begin
      Ch:= Default(TUsesChange);
      Ch.Action  := 'remove';
      Ch.UnitName:= AC.Entries[I].Name;
      Ch.Section := AC.Section;
      Ch.Line    := FUnit.LineOf(AC.Entries[I].Start);
      Ch.Rule    := FRemoveRule[AC.Entries[I].Name];
      FChanges.Add(Ch);
    end;
  for Ch in AAdds do
    if Ch.Rule <> '' then
    begin
      A:= Ch;
      A.Line:= AAddLine;
      FChanges.Add(A);
    end;
  Result:= True;
end;

function TUnitRulePlanner.PlanClause(AIdx: Integer): Boolean;
var
  C       : TUsesClause;
  Adds    : TList<TUsesChange>;
  Names   : TList<string>;
  Spans   : TList<TSpan>;
  Claimed : TList<Integer>;
  I, LastKept, Anchor, AddLine: Integer;
  Removed   : TArray<Boolean>;
  AnyRemoved: Boolean;
  Emitted   : Integer;  { edits EmitRegion / the clause insert produced }
  Ch        : TUsesChange;
  E         : TTextEdit;
  Sp        : TSpan;
begin
  C   := FClauses[AIdx];
  Adds:= FAdds[AIdx];
  if not MarkRemovals(C, Removed, LastKept) then Exit(False);
  Result    := True;
  AnyRemoved:= False;
  for I:= 0 to High(Removed) do AnyRemoved:= AnyRemoved or Removed[I];
  if (Adds.Count = 0) and not AnyRemoved then Exit;  { this clause is untouched }

  Names  := TList<string>.Create;
  Spans  := TList<TSpan>.Create;
  Claimed:= TList<Integer>.Create;
  try
    for Ch in Adds do Names.Add(Ch.UnitName);
    AddLine:= C.KwLine;
    if not C.Present then
    begin
      { no clause: nothing to remove, so there are adds -- create the clause }
      E:= Default(TTextEdit);
      E.FilePath:= FUnitPas;
      E.Kind    := tekInsertLines;
      E.Line    := C.KwLine;
      E.Text    := CRLF + 'uses ' + String.Join(', ', Names.ToArray) + ';';
      FEdits.Add(E);
      Emitted:= 1;
    end
    else if LastKept < 0 then
    begin
      if FLex.DirectiveIn(C.Start, C.Stop) then
        Exit(Refuse(Format('the %s uses clause holds a compiler directive, so it cannot be rewritten whole', [C.Section])));
      if Adds.Count = 0 then
      begin
        { the whole 'uses ... ;' goes. When it owns its lines EmitRegion deletes
          them; when it shares a line (a trailing comment, 'implementation
          uses X;') this span removes it and the rest of the line stays. }
        Sp.Start:= C.Start;
        Sp.Stop := C.Stop;
        I:= C.Start;
        while (I > 1) and CharInSet(FText[I - 1], [' ', #9]) do Dec(I);
        if (I > 1) and (FText[I - 1] <> LF) then Sp.Start:= I;  { 'implementation uses X;' }
        Spans.Add(Sp);
        Emitted:= FUnit.EmitRegion(C, Spans, 0, '', True, FEdits);
      end
      else
      begin
        { every entry goes and the adds take their place }
        Sp.Start:= C.Entries[0].Start;
        Sp.Stop := C.Entries[High(C.Entries)].Stop;
        Spans.Add(Sp);
        AddLine:= FUnit.LineOf(Sp.Start);
        Emitted:= FUnit.EmitRegion(C, Spans, Sp.Start, String.Join(', ', Names.ToArray), False, FEdits);
      end;
    end
    else
    begin
      for I:= 0 to High(C.Entries) do
        if Removed[I] and not RemovalSpans(C, I, LastKept, Claimed, Spans) then
          Exit(Refuse(Format('removing "%s" from the %s uses clause would cross a conditional directive ({$IF...})',
            [C.Entries[I].Name, C.Section])));
      Anchor:= -1;
      for I:= 0 to High(C.Entries) do
        if not Removed[I] and (C.Entries[I].Depth = 0) then Anchor:= I;
      if (Adds.Count > 0) and (Anchor < 0) then
        Exit(Refuse(Format('the %s uses clause has no unconditional entry to add "%s" after', [C.Section, Names[0]])));
      if Adds.Count > 0 then
      begin
        AddLine:= FUnit.LineOf(C.Entries[Anchor].Start);
        Emitted:= FUnit.EmitRegion(C, Spans, C.Entries[Anchor].Stop, ', ' + String.Join(', ', Names.ToArray), False, FEdits);
      end
      else
        Emitted:= FUnit.EmitRegion(C, Spans, 0, '', False, FEdits);
    end;

    Result:= RecordChanges(C, Removed, Adds, AddLine, Emitted);
  finally
    Claimed.Free;
    Spans.Free;
    Names.Free;
  end;
end;

function TUnitRulePlanner.Run(const ARules: TConversionRuleSet; const AExtraAdds, AInterfaceAdds: TArray<string>): TUsesPlan;
begin
  Result:= Default(TUsesPlan);
  if ReadUnit then
  begin
    Normalise(ARules, AExtraAdds);
    RequestAdds(ARules, AExtraAdds, AInterfaceAdds);
    if PlanClause(0) and PlanClause(1) then
    begin
      Result.Ok     := True;
      Result.Edits  := FEdits.ToArray;
      Result.Changes:= FChanges.ToArray;
      Exit;
    end;
  end;
  Result.Error  := FError;
  Result.Refused:= FRefused;
end;

function BookHasUnitRules(const ARules: TConversionRuleSet): Boolean;
var
  R: TConversionRule;
begin
  for R in ARules.Rules do
    if R.Kind in [rkUnuse, rkUse, rkUseSwap] then Exit(True);
  Result:= False;
end;

function PlanUnitRules(const AUnitPas, AText: string; const ARules: TConversionRuleSet;
  const AExtraAdds: TArray<string>; const AInterfaceAdds: TArray<string>): TUsesPlan;
var
  Planner: TUnitRulePlanner;
begin
  Planner:= TUnitRulePlanner.Create(AUnitPas, AText);
  try
    Result:= Planner.Run(ARules, AExtraAdds, AInterfaceAdds);
  finally
    Planner.Free;
  end;
end;

end.
