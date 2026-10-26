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
  (// first) are never written and never asked about; any other line of a book counts, whether
  or not its #convert matches the unit (the editor cannot know before the engine runs).
  No UI and no engine calls; ConvRulesModelTests.dpr (EncodingPreRunTests.inc) pins every rule. }

interface

uses
  ConvRules.TextEncoding;

const
  /// <summary>At most this many places are listed in one question; the rest are counted.</summary>
  PRE_RUN_PLACES_SHOWN = 20;
  /// <summary>Longest rule text shown for one place.</summary>
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
    /// <summary>The trimmed book line holding it (at most PRE_RUN_RULE_CHARS).</summary>
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
  end;

/// <summary>PURE: a book's text with every comment line (trimmed text starting with //) blanked;
/// line breaks are kept, so line numbers do not move.</summary>
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
/// <returns>Every occurrence, not one per distinct character; [] when everything fits.</returns>
/// <exception cref="Exception">Whatever ABookText raises propagates.</exception>
function EncodingPlaces(const ABooks, AUnits: TArray<string>; const ABookText: TBookTextFn;
  const AUnitLevel: TUnitLevelFn): TArray<TEncodingPlace>;

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

/// <summary>PURE: asks once per unit that has places, in order, until a No or Cancel.</summary>
/// <param name="APlaces">As EncodingPlaces returns them.</param>
/// <param name="AGuard">The engine reports convert_encoding_guard.</param>
/// <param name="AAsk">The dialog; nil = nobody to ask: the run stops (Cancel) when there are places.</param>
/// <returns>Yes (only where CanRaisePlaces) adds the unit's .pas to RaiseFiles; No (or a Yes that
/// cannot raise) stops with ChangeRules; Cancel stops. No place = no question, an empty plan.</returns>
function PreRunPlan(const APlaces: TArray<TEncodingPlace>; AGuard: Boolean; const AAsk: TPreRunAskFn): TPreRunPlan;

implementation

uses
  System.SysUtils
  , System.StrUtils  // MatchText
  , System.Character
  , System.UITypes  // mrYes / mrNo / mrCancel: PreRunPlan's answers
  ;

const
  LAST_ASCII     = 127;
  SURR_FIRST     = $D800;
  SURR_HIGH_LAST = $DBFF;
  SURR_LOW_FIRST = $DC00;
  SURR_LAST      = $DFFF;
  COMMENT_LEAD   = '//';
  PLACE_FMT      = '  %s %d:%d  %s  in: %s';
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

function RuleLinesOnly(const ABookText: string): string;
var
  LLines: TArray<string>;
begin
  // Split on #10 only: a #13 stays on its line, so the joined text keeps every break as it was.
  LLines:= ABookText.Split([#10]);
  for var I: Integer:= 0 to High(LLines) do
    if TrimLeft(LLines[I]).StartsWith(COMMENT_LEAD) then
      LLines[I]:= if LLines[I].EndsWith(#13) then #13 else '';
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

// The places of one book's rule text for one unit: every occurrence, line and column order.
function BookPlaces(const ABook, AText, AUnitPas: string; ALevel: TTextLevel): TArray<TEncodingPlace>;
var
  LLines: TArray<string>;
  LLine : string;
  LPlace: TEncodingPlace;
  LCode, LWidth, I: Integer;
begin
  Result:= nil;
  LLines:= RuleLinesOnly(AText).Split([#10]);
  for var N: Integer:= 0 to High(LLines) do
  begin
    LLine:= LLines[N];
    I:= 1;
    while I <= Length(LLine) do
    begin
      LCode := Ord(LLine[I]);
      LWidth:= 1;
      if (LCode >= SURR_FIRST) and (LCode <= SURR_HIGH_LAST) and (I < Length(LLine))
        and (Ord(LLine[I + 1]) >= SURR_LOW_FIRST) and (Ord(LLine[I + 1]) <= SURR_LAST) then
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
        LPlace.Rule     := Copy(Trim(LLine), 1, PRE_RUN_RULE_CHARS);
        LPlace.UnitPas  := AUnitPas;
        LPlace.UnitLevel:= ALevel;
        LPlace.Needs    := NeededLevel(Copy(LLine, I, LWidth));
        Result:= Result + [LPlace];
      end;
      Inc(I, LWidth);
    end;
  end;
end;

function EncodingPlaces(const ABooks, AUnits: TArray<string>; const ABookText: TBookTextFn;
  const AUnitLevel: TUnitLevelFn): TArray<TEncodingPlace>;
var
  LTexts: TArray<string>;
  LLevel: TTextLevel;
begin
  Result:= nil;
  SetLength(LTexts, Length(ABooks));
  for var B: Integer:= 0 to High(ABooks) do
    LTexts[B]:= ABookText(ABooks[B]);
  for var LUnit: string in AUnits do
    if AUnitLevel(LUnit, LLevel) then
      for var B: Integer:= 0 to High(ABooks) do
        Result:= Result + BookPlaces(ABooks[B], LTexts[B], LUnit, LLevel);
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
      Continue;
    end;
    Result.Stop       := True;
    Result.ChangeRules:= LAnswer <> mrCancel;
    Result.Places     := LOwn;
    Exit;
  end;
end;

end.
