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
  /// <summary>One reason a uses entry is still needed, or still referenced:
  /// a name and where it sits (C9, apply/1 uses[].needed_by).</summary>
  /// <remarks>For a `kept` row Name is a .dfm component, 'Name: Class', and
  /// Line its object header line in the .dfm; for a reconcile `add` it is the
  /// introduced name and its line in the converted .pas; for a `remove` row it
  /// is a .pas reference the removal leaves dangling (owner ruling 1: the
  /// compile error is the intended signal). Section is the .pas section of the
  /// reference ('interface' / 'implementation'), or 'dfm'.</remarks>
  TUsesNeed = record
    Name   : string;
    Line   : Integer;
    Section: string;
  end;

  /// <summary>One uses-clause change convert-apply makes, or decides not to
  /// make, to the unit being converted -- one row of apply/1 'uses'.</summary>
  /// <remarks>
  /// Action is one of:
  /// 'remove' -- an entry taken out (a #unuse / #useswap Old, or a C9 watched
  /// unit nothing the converted .dfm streams still needs);
  /// 'add' -- an entry written (a #use / #useswap New, or a C9 reconcile add);
  /// 'kept' (C9) -- a watched entry NOT removed: Reason says why (a .dfm
  /// component still needs it, no --db indexes it, or the re-index failed),
  /// NeededBy names the components; no edit behind the row;
  /// 'moved' (C9) -- the C13 move of an entry from the implementation to the
  /// interface uses, Section 'interface';
  /// 'skipped' (1.23.0, C13 N4) -- a removal NOT made because it would strand
  /// instances --only left out; no edit behind it, Line/Section are the kept
  /// entry's, Reason 'would leave N unconverted instance(s) of T'.
  /// Section is 'interface' or 'implementation'. Line is 1-based in the unit
  /// AS READ, before any edit: a removed or kept entry's own line; for an add,
  /// the line the name is written onto (the entry it is appended after, or the
  /// first entry it replaces), or the section keyword's line when a new uses
  /// clause is created. Rule is the book line behind the row, normalised to
  /// '#unuse Old', '#use New' or '#useswap Old -&gt; New1, New2', '' for a
  /// row no rule asked for. UnitName is spelled as written in the unit for a
  /// removal, kept or moved row and as written in the book for an add.
  /// Reason is '' unless kept or skipped. Source (C9) says what produced the
  /// row: 'rule' (a book line), 'reconcile' (a name the conversion introduced)
  /// or 'convert' (the #convert surface's own To-type add, reported only when
  /// it MOVES a unit). NeededBy (C9) is why the row exists -- see TUsesNeed.
  /// </remarks>
  TUsesChange = record
    Action  : string;
    UnitName: string;
    Section : string;
    Line    : Integer;
    Rule    : string;
    Reason  : string;
    /// <summary>C9: 'rule' (a book line asked for it), 'reconcile' (a name the
    /// conversion introduced needs it) or 'convert' (the #convert surface's own
    /// To-type add, reported only when it MOVES a unit).</summary>
    Source  : string;
    /// <summary>C9: why the row exists -- see TUsesNeed. Empty unless kept,
    /// a reconcile add, or a removal that leaves references dangling.</summary>
    NeededBy: TArray<TUsesNeed>;
  end;

  /// <summary>True when two uses-entry spellings name ONE unit (C9 R9: scope
  /// aliases, 'DB' and 'Data.DB').</summary>
  TSameUnitFunc = reference to function(const A, B: string): Boolean;

  /// <summary>A watched entry the reconciler decided to KEEP (C9).</summary>
  /// <remarks>UnitName is the entry as written in the unit. Action is 'kept'
  /// or 'skipped' (the C13 N4 --only shape, kept byte-compatible).</remarks>
  TUsesKeep = record
    UnitName: string;
    Action  : string;
    Reason  : string;
    NeededBy: TArray<TUsesNeed>;
  end;

  /// <summary>A unit the reconciler adds because a name the conversion
  /// introduced resolves to it (C9 R7).</summary>
  TUsesReconAdd = record
    UnitName : string;
    ToInterface: Boolean;
    NeededBy   : TArray<TUsesNeed>;
  end;

  /// <summary>The reconciler's verdicts, handed to PlanUnitRules (C9).</summary>
  /// <remarks>Enabled=False (Default) is the 1.26 planner exactly. With
  /// Enabled: a watched entry named in Keeps is not removed and gets a row of
  /// its own; Adds are requested like #use (into their section, a move when
  /// present in the implementation only); Dangling carries the needed_by of
  /// remove rows (UnitName = entry); SameUnit makes presence, removal and the
  /// ADD-wins normalisation scope-alias aware (nil = case-insensitive equality).
  /// A C13 move is reported as a 'moved' row.</remarks>
  TUsesNeeds = record
    Enabled : Boolean;
    SameUnit: TSameUnitFunc;
    Keeps   : TArray<TUsesKeep>;
    Adds    : TArray<TUsesReconAdd>;
    Dangling: TArray<TUsesKeep>;
  end;

  /// <summary>One entry of a unit's uses clauses as the planner reads it.</summary>
  TUsesEntryInfo = record
    Name       : string;
    Section    : string;
    Line       : Integer;
    Conditional: Boolean;
  end;

  /// <summary>One unit the book removes (the WATCH LIST, C9) and the rule
  /// text that removes it, after the ADD-wins normalisation.</summary>
  TWatchUnit = record
    UnitName: string;
    Rule    : string;
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
/// not pull it into the implementation; one the unit uses ONLY in its
/// implementation clause is MOVED (removed there, added to the interface; no
/// TUsesChange row). Default nil: every extra add takes the section rule
/// above.</param>
/// <returns>The plan; see TUsesPlan. Ok=False (with Error) when the text is
/// not a unit with interface and implementation sections, when a clause
/// cannot be read, when an entry to remove sits in a conditional region, when
/// a removal would cross a conditional directive, or when an add has no
/// unconditional entry to follow.</returns>
/// <remarks>Pure: reads nothing but its arguments and writes nothing. The
/// contract (remove Old, add each New once in any case, keep Old's section) is
/// pinned by tests\autotest\run_convert_apply_unit_rules.ps1.</remarks>
function PlanUnitRules(const AUnitPas, AText: string; const ARules: TConversionRuleSet;
  const AExtraAdds: TArray<string>; const AInterfaceAdds: TArray<string> = nil): TUsesPlan; overload;

