unit ConvRules.ConvertEncoding;

{ Pure decisions behind the Convert tab's PRE-RUN encoding question (owner ruling 2026-10-26).
  The level a unit is written at is the level of its existing .pas (inferred, DetectTextLevel).
  When a runnable book's rule text holds a character that level cannot hold, converting would
  raise the source file's level -- so the user is asked BEFORE the run, with every place listed
  (book, line:col, U+XXXX, the rule line, the unit), and chooses: raise the unit's .pas (the
  engine's --raise-encoding: UTF-8 with BOM), change the rules (the run does not start), or
  cancel. A lone surrogate fits UTF-16 only, which the engine cannot raise a source to: the rule
  must be fixed, and the question says so.
  The .dfm is not checked here: the engine #-escapes a .dfm string losslessly, and anything it
  still cannot write is refused after the run (ConvRules.ConvertRerun asks then). Comment lines
  (// first) are never written and never asked about. ENC-N1 (2026-10-26): a #convert block's own
  lines (header, #link, #default, #ignore, #remove, #migrate, #apply, #tag, #warn, #check-ref)
  count only for a unit the block applies to (FromTypeApplier); every other line of a book counts
  for every unit.
  No UI and no engine calls; ConvRulesModelTests.dpr (EncodingPreRunTests.inc) pins every rule. }

interface

uses
  ConvRules.TextEncoding
  , ConvRules.Inheritance  // dl:unit ConvRules.Inheritance accepted -- FromTypeApplier reads a unit's evidence the way C8 does: TDfmTextReader, TUnitInheritance, ListDfmInstances, DFM_EXT and BINARY_DFM_SIGNATURE travel together
  ;

const
  /// <summary>At most this many places are listed in one question; the rest are counted.</summary>
  PRE_RUN_PLACES_SHOWN = 20;
  /// <summary>Longest slice of a rule line shown for one place (RuleExcerpt; a cut side adds '...').</summary>
  PRE_RUN_RULE_CHARS = 80;

type
  /// <summary>One character of a book's rule text that a target unit's .pas cannot hold.</summary>
  TEncodingPlace = record
    /// <summary>The book's path, as the job lists it.</summary>
    Book     : string;
    /// <summary>1-based line in the book.</summary>
    Line     : Integer;
    /// <summary>1-based column (UTF-16 units: a surrogate pair is 2 columns).</summary>
    Col      : Integer;
    /// <summary>Unicode code point (a pair is one code point; a lone surrogate its own unit).</summary>
    Code     : Integer;
    /// <summary>The trimmed book line holding it, windowed around Col when longer than PRE_RUN_RULE_CHARS (RuleExcerpt).</summary>
    Rule     : string;
    /// <summary>The target unit's .pas, as the job lists it.</summary>
    UnitPas  : string;
    /// <summary>The level the .pas is at now (what the run would write it at).</summary>
    UnitLevel: TTextLevel;
    /// <summary>The lowest level that holds the character: tlAscii8, tlUtf8, or tlUtf16Bom for a lone surrogate.</summary>
    Needs    : TTextLevel;
  end;

  /// <summary>Returns a book's decoded text; may raise when the book cannot be read.</summary>
  TBookTextFn = reference to function(const APath: string): string;
  /// <summary>The current level of a unit's .pas; False = the file is not there (not asked about).</summary>
  TUnitLevelFn = reference to function(const APas: string; out ALevel: TTextLevel): Boolean;
  /// <summary>The user's answer for one unit: mrYes (raise), mrNo (change the rules) or mrCancel
  /// (System.UITypes); anything else counts as mrNo.</summary>
  TPreRunAskFn = reference to function(const AUnitPas, AQuestion: string; ACanRaise: Boolean): Integer;

  /// <summary>Whether a #convert block whose From type is AFromType (bare or qualified) applies to one unit.</summary>
  TFromTypeAppliesFn = reference to function(const AFromType: string): Boolean;
  /// <summary>The From-type test for one unit's .pas (FromTypeApplier); nil = every block applies to it.</summary>
  TUnitApplierFn = reference to function(const AUnitPas: string): TFromTypeAppliesFn;
  /// <summary>What the pre-run questions decided.</summary>
  TPreRunPlan = record
    /// <summary>The .pas files to pass as --raise-encoding (each Yes), in question order.</summary>
    RaiseFiles : TArray<string>;
    /// <summary>The run must not start (a No or a Cancel).</summary>
    Stop       : Boolean;
    /// <summary>The stop was a No: the user changes the rules (Places says where).</summary>
    ChangeRules: Boolean;
    /// <summary>The places of the unit whose answer stopped the run; [] otherwise.</summary>
    Places     : TArray<TEncodingPlace>;
    /// <summary>The places the Convert tab keeps as note rows (PlaceNoteText): every place of each unit
    /// answered Yes, plus the stopping unit's places after a No; [] after a Cancel (nothing is kept).</summary>
    Notes      : TArray<TEncodingPlace>;
  end;

/// <summary>PURE: a book's text with every comment line (trimmed text starting with //) blanked;
/// line numbers do not move. Lines are split like BookLines (CRLF, LF, lone CR) and the result is
/// joined with LF, so a book's breaks are normalised to LF (a trailing break is not kept).</summary>
/// <param name="ABookText">The decoded book text.</param>
/// <returns>The text the engine may write from.</returns>
function RuleLinesOnly(const ABookText: string): string;

/// <summary>PURE: 'U+XXXX' plus the character in quotes; a lone surrogate (U+D800..U+DFFF without
/// its pair) is named instead of shown.</summary>
/// <param name="ACode">A code point as TEncodingPlace.Code holds it.</param>
/// <returns>The label, for example U+0414 'D' (with the real character).</returns>
function CharLabel(ACode: Integer): string;

/// <summary>PURE: every place, in unit order, then book order, then line and column, where a
/// book's rule text (RuleLinesOnly) holds a character the unit's .pas cannot hold at its level.</summary>
/// <param name="ABooks">The runnable books, application order.</param>
/// <param name="AUnits">The job's units (.pas).</param>
/// <param name="ABookText">Reads a book; called once per book.</param>
/// <param name="AUnitLevel">The level of a unit's .pas; a unit it returns False for is skipped.</param>
/// <returns>Every occurrence, not one per distinct character; [] when everything fits. Every block counts for every unit: EncodingPlacesFor narrows.</returns>
/// <exception cref="Exception">Whatever ABookText raises propagates.</exception>
function EncodingPlaces(const ABooks, AUnits: TArray<string>; const ABookText: TBookTextFn;  // dl:ok unused-public-symbol@4b8e, doc-drift@4b8e -- REVIEWED 2026-10-26 the no-narrowing form the model tests pin (prerun.*); the Convert tab calls EncodingPlacesFor. The exception is ABookText's, propagated (documented on purpose)
  const AUnitLevel: TUnitLevelFn): TArray<TEncodingPlace>;

/// <summary>PURE (ENC-N3): the rule text shown for a place: the trimmed line, or when it is longer
/// than PRE_RUN_RULE_CHARS a window of that many characters centred on ACol (clamped to the line),
/// with '...' on each side that was cut.</summary>
/// <param name="ALine">The book line, untrimmed (ACol counts from its first character).</param>
/// <param name="ACol">1-based column of the offending character in ALine.</param>
/// <returns>The excerpt; it always holds the character at ACol. A window edge never splits a
/// surrogate pair (the half is left out).</returns>
function RuleExcerpt(const ALine: string; ACol: Integer): string;

/// <summary>PURE (ENC-N1): ABookText with the block-local lines (header, #link, #default, #ignore,
/// #remove, #migrate, #apply, #tag, #warn, #check-ref) of every #convert block whose From type
/// AApplies rejects blanked; line breaks are kept, so line numbers do not move.</summary>
/// <param name="ABookText">A book's text (usually RuleLinesOnly'd).</param>
/// <param name="AApplies">The unit's test (FromTypeApplier); nil = every block applies.</param>
/// <returns>The text the engine may write into that unit.</returns>
/// <remarks>Lines before the first #convert, unit directives (#use / #unuse / #useswap), #depth,
/// #mapping (another block may #apply it), #note, raw pcre and unknown lines always count. A
/// header naming no From type applies to every unit.</remarks>
function AppliedRuleLines(const ABookText: string; const AApplies: TFromTypeAppliesFn): string;  // dl:ok unused-public-symbol@34c0 -- REVIEWED 2026-10-26 pinned by the model tests (n1.*), which are outside this project's index; EncodingPlacesFor runs the same BlockFromTypes / BlankUnapplied

/// <summary>PURE (ENC-N1): which #convert blocks apply to one unit, from what the unit itself
/// says: a block applies when its bare From type is the class of any block header of the unit's
/// text .dfm (ListDfmInstances: object, inherited and inline, at any depth), an identifier of the
/// unit's .pas (a field, a var, a runtime creator TFrom.Create), or the class of one of AInherit's
/// verdicts (an inherited instance or an E2b code use the .dfm does not re-open).</summary>
/// <param name="AUnitPas">The unit's .pas; its .dfm is ChangeFileExt(AUnitPas, DFM_EXT).</param>
/// <param name="AReader">The file system (DiskTextReader in the editor, a fake in the tests);
/// called once for the .pas and once for the .dfm, here, not by the answer.</param>
/// <param name="AInherit">The unit's C8 analysis; Default(TUnitInheritance) when there is none.</param>
/// <returns>The test; names compare case-insensitively on bare names; a From type '' always
/// applies.</returns>
/// <remarks>Decision 2026-10-26 (ENC-N1): a unit WITHOUT a .dfm (drMissing) gets the blocks its
/// .pas or its C8 analysis names -- the engine's runtime-creator retype and code-use edits reach a
/// .pas with no .dfm; with no .dfm instance and no such name no block can write into it. When the
/// unit cannot be judged -- the .pas cannot be read, the .dfm exists but cannot be read, or the
/// .dfm is binary (BINARY_DFM_SIGNATURE) -- every block applies (the question may be needless,
/// never missing). Over-inclusion is the safe side throughout: a .pas comment or string naming
/// the type counts too. The ancestors AncestorChain offers are units of the job in their own
/// right and are judged by their own files.</remarks>
function FromTypeApplier(const AUnitPas: string; const AReader: TDfmTextReader; const AInherit: TUnitInheritance): TFromTypeAppliesFn;

/// <summary>PURE: EncodingPlaces, with each unit's places narrowed to the lines AppliedRuleLines
/// keeps for it.</summary>
/// <param name="ABooks">The runnable books, application order.</param>
/// <param name="AUnits">The job's units (.pas).</param>
/// <param name="ABookText">Reads a book; called once per book.</param>
/// <param name="AUnitLevel">The level of a unit's .pas; a unit it returns False for is skipped.</param>
/// <param name="AApplier">The test per unit (called once per unit with a level); nil, or a nil
/// answer for a unit, = every block applies (EncodingPlaces).</param>
/// <returns>Every occurrence, unit order, then book order, then line and column; [] when everything fits.</returns>
/// <exception cref="Exception">Whatever ABookText raises propagates.</exception>
function EncodingPlacesFor(const ABooks, AUnits: TArray<string>; const ABookText: TBookTextFn;  // dl:ok doc-drift@e7ae -- REVIEWED 2026-10-26 the exception is ABookText's, propagated (documented on purpose)
  const AUnitLevel: TUnitLevelFn; const AApplier: TUnitApplierFn): TArray<TEncodingPlace>;
/// <summary>PURE: the places of one unit (SameText on UnitPas), in order.</summary>
/// <param name="APlaces">As EncodingPlaces returns them.</param>
/// <param name="AUnitPas">The unit.</param>
/// <returns>Its places; [] when it has none.</returns>
function PlacesOfUnit(const APlaces: TArray<TEncodingPlace>; const AUnitPas: string): TArray<TEncodingPlace>;

/// <summary>PURE: whether raising the unit's .pas would hold all of APlaces.</summary>
/// <param name="APlaces">One unit's places.</param>
/// <param name="AGuard">The engine reports convert_encoding_guard (--raise-encoding).</param>
/// <returns>True when AGuard and no place needs more than UTF-8 (the engine raises to UTF-8 with BOM only).</returns>
function CanRaisePlaces(const APlaces: TArray<TEncodingPlace>; AGuard: Boolean): Boolean;

/// <summary>PURE: the question for one unit: its level, every place (book line:col, CharLabel,
/// rule) up to PRE_RUN_PLACES_SHOWN, and the choices.</summary>
/// <param name="AUnitPas">The unit.</param>
/// <param name="APlaces">Its places (PlacesOfUnit).</param>
/// <param name="ACanRaise">CanRaisePlaces: False drops the Yes choice and names the reason.</param>
/// <returns>The dialog text.</returns>
function PreRunQuestion(const AUnitPas: string; const APlaces: TArray<TEncodingPlace>; ACanRaise: Boolean): string;

/// <summary>PURE: the text of one place's note row on the Convert tab.</summary>
/// <param name="APlace">One place.</param>
/// <returns>'encoding: book line:col U+XXXX unit does not fit level (rule)'-style text, rule appended.</returns>
function PlaceNoteText(const APlace: TEncodingPlace): string;

/// <summary>PURE: asks once per unit that has places, in order, until a No or Cancel.</summary>
/// <param name="APlaces">As EncodingPlaces returns them.</param>
/// <param name="AGuard">The engine reports convert_encoding_guard.</param>
/// <param name="AAsk">The dialog; nil = nobody to ask: the run stops (Cancel) when there are places.</param>
/// <returns>Yes (only where CanRaisePlaces) adds the unit's .pas to RaiseFiles; No (or a Yes that
/// cannot raise) stops with ChangeRules; Cancel stops. No place = no question, an empty plan.
/// Notes: every place of each Yes unit (the run goes on, the places stay visible), the stopping
/// unit's places after a No; a Cancel leaves Notes empty.</returns>
function PreRunPlan(const APlaces: TArray<TEncodingPlace>; AGuard: Boolean; const AAsk: TPreRunAskFn): TPreRunPlan;

implementation

uses
  System.SysUtils
  , System.Classes  // TStringList: BookLines
  , System.StrUtils  // MatchText
  , System.Character
  , System.UITypes  // mrYes / mrNo / mrCancel: PreRunPlan's answers
  , System.Math  // Max / Min: RuleExcerpt's window
  , System.Generics.Collections  // TArray.Sort / BinarySearch: FromTypeApplier's identifiers
  , ConvRules.Model  // TRuleBook.ParseLine: which #convert block a line belongs to
  ;

const
  LAST_ASCII     = 127;
  SURR_FIRST     = $D800;
  SURR_HIGH_LAST = $DBFF;
  SURR_LOW_FIRST = $DC00;
  SURR_LAST      = $DFFF;
  COMMENT_LEAD   = '//';
  PLACE_FMT      = '  %s %d:%d  %s  in: %s';
  NOTE_FMT       = 'encoding: %s %d:%d %s does not fit %s (%s) -- rule: %s';
  MORE_FMT       = '  ... and %d more';
  HEAD_FMT       = '%s is %s, but the rule books would write %d character(s) it cannot hold -- converting would raise the file''s encoding:';
  CHOICE_RAISE   = 'Yes = raise %s to UTF-8 with BOM, then convert.';
  CHOICE_RULES   = 'No = do not convert: change the rule text (down-convert or escape it), then Convert again.';
  CHOICE_CANCEL  = 'Cancel = cancel the whole run.';
  NO_RAISE_LONE  = 'A lone surrogate (U+D800..U+DFFF without its pair) fits UTF-16 only, and the engine raises a source to UTF-8 with BOM only: the rule must be fixed.';
  NO_RAISE_GUARD = 'This engine cannot raise a source''s encoding (no convert_encoding_guard): the rule must be fixed.';

function IsSurrogateCode(ACode: Integer): Boolean;
begin
  Result:= (ACode >= SURR_FIRST) and (ACode <= SURR_LAST);
end;

function BookLines(const ABookText: string): TArray<string>;
var
  LList: TStringList;
begin
  LList:= TStringList.Create;
  try
    LList.Text:= ABookText;
    Result:= LList.ToStringArray;
  finally
    LList.Free;
  end;
end;

function RuleLinesOnly(const ABookText: string): string;
var
  LLines: TArray<string>;
begin
  // Split like the model (BookLines: CRLF, LF and a lone CR); the result is joined with LF.
  LLines:= BookLines(ABookText);
  for var I: Integer:= 0 to High(LLines) do
    if TrimLeft(LLines[I]).StartsWith(COMMENT_LEAD) then
      LLines[I]:= '';
  Result:= string.Join(#10, LLines);
end;

function CharLabel(ACode: Integer): string;
begin
  Result:= Format('U+%.4X', [ACode]);
  if IsSurrogateCode(ACode) then
    Result:= Result + ' (a lone surrogate)'
  else
    Result:= Result + ' ''' + Char.ConvertFromUtf32(ACode) + '''';
end;

const
  // The kinds that belong to their #convert block (the engine applies them only to that block's
  // instances). Every other kind -- a unit directive, #depth, #mapping (another block may #apply
  // it), #note, a raw pcre line, an unknown line -- always counts, inside a block or not.
  BLOCK_LOCAL_KINDS = [rnkConvert, rnkLink, rnkDefault, rnkIgnore, rnkRemove, rnkMigrate, rnkApply,
    rnkTag, rnkWarn, rnkCheckRef];
  ELLIPSIS          = '...';
  RULE_HALF_WINDOW  = PRE_RUN_RULE_CHARS div 2;

function IsHighSurrogateChar(AChar: Char): Boolean;
begin
  Result:= (Ord(AChar) >= SURR_FIRST) and (Ord(AChar) <= SURR_HIGH_LAST);
end;

function IsLowSurrogateChar(AChar: Char): Boolean;
begin
  Result:= (Ord(AChar) >= SURR_LOW_FIRST) and (Ord(AChar) <= SURR_LAST);
end;

function RuleExcerpt(const ALine: string; ACol: Integer): string;
var
  LText              : string;
  LPos, LFirst, LLast: Integer;
begin
  LText:= Trim(ALine);
  if Length(LText) <= PRE_RUN_RULE_CHARS then
    Exit(LText);
  LPos  := ACol - (Length(ALine) - Length(TrimLeft(ALine)));
  LFirst:= Max(1, Min(LPos - RULE_HALF_WINDOW, Length(LText) - PRE_RUN_RULE_CHARS + 1));
  LLast := LFirst + PRE_RUN_RULE_CHARS - 1;
  // never cut a surrogate pair in half at either edge
  if IsLowSurrogateChar(LText[LFirst]) then
    Inc(LFirst);
  if IsHighSurrogateChar(LText[LLast]) then
    Dec(LLast);
  Result:= Copy(LText, LFirst, LLast - LFirst + 1);
  if LFirst > 1 then
    Result:= ELLIPSIS + Result;
  if LLast < Length(LText) then
    Result:= Result + ELLIPSIS;
end;

// Per #10-line of a rule text: the bare From type of the #convert block the line belongs to when
// its kind is block-local, else '' (the line always counts: before the first #convert, a kind
// that is not block-local, or a header naming no From type).
function BlockFromTypes(const ALines: TArray<string>): TArray<string>;
var
  LBook   : TRuleBook;
  LNode   : TRuleNode;
  LFrom   : string;
  LInBlock: Boolean;
begin
  SetLength(Result, Length(ALines));
  LFrom   := '';
  LInBlock:= False;
  LBook   := TRuleBook.Create;
  try
    for var N: Integer:= 0 to High(ALines) do
    begin
      LNode:= LBook.ParseLine(ALines[N].TrimRight([#13]));
      try
        if LNode.Kind = rnkConvert then
        begin
          LInBlock:= True;
          LFrom   := BareType(Trim(LNode.FromType));
        end;
        Result[N]:= if LInBlock and (LNode.Kind in BLOCK_LOCAL_KINDS) then LFrom else '';
      finally
        LNode.Free;
      end; // try
    end;
  finally
    LBook.Free;
  end; // try
end;

// ALines with every line whose block (AFroms) does not apply blanked; a #13 stays, so the lines
// join back to the same line numbers.
function BlankUnapplied(const ALines, AFroms: TArray<string>; const AApplies: TFromTypeAppliesFn): TArray<string>;
begin
  Result:= Copy(ALines);
  for var N: Integer:= 0 to High(Result) do
    if (AFroms[N] <> '') and not AApplies(AFroms[N]) then
      Result[N]:= if Result[N].EndsWith(#13) then #13 else '';
end;

function AppliedRuleLines(const ABookText: string; const AApplies: TFromTypeAppliesFn): string;
var
  LLines: TArray<string>;
begin
  if not Assigned(AApplies) then
    Exit(ABookText);
  LLines:= ABookText.Split([#10]);
  Result:= string.Join(#10, BlankUnapplied(LLines, BlockFromTypes(LLines), AApplies));
end;

function AllApply: TFromTypeAppliesFn;
begin
  Result:=
    function(const AFromType: string): Boolean
    begin
      Result:= True;
    end;
end;

// Every identifier of a Pascal text, upper-cased and sorted (duplicates kept): a letter or '_'
// followed by letters, digits or '_'. Comments and strings are not told apart (over-inclusion
// only makes a block count).
function SortedIdentifiers(const AText: string): TArray<string>;
var
  I, LStart: Integer;
begin
  Result:= nil;
  I     := 1;
  while I <= Length(AText) do
  begin
    if AText[I].IsLetter or (AText[I] = '_') then
    begin
      LStart:= I;
      while (I <= Length(AText)) and (AText[I].IsLetterOrDigit or (AText[I] = '_')) do
        Inc(I);
      Result:= Result + [UpperCase(Copy(AText, LStart, I - LStart))];
    end
    else
      Inc(I);
  end;
  TArray.Sort<string>(Result);
end;

function FromTypeApplier(const AUnitPas: string; const AReader: TDfmTextReader; const AInherit: TUnitInheritance): TFromTypeAppliesFn;
var
  LPas, LDfm: string;
  LTypes    : TArray<string>;
  LIdents   : TArray<string>;
begin
  if AReader(AUnitPas, LPas) <> drRead then
    Exit(AllApply);
  LTypes:= nil;
  case AReader(ChangeFileExt(AUnitPas, DFM_EXT), LDfm) of
    drUnreadable:
      Exit(AllApply);
    drRead:
      begin
        if LDfm.StartsWith(BINARY_DFM_SIGNATURE) then
          Exit(AllApply);
        for var LInst: TDfmInstance in ListDfmInstances(LDfm) do
          LTypes:= LTypes + [BareType(LInst.TypeName)];
      end;
    drMissing:
      ; // no .dfm: only the .pas and the C8 analysis say what applies
  end;
  for var LVerdict: TInstanceVerdict in AInherit.Verdicts do
    LTypes:= LTypes + [BareType(LVerdict.Instance.TypeName)];
  LIdents:= SortedIdentifiers(LPas);
  Result:=
    function(const AFromType: string): Boolean
    var
      LBare : string;
      LFound: Integer;
    begin
      LBare := BareType(Trim(AFromType));
      Result:= (LBare = '') or MatchText(LBare, LTypes)
        or TArray.BinarySearch<string>(LIdents, UpperCase(LBare), LFound);
    end;
end;

// The places of one book's rule lines (comments and unapplied blocks already blanked) for one
// unit: every occurrence, line and column order.
function BookPlaces(const ABook: string; const ALines: TArray<string>; const AUnitPas: string; ALevel: TTextLevel): TArray<TEncodingPlace>;
var
  LLine : string;
  LPlace: TEncodingPlace;
  LCode, LWidth, I: Integer;
begin
  Result:= nil;
  for var N: Integer:= 0 to High(ALines) do
  begin
    LLine:= ALines[N];
    I:= 1;
    while I <= Length(LLine) do
    begin
      LCode := Ord(LLine[I]);
      LWidth:= 1;
      if IsHighSurrogateChar(LLine[I]) and (I < Length(LLine)) and IsLowSurrogateChar(LLine[I + 1]) then
      begin
        LCode := Char.ConvertToUtf32(LLine[I], LLine[I + 1]);
        LWidth:= 2;
      end;
      if (LCode > LAST_ASCII) and not RoundTrips(Copy(LLine, I, LWidth), ALevel) then
      begin
        LPlace          := Default(TEncodingPlace);
        LPlace.Book     := ABook;
        LPlace.Line     := N + 1;
        LPlace.Col      := I;
        LPlace.Code     := LCode;
        LPlace.Rule     := RuleExcerpt(LLine, I);
        LPlace.UnitPas  := AUnitPas;
        LPlace.UnitLevel:= ALevel;
        LPlace.Needs    := NeededLevel(Copy(LLine, I, LWidth));
        Result:= Result + [LPlace];
      end;
      Inc(I, LWidth);
    end;
  end;
end;

function EncodingPlacesFor(const ABooks, AUnits: TArray<string>; const ABookText: TBookTextFn;
  const AUnitLevel: TUnitLevelFn; const AApplier: TUnitApplierFn): TArray<TEncodingPlace>;
var
  LLines, LFroms: TArray<TArray<string>>;
  LLevel        : TTextLevel;
  LApplies      : TFromTypeAppliesFn;
begin
  Result:= nil;
  SetLength(LLines, Length(ABooks));
  SetLength(LFroms, Length(ABooks));
  for var B: Integer:= 0 to High(ABooks) do
  begin
    LLines[B]:= BookLines(RuleLinesOnly(string.Join(#10, BookLines(ABookText(ABooks[B])))));
    if Assigned(AApplier) then
      LFroms[B]:= BlockFromTypes(LLines[B]);
  end;
  for var LUnit: string in AUnits do
    if AUnitLevel(LUnit, LLevel) then
    begin
      LApplies:= nil;
      if Assigned(AApplier) then
        LApplies:= AApplier(LUnit);
      for var B: Integer:= 0 to High(ABooks) do
        if Assigned(LApplies) then
          Result:= Result + BookPlaces(ABooks[B], BlankUnapplied(LLines[B], LFroms[B], LApplies), LUnit, LLevel)
        else
          Result:= Result + BookPlaces(ABooks[B], LLines[B], LUnit, LLevel);
    end;
end;

function EncodingPlaces(const ABooks, AUnits: TArray<string>; const ABookText: TBookTextFn;
  const AUnitLevel: TUnitLevelFn): TArray<TEncodingPlace>;
begin
  Result:= EncodingPlacesFor(ABooks, AUnits, ABookText, AUnitLevel, nil);
end;

function PlacesOfUnit(const APlaces: TArray<TEncodingPlace>; const AUnitPas: string): TArray<TEncodingPlace>;
begin
  Result:= nil;
  for var LPlace: TEncodingPlace in APlaces do
    if SameText(LPlace.UnitPas, AUnitPas) then
      Result:= Result + [LPlace];
end;

function CanRaisePlaces(const APlaces: TArray<TEncodingPlace>; AGuard: Boolean): Boolean;
begin
  Result:= AGuard;
  for var LPlace: TEncodingPlace in APlaces do
    if LevelRank(LPlace.Needs) > LevelRank(tlUtf8) then
      Exit(False);
end;

function PreRunQuestion(const AUnitPas: string; const APlaces: TArray<TEncodingPlace>; ACanRaise: Boolean): string;
var
  LName : string;
  LLines: TArray<string>;
  LLone : Boolean;
  LLevel: TTextLevel;
begin
  LName := ExtractFileName(AUnitPas);
  LLevel:= tlAscii7;
  if Length(APlaces) > 0 then
    LLevel:= APlaces[0].UnitLevel;
  LLines:= [Format(HEAD_FMT, [LName, LevelName(LLevel), Length(APlaces)])];
  LLone := False;
  for var I: Integer:= 0 to High(APlaces) do
  begin
    LLone:= LLone or IsSurrogateCode(APlaces[I].Code);
    if I < PRE_RUN_PLACES_SHOWN then
      LLines:= LLines + [Format(PLACE_FMT, [ExtractFileName(APlaces[I].Book), APlaces[I].Line, APlaces[I].Col,
        CharLabel(APlaces[I].Code), APlaces[I].Rule])];
  end;
  if Length(APlaces) > PRE_RUN_PLACES_SHOWN then
    LLines:= LLines + [Format(MORE_FMT, [Length(APlaces) - PRE_RUN_PLACES_SHOWN])];
  LLines:= LLines + [''];
  if ACanRaise then
    LLines:= LLines + [Format(CHOICE_RAISE, [LName])]
  else
    LLines:= LLines + [if LLone then NO_RAISE_LONE else NO_RAISE_GUARD];
  LLines:= LLines + [CHOICE_RULES, CHOICE_CANCEL];
  Result:= string.Join(sLineBreak, LLines);
end;

function PlaceNoteText(const APlace: TEncodingPlace): string;
begin
  Result:= Format(NOTE_FMT, [ExtractFileName(APlace.Book), APlace.Line, APlace.Col, CharLabel(APlace.Code),
    ExtractFileName(APlace.UnitPas), LevelName(APlace.UnitLevel), APlace.Rule]);
end;

function PreRunPlan(const APlaces: TArray<TEncodingPlace>; AGuard: Boolean; const AAsk: TPreRunAskFn): TPreRunPlan;
var
  LSeen  : TArray<string>;
  LOwn   : TArray<TEncodingPlace>;
  LCan   : Boolean;
  LAnswer: Integer;
begin
  Result:= Default(TPreRunPlan);
  LSeen := nil;
  for var LPlace: TEncodingPlace in APlaces do
  begin
    if MatchText(LPlace.UnitPas, LSeen) then
      Continue;
    LSeen:= LSeen + [LPlace.UnitPas];
    LOwn := PlacesOfUnit(APlaces, LPlace.UnitPas);
    LCan := CanRaisePlaces(LOwn, AGuard);
    LAnswer:= if Assigned(AAsk) then AAsk(LPlace.UnitPas, PreRunQuestion(LPlace.UnitPas, LOwn, LCan), LCan) else mrCancel;
    if (LAnswer = mrYes) and LCan then
    begin
      Result.RaiseFiles:= Result.RaiseFiles + [LPlace.UnitPas];
      Result.Notes     := Result.Notes + LOwn;
      Continue;
    end;
    Result.Stop       := True;
    Result.ChangeRules:= LAnswer <> mrCancel;
    Result.Places     := LOwn;
    if LAnswer = mrCancel then
      Result.Notes:= nil
    else
      Result.Notes:= Result.Notes + LOwn;
    Exit;
  end;
end;

end.
