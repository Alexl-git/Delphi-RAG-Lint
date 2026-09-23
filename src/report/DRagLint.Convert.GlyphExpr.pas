unit DRagLint.Convert.GlyphExpr;

{ Parser and static validator for the G[I/N] glyph-expression grammar that may
  follow a #link FromPath
  (docs\superpowers\specs\2026-09-17-glyph-strip-G-grammar-design.md, sections
  3.1-3.3 and 8):

      G-expr      := alternative ( ',' alternative )*
      alternative := term ( term )*        -- concatenation stitches, left to right
      term        := 'G[' I '/' N ']' | 'G[' I ']' | 'G[*/' N ']' | 'G[count]'

  Pure: no I/O, no globals, strings in and records out.

  This is the VALIDATE half (CV-4). Selecting an alternative for an actual N,
  extracting and stitching the slots, and realising the result in convert-apply
  are CV-2's build; they consume TGlyphExpr exactly as it is parsed here. }

interface

uses
  System.SysUtils;

type
  /// <summary>The shape of one G[..] term of a glyph expression.</summary>
  /// <remarks>
  /// gtkSlotOfCount = 'G[I/N]', slot I of a source known to hold N glyphs.
  /// gtkSlot = 'G[I]', slot I of the ACTUAL count (no denominator).
  /// gtkAllOfCount = 'G[*/N]', all N slots in order (the identity for that N).
  /// gtkCount = 'G[count]', an integer: the number of terms in the alternative
  /// chosen for the sibling image link on the same FromPath.
  /// </remarks>
  TGlyphTermKind = (gtkSlotOfCount, gtkSlot, gtkAllOfCount, gtkCount);

  /// <summary>One parsed G[..] term.</summary>
  /// <remarks>
  /// Slot is I (1-based), 0 for gtkAllOfCount and gtkCount. Count is N, 0 for
  /// gtkSlot and gtkCount. Column is the 1-based column of the term's 'G' in the
  /// expression text, so an error can point at it. A parsed term is SYNTAX
  /// only; its ranges are checked by ValidateGlyphExpr.
  /// </remarks>
  TGlyphTerm = record
    Kind  : TGlyphTermKind;
    Slot  : Integer;
    Count : Integer;
    Column: Integer;
  end;

  /// <summary>One comma-separated alternative: terms stitched left to right.</summary>
  /// <remarks>Column is the 1-based column of the alternative's first term (or,
  /// for an empty alternative, where one was expected).</remarks>
  TGlyphAlternative = record
    Terms : TArray<TGlyphTerm>;
    Column: Integer;
  end;

  /// <summary>A parsed glyph expression.</summary>
  /// <remarks>Text is the expression VERBATIM as it appeared on the #link line
  /// (the editor round-trips it byte-exact); Alternatives are in source
  /// order.</remarks>
  TGlyphExpr = record
    Text        : string;
    Alternatives: TArray<TGlyphAlternative>;
  end;

  /// <summary>One problem found in a glyph expression.</summary>
  /// <remarks>Column is 1-based within the expression text; Message is
  /// ASCII-only prose that does NOT repeat the column.</remarks>
  TGlyphExprError = record
    Column : Integer;
    Message: string;
  end;

/// <summary>Parses the SYNTAX of a glyph expression.</summary>
/// <param name="AText">The expression as split off a #link FromPath, e.g.
/// 'G[*/4], G[1/5]G[2/5]'. Spaces are allowed between terms and around commas,
/// never inside G[..].</param>
/// <param name="AExpr">Receives the parsed expression. On a syntax error it
/// holds what was parsed before the error and must not be used.</param>
/// <returns>Empty when the text is well-formed. Otherwise exactly ONE error: the
/// first malformed position (parsing stops there, because every later column
/// would be a guess).</returns>
/// <remarks>Total: never raises. Accepts 'count' case-insensitively, like the
/// DSL's directives. Numbers are plain decimals of at most six digits; range
/// checks (I in 1..N, N at least 1) are ValidateGlyphExpr's job, so 'G[0/4]'
/// parses cleanly and then fails validation. Pure.</remarks>
function ParseGlyphExpr(const AText: string; out AExpr: TGlyphExpr): TArray<TGlyphExprError>;

/// <summary>Checks the static rules of a well-formed glyph expression.</summary>
/// <param name="AExpr">An expression ParseGlyphExpr accepted.</param>
/// <returns>Empty when valid; otherwise one error per problem, in source
/// order.</returns>
/// <remarks>
/// Errors: a slot below 1; a count below 1; a slot above its count ('G[5/4]',
/// or a 'G[I]' above the N its alternative's denominators fix); two different
/// denominators in one alternative; two alternatives with the same N; two
/// denominator-less alternatives; 'G[count]' anywhere but as the whole
/// expression. What this CANNOT check, because it needs other rules or the
/// index: that a 'G[count]' has exactly one sibling image link (done by
/// ValidateConversionRules over the #convert block), and that the source class
/// has an N reader (CV-2). Pure.
/// </remarks>
function ValidateGlyphExpr(const AExpr: TGlyphExpr): TArray<TGlyphExprError>;

/// <summary>True when the expression is exactly 'G[count]'.</summary>
/// <param name="AExpr">A parsed expression.</param>
/// <returns>True for a single alternative holding a single gtkCount term.</returns>
/// <remarks>A 'G[count]' link carries the target's glyph COUNT; every other
/// G-link is an IMAGE link. Pure.</remarks>
function IsGlyphCountExpr(const AExpr: TGlyphExpr): Boolean;

/// <summary>True when a property name is a known glyph-count property.</summary>
/// <param name="AName">A bare ('NumGlyphs') or dotted ('OptionsImage.NumGlyphs')
/// property path; only its LAST segment is compared, case-insensitively.</param>
/// <returns>True for NumGlyphs, GlyphCount, NumStates or ImageCount.</returns>
/// <remarks>Shared by the glyph vacuum (which reads the count leaf off a .dfm
/// object) and convert-validate (which warns on a straight count carry beside a
/// G-link), so the two cannot disagree about which names count. Pure.</remarks>
function IsGlyphCountPropName(const AName: string): Boolean;

implementation

const
  TermOpen       = 'G[';
  TermClose      = ']';
  CountWord      = 'count';
  AllSlots       = '*';
  CountSep       = '/';
  AltSep         = ',';
  MaxNumberDigits = 6;
  GlyphCountPropNames: array[0..3] of string = ('NumGlyphs', 'GlyphCount', 'NumStates', 'ImageCount');

function MakeError(AColumn: Integer; const AMessage: string): TGlyphExprError;
begin
  Result.Column := AColumn;
  Result.Message:= AMessage;
end;

// The single-error result ParseGlyphExpr returns when it stops. A function
// rather than an 'Exit([..])' literal: the compiler reads a bracket literal in
// Exit as a SET constructor (E2001).
function OnlyError(AColumn: Integer; const AMessage: string): TArray<TGlyphExprError>;
begin
  Result:= [MakeError(AColumn, AMessage)];
end;

// A plain decimal of 1..MaxNumberDigits ASCII digits; False on anything else
// (sign, blank, non-ASCII digit, overflow-sized).
function TryParseNumber(const AText: string; out AValue: Integer): Boolean;
var
  Ch: Char;
begin
  AValue:= 0;
  Result:= (AText <> '') and (Length(AText) <= MaxNumberDigits);
  if not Result then Exit;
  for Ch in AText do
    if not CharInSet(Ch, ['0'..'9']) then Exit(False);
  AValue:= StrToInt(AText);
end;

// The text between 'G[' and ']' -> ATerm.Kind/Slot/Count. ABodyCol is the
// body's first column in the whole expression.
function ParseTermBody(const ABody: string; ABodyCol: Integer; var ATerm: TGlyphTerm;
  out AError: TGlyphExprError): Boolean;
var
  SepAt    : Integer;
  SlotText : string;
  CountText: string;
begin
  Result:= False;
  AError:= Default(TGlyphExprError);
  if SameText(ABody, CountWord) then
  begin
    ATerm.Kind:= gtkCount;
    Exit(True);
  end;
  SepAt:= Pos(CountSep, ABody);
  if SepAt = 0 then
  begin
    if ABody = AllSlots then
      AError:= MakeError(ABodyCol, '"*" needs a count: write G[*/N]')
    else if TryParseNumber(ABody, ATerm.Slot) then
    begin
      ATerm.Kind:= gtkSlot;
      Result:= True;
    end
    else
      AError:= MakeError(ABodyCol, 'expected a decimal slot number, "*/N" or "count" inside G[..]');
    Exit;
  end;
  SlotText := Copy(ABody, 1, SepAt - 1);
  CountText:= Copy(ABody, SepAt + 1, MaxInt);
  if SlotText = AllSlots then
    ATerm.Kind:= gtkAllOfCount
  else if TryParseNumber(SlotText, ATerm.Slot) then
    ATerm.Kind:= gtkSlotOfCount
  else
  begin
    AError:= MakeError(ABodyCol, 'expected a decimal slot number or "*" before "/"');
    Exit;
  end;
  if not TryParseNumber(CountText, ATerm.Count) then
  begin
    AError:= MakeError(ABodyCol + SepAt, 'expected a decimal count after "/"');
    Exit;
  end;
  Result:= True;
end;

function ParseGlyphExpr(const AText: string; out AExpr: TGlyphExpr): TArray<TGlyphExprError>;
var
  P      : Integer;
  L      : Integer;
  CloseAt: Integer;
  BodyAt : Integer;
  Alt    : TGlyphAlternative;
  Term   : TGlyphTerm;
  Err    : TGlyphExprError;

  procedure SkipBlanks;
  begin
    while (P <= L) and CharInSet(AText[P], [' ', #9]) do
      Inc(P);
  end;

begin
  Result:= nil;
  AExpr := Default(TGlyphExpr);
  AExpr.Text:= AText;
  L:= Length(AText);
  P:= 1;
  SkipBlanks;
  if P > L then Exit(OnlyError(1, 'empty G-expression'));
  repeat
    Alt:= Default(TGlyphAlternative);
    SkipBlanks;
    Alt.Column:= P;
    while (P <= L) and (AText[P] <> AltSep) do
    begin
      if Copy(AText, P, Length(TermOpen)) <> TermOpen then
        Exit(OnlyError(P, 'expected "G[" to start a term'));
      BodyAt := P + Length(TermOpen);
      CloseAt:= Pos(TermClose, AText, BodyAt);
      if CloseAt = 0 then Exit(OnlyError(P, 'unterminated term: missing "]"'));
      Term:= Default(TGlyphTerm);
      Term.Column:= P;
      if not ParseTermBody(Copy(AText, BodyAt, CloseAt - BodyAt), BodyAt, Term, Err) then
        Exit(OnlyError(Err.Column, Err.Message));
      Alt.Terms:= Alt.Terms + [Term];
      P:= CloseAt + 1;
      SkipBlanks;
    end;
    if Length(Alt.Terms) = 0 then
      Exit(OnlyError(Alt.Column, 'empty alternative: expected a G[..] term before or after the comma'));
    AExpr.Alternatives:= AExpr.Alternatives + [Alt];
    if P > L then Break;
    Inc(P); { past the comma; an alternative must follow it }
  until False;
end;

function ValidateGlyphExpr(const AExpr: TGlyphExpr): TArray<TGlyphExprError>;
var
  Alt         : TGlyphAlternative;
  Term        : TGlyphTerm;
  AltN        : Integer;
  Limit       : Integer;
  HasDenom    : Boolean;
  HasCountTerm: Boolean;
  SeenBare    : Boolean;
  SeenN       : TArray<Integer>;
  N           : Integer;
  Duplicate   : Boolean;
begin
  Result  := nil;
  SeenBare:= False;
  SeenN   := nil;
  for Alt in AExpr.Alternatives do
  begin
    AltN        := 0;
    HasDenom    := False;
    HasCountTerm:= False;
    // Pass 1: G[count] placement, bounds below, and the alternative's agreed N.
    for Term in Alt.Terms do
    begin
      if Term.Kind = gtkCount then
      begin
        HasCountTerm:= True;
        if not IsGlyphCountExpr(AExpr) then
          Result:= Result + [MakeError(Term.Column,
            'G[count] must be the whole expression -- it is the number of terms the sibling image link chose, not a slot')];
        Continue;
      end;
      if Term.Kind in [gtkSlotOfCount, gtkAllOfCount] then
      begin
        HasDenom:= True;
        if Term.Count < 1 then
          Result:= Result + [MakeError(Term.Column,
            Format('count %d is out of range: N must be at least 1', [Term.Count]))]
        else if AltN = 0 then
          AltN:= Term.Count
        else if Term.Count <> AltN then
          Result:= Result + [MakeError(Term.Column,
            Format('mixed denominators in one alternative (/%d and /%d)', [AltN, Term.Count]))];
      end;
      if (Term.Kind in [gtkSlotOfCount, gtkSlot]) and (Term.Slot < 1) then
        Result:= Result + [MakeError(Term.Column,
          Format('slot %d is out of range: I must be at least 1', [Term.Slot]))];
    end;
    // Pass 2: slots against their bound -- a G[I/N] against its own N, a G[I]
    // against the N pass 1 fixed for the alternative (none -> any N, unchecked).
    for Term in Alt.Terms do
    begin
      if not (Term.Kind in [gtkSlotOfCount, gtkSlot]) then Continue;
      Limit:= if Term.Kind = gtkSlotOfCount then Term.Count else AltN;
      if (Term.Slot >= 1) and (Limit >= 1) and (Term.Slot > Limit) then
        Result:= Result + [MakeError(Term.Column,
          Format('slot %d exceeds its count %d', [Term.Slot, Limit]))];
    end;
    // Selection uniqueness (design 3.2): one alternative per N, and at most one
    // denominator-less alternative. An alternative whose every denominator was
    // already rejected above (HasDenom, AltN = 0) has no N to compare.
    if HasCountTerm or (HasDenom and (AltN = 0)) then Continue;
    if not HasDenom then
    begin
      if SeenBare then
        Result:= Result + [MakeError(Alt.Column,
          'two denominator-less alternatives -- at most one may match any N')];
      SeenBare:= True;
      Continue;
    end;
    Duplicate:= False;
    for N in SeenN do
      if N = AltN then Duplicate:= True;
    if Duplicate then
      Result:= Result + [MakeError(Alt.Column,
        Format('two alternatives for N=%d -- at most one alternative may apply to a given N', [AltN]))]
    else
      SeenN:= SeenN + [AltN];
  end;
end;

function IsGlyphCountExpr(const AExpr: TGlyphExpr): Boolean;
begin
  Result:= (Length(AExpr.Alternatives) = 1) and (Length(AExpr.Alternatives[0].Terms) = 1) and
           (AExpr.Alternatives[0].Terms[0].Kind = gtkCount);
end;

function IsGlyphCountPropName(const AName: string): Boolean;
var
  S   : string;
  Tail: string;
  P   : Integer;
begin
  Result:= False;
  P:= LastDelimiter('.', AName);
  Tail:= if P > 0 then Copy(AName, P + 1, MaxInt) else AName;
  for S in GlyphCountPropNames do
    if SameText(S, Tail) then Exit(True);
end;

end.