/// <summary>PlanUnitRules with the C9 reconciler's verdicts (see TUsesNeeds).</summary>
/// <param name="AUnitPas">As the other overload.</param>
/// <param name="AText">As the other overload.</param>
/// <param name="ARules">As the other overload.</param>
/// <param name="AExtraAdds">As the other overload.</param>
/// <param name="AInterfaceAdds">As the other overload.</param>
/// <param name="ANeeds">The verdicts; Default(TUsesNeeds) is the other overload.</param>
/// <returns>The plan. Rows gain Source / NeededBy; a kept entry plans no edit
/// and never refuses (a {$IF} entry included).</returns>
/// <remarks>Pure. Pinned by tests\autotest\run_convert_apply_uses_reconcile.ps1.</remarks>
function PlanUnitRules(const AUnitPas, AText: string; const ARules: TConversionRuleSet;
  const AExtraAdds, AInterfaceAdds: TArray<string>; const ANeeds: TUsesNeeds): TUsesPlan; overload;

/// <summary>The entries of a unit's interface and implementation uses
/// clauses, read with the planner's own lexer (C9).</summary>
/// <param name="AUnitPas">The unit's path (for the error text only).</param>
/// <param name="AText">The unit's text.</param>
/// <param name="AEntries">Out: every entry, interface first, in order.</param>
/// <returns>False when the text cannot be read as a unit (AEntries empty).</returns>
/// <remarks>Pure.</remarks>
function ReadUsesEntries(const AUnitPas, AText: string; out AEntries: TArray<TUsesEntryInfo>): Boolean;

/// <summary>The units ARules removes -- every #unuse and #useswap Old -- after
/// the ADD-wins normalisation PlanUnitRules applies (C9 watch list).</summary>
/// <param name="ARules">The parsed rule book.</param>
/// <param name="AExtraAdds">Units the #convert surface adds (never watched).</param>
/// <param name="ASameUnit">Alias predicate for ADD wins; nil = equality.</param>
/// <returns>One entry per watched unit, book spelling, in book order.</returns>
/// <remarks>Pure.</remarks>
function UnitRuleWatchList(const ARules: TConversionRuleSet; const AExtraAdds: TArray<string>;
  const ASameUnit: TSameUnitFunc): TArray<TWatchUnit>;

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
  TUnitRulePlanner = class  // dl:ok high-response@7a45 -- REVIEWED 2026-10-06: 51 since PlanMoves (C13 a) joined; one uses-clause rewrite whose steps share the parsed clauses -- splitting it would pass that state between classes
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
    FNeeds     : TUsesNeeds;                    { C9; Enabled=False = the 1.26 planner }
    FMoved     : TDictionary<string, Boolean>;  { C9: units a C13 move relocates }
    function ReadUnit: Boolean;
    procedure Normalise(const ARules: TConversionRuleSet; const AExtraAdds: TArray<string>);
    function Same(const A, B: string): Boolean;
    function InAddSet(const AName: string): Boolean;
    function RuleFor(const AEntry: string; out ARule: string): Boolean;
    function IsKept(const AEntry: string): Boolean;
    function DanglingOf(const AEntry: string): TArray<TUsesNeed>;
    procedure RecordKeeps;
    function IsPresent(const AName: string): Boolean;
    function SectionOf(const AName: string): Integer;
    procedure RequestAdd(const AName: string; ASection: Integer; const ARule: string;
      const ASource: string = ''; const ANeededBy: TArray<TUsesNeed> = nil);
    procedure RequestAdds(const ARules: TConversionRuleSet; const AExtraAdds, AInterfaceAdds: TArray<string>);
    procedure PlanMoves(const AInterfaceAdds: TArray<string>);
    function Refuse(const AMsg: string): Boolean;
    function RemovalSpans(const AC: TUsesClause; AIdx, ALastKept: Integer;
      AClaimed: TList<Integer>; ASpans: TList<TSpan>): Boolean;
    function MarkRemovals(const AC: TUsesClause; out ARemoved: TArray<Boolean>;
      out ALastKept: Integer): Boolean;
    function RecordChanges(const AC: TUsesClause; const ARemoved: TArray<Boolean>;
      AAdds: TList<TUsesChange>; AAddLine, AEmitted: Integer): Boolean;
    function PlanClause(AIdx: Integer): Boolean;
  public
    constructor Create(const AUnitPas, AText: string; const ANeeds: TUsesNeeds);
    destructor Destroy; override;
    function Run(const ARules: TConversionRuleSet; const AExtraAdds, AInterfaceAdds: TArray<string>): TUsesPlan;
    function Entries(out AEntries: TArray<TUsesEntryInfo>): Boolean;
    function WatchList(const ARules: TConversionRuleSet; const AExtraAdds: TArray<string>): TArray<TWatchUnit>;
  end;

function SwapRuleText(const R: TConversionRule): string;
begin
  Result:= '#useswap ' + R.UnitName + ' -> ' + String.Join(', ', R.UnitsAdd);
end;

constructor TUnitRulePlanner.Create(const AUnitPas, AText: string; const ANeeds: TUsesNeeds);
begin
  inherited Create;
  FNeeds  := ANeeds;
  FMoved  := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
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
  FMoved.Free;
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
    if (R.UnitName <> '') and not InAddSet(R.UnitName) and not FRemoveRule.ContainsKey(R.UnitName) then
      case R.Kind of
        rkUnuse  : FRemoveRule.Add(R.UnitName, '#unuse ' + R.UnitName);
        rkUseSwap: FRemoveRule.Add(R.UnitName, SwapRuleText(R));
      end;
end;

{ C9: two spellings name one unit -- scope-alias aware when the reconciler
  handed a predicate, plain case-insensitive equality otherwise (1.26). }
function TUnitRulePlanner.Same(const A, B: string): Boolean;
begin
  if FNeeds.Enabled and Assigned(FNeeds.SameUnit) then Result:= FNeeds.SameUnit(A, B)
  else Result:= SameText(A, B);
end;

function TUnitRulePlanner.InAddSet(const AName: string): Boolean;
begin
  Result:= FAddSet.ContainsKey(AName);
  if Result or not FNeeds.Enabled then Exit;
  for var K: string in FAddSet.Keys do
    if Same(K, AName) then Exit(True);
end;

{ The removal rule that names the entry AEntry -- the exact spelling first (a
  C13 move is keyed by the entry itself, rule ''), then, under C9, any watched
  unit the entry is an alias of. False when nothing removes it. }
function TUnitRulePlanner.RuleFor(const AEntry: string; out ARule: string): Boolean;
begin
  Result:= FRemoveRule.TryGetValue(AEntry, ARule);
  if Result or not FNeeds.Enabled then Exit;
  for var P: TPair<string, string> in FRemoveRule do
    if (P.Value <> '') and Same(P.Key, AEntry) then
    begin
      ARule:= P.Value;
      Exit(True);
    end;
end;

function TUnitRulePlanner.IsKept(const AEntry: string): Boolean;
begin
  if FNeeds.Enabled then
    for var K: TUsesKeep in FNeeds.Keeps do
      if SameText(K.UnitName, AEntry) then Exit(True);
  Result:= False;
end;

function TUnitRulePlanner.DanglingOf(const AEntry: string): TArray<TUsesNeed>;
begin
  Result:= nil;
  for var D: TUsesKeep in FNeeds.Dangling do
    if SameText(D.UnitName, AEntry) then Exit(D.NeededBy);
end;

{ C9: one row per watched entry the reconciler KEPT -- no edit behind it,
  Line/Section the entry's own, after every edit-backed row. }
procedure TUnitRulePlanner.RecordKeeps;
var
  Rule: string;
begin
  for var K: TUsesKeep in FNeeds.Keeps do
    for var S: Integer:= 0 to 1 do
      for var E: TUsesEntry in FClauses[S].Entries do
        if SameText(E.Name, K.UnitName) and RuleFor(E.Name, Rule) and (Rule <> '') then
        begin
          var Ch: TUsesChange:= Default(TUsesChange);
          Ch.Action  := K.Action;
          Ch.UnitName:= E.Name;
          Ch.Section := FClauses[S].Section;
          Ch.Line    := FUnit.LineOf(E.Start);
          Ch.Rule    := Rule;
          Ch.Reason  := K.Reason;
          Ch.Source  := 'rule';
          Ch.NeededBy:= K.NeededBy;
          FChanges.Add(Ch);
        end;
end;

function TUnitRulePlanner.IsPresent(const AName: string): Boolean;
var
  S   : Integer;
  E   : TUsesEntry;
  C   : TUsesChange;
  Rule: string;
begin
  for S:= 0 to 1 do
  begin
    for E in FClauses[S].Entries do
      if Same(E.Name, AName) and (IsKept(E.Name) or not RuleFor(E.Name, Rule)) then Exit(True);
    for C in FAdds[S] do
      if Same(C.UnitName, AName) then Exit(True);
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
      if Same(E.Name, AName) then Exit(S);
  Result:= -1;
end;

procedure TUnitRulePlanner.RequestAdd(const AName: string; ASection: Integer; const ARule: string;
  const ASource: string; const ANeededBy: TArray<TUsesNeed>);
var
  C: TUsesChange;
begin
  if (Trim(AName) = '') or SameText(AName, FUnitName) or IsPresent(AName) then Exit;
  C:= Default(TUsesChange);
  C.Action  := 'add';
  C.UnitName:= Trim(AName);
  C.Section := FClauses[ASection].Section;
  C.Rule    := ARule;
  C.Source  := if (ASource = '') and (ARule <> '') then 'rule' else ASource;
  C.NeededBy:= ANeededBy;
  FAdds[ASection].Add(C);
end;

{ C13 a: a unit an INTERFACE declaration needs that the unit uses only in its
  implementation clause is MOVED -- removed there (a removal with no rule, so
  no uses[] row) and then added to the interface by RequestAdds. Left where it
  is, the interface declaration fails E2003. }
procedure TUnitRulePlanner.PlanMoves(const AInterfaceAdds: TArray<string>);
var
  U: string;

  procedure Move(const AUnit: string);
  begin
    if SectionOf(AUnit) <> 1 then Exit;
    for var E: TUsesEntry in FClauses[1].Entries do
      if Same(E.Name, AUnit) then
      begin
        FRemoveRule.AddOrSetValue(E.Name, '');
        FMoved.AddOrSetValue(AUnit, True);
      end;
  end;

begin
  for U in AInterfaceAdds do Move(U);
  { C9: a reconcile add an interface declaration needs moves the same way }
  if FNeeds.Enabled then
    for var A: TUsesReconAdd in FNeeds.Adds do
      if A.ToInterface then Move(A.UnitName);
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
  { C9 R7: units a name the conversion introduced resolves to }
  if FNeeds.Enabled then
    for var A: TUsesReconAdd in FNeeds.Adds do
      RequestAdd(A.UnitName, if A.ToInterface then 0 else 1, '', 'reconcile', A.NeededBy);
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
  I   : Integer;
  Rule: string;
begin
  SetLength(ARemoved, Length(AC.Entries));
  ALastKept:= -1;
  for I:= 0 to High(AC.Entries) do
  begin
    { C9 R12: an entry the reconciler KEEPS plans no edit, so it never refuses }
    ARemoved[I]:= RuleFor(AC.Entries[I].Name, Rule) and not IsKept(AC.Entries[I].Name);
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
  I   : Integer;
  Ch  : TUsesChange;
  A   : TUsesChange;
  Rule: string;
begin
  if AEmitted = 0 then
  begin
    { a planner defect, NOT a refusal: the message is Refuse's, the flag is not }
    Result  := Refuse(Format('internal: the %s uses change produced no edit', [AC.Section]));
    FRefused:= False;
    Exit;
  end;
  for I:= 0 to High(AC.Entries) do
  begin
    if not ARemoved[I] then Continue;
    RuleFor(AC.Entries[I].Name, Rule);
    Ch:= Default(TUsesChange);
    Ch.UnitName:= AC.Entries[I].Name;
    Ch.Section := AC.Section;
    Ch.Line    := FUnit.LineOf(AC.Entries[I].Start);
    Ch.Rule    := Rule;
    if Rule <> '' then
    begin
      Ch.Action  := 'remove';
      Ch.Source  := 'rule';
      Ch.NeededBy:= DanglingOf(Ch.UnitName);
      FChanges.Add(Ch);
    end
    else if FNeeds.Enabled then
    begin
      { C9 R10: the C13 move is reported -- a 'moved' row naming its
        destination; 1.26 kept it silent as the #convert surface }
      Ch.Action := 'moved';
      Ch.Section:= SECTION_INTF;
      Ch.Source := 'convert';
      for var RA: TUsesReconAdd in FNeeds.Adds do
        if RA.ToInterface and Same(RA.UnitName, Ch.UnitName) then
        begin
          Ch.Source  := 'reconcile';
          Ch.NeededBy:= RA.NeededBy;
        end;
      FChanges.Add(Ch);
    end;
  end;
  for Ch in AAdds do
    if ((Ch.Rule <> '') or (Ch.Source = 'reconcile')) and not FMoved.ContainsKey(Ch.UnitName) then
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
    PlanMoves(AInterfaceAdds);
    RequestAdds(ARules, AExtraAdds, AInterfaceAdds);
    if PlanClause(0) and PlanClause(1) then
    begin
      if FNeeds.Enabled then RecordKeeps;
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

function TUnitRulePlanner.Entries(out AEntries: TArray<TUsesEntryInfo>): Boolean;
begin
  AEntries:= nil;
  if not ReadUnit then Exit(False);
  for var S: Integer:= 0 to 1 do
    for var E: TUsesEntry in FClauses[S].Entries do
    begin
      var Info: TUsesEntryInfo:= Default(TUsesEntryInfo);
      Info.Name       := E.Name;
      Info.Section    := FClauses[S].Section;
      Info.Line       := FUnit.LineOf(E.Start);
      Info.Conditional:= E.Depth > 0;
      AEntries:= AEntries + [Info];
    end;
  Result:= True;
end;

function TUnitRulePlanner.WatchList(const ARules: TConversionRuleSet; const AExtraAdds: TArray<string>): TArray<TWatchUnit>;
begin
  Result:= nil;
  Normalise(ARules, AExtraAdds);
  { book order: FRemoveRule is a dictionary, so walk the rules again }
  for var R: TConversionRule in ARules.Rules do
    if (R.Kind in [rkUnuse, rkUseSwap]) and FRemoveRule.ContainsKey(R.UnitName) then
    begin
      var W: TWatchUnit;
      W.UnitName:= R.UnitName;
      W.Rule    := FRemoveRule[R.UnitName];
      var Dup: Boolean:= False;
      for var X: TWatchUnit in Result do
        if SameText(X.UnitName, W.UnitName) then Dup:= True;
      if not Dup then Result:= Result + [W];
    end;
end;

function PlanUnitRules(const AUnitPas, AText: string; const ARules: TConversionRuleSet;
  const AExtraAdds: TArray<string>; const AInterfaceAdds: TArray<string>): TUsesPlan;
begin
  Result:= PlanUnitRules(AUnitPas, AText, ARules, AExtraAdds, AInterfaceAdds, Default(TUsesNeeds));
end;

function PlanUnitRules(const AUnitPas, AText: string; const ARules: TConversionRuleSet;
  const AExtraAdds, AInterfaceAdds: TArray<string>; const ANeeds: TUsesNeeds): TUsesPlan;
var
  Planner: TUnitRulePlanner;
begin
  Planner:= TUnitRulePlanner.Create(AUnitPas, AText, ANeeds);
  try
    Result:= Planner.Run(ARules, AExtraAdds, AInterfaceAdds);
  finally
    Planner.Free;
  end;
end;

function ReadUsesEntries(const AUnitPas, AText: string; out AEntries: TArray<TUsesEntryInfo>): Boolean;
var
  Planner: TUnitRulePlanner;
begin
  Planner:= TUnitRulePlanner.Create(AUnitPas, AText, Default(TUsesNeeds));
  try
    Result:= Planner.Entries(AEntries);
  finally
    Planner.Free;
  end;
end;

function UnitRuleWatchList(const ARules: TConversionRuleSet; const AExtraAdds: TArray<string>;
  const ASameUnit: TSameUnitFunc): TArray<TWatchUnit>;
var
  Planner: TUnitRulePlanner;
  Needs  : TUsesNeeds;
begin
  Needs:= Default(TUsesNeeds);
  Needs.Enabled := Assigned(ASameUnit);
  Needs.SameUnit:= ASameUnit;
  Planner:= TUnitRulePlanner.Create('', '', Needs);
  try
    Result:= Planner.WatchList(ARules, AExtraAdds);
  finally
    Planner.Free;
  end;
end;

end.
