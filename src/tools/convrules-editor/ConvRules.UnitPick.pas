unit ConvRules.UnitPick;

{ Pure model behind the unit picker (ConvRules.UnitPicker.pas): the two-field
  filter, the library list a platform selects, and the "not on this platform"
  note. No UI, no engine, no I/O -- the modal form only renders what these
  return, so every rule it applies is pinned by ConvRulesModelTests.dpr, whose
  closure the VCL form unit is outside of. }

interface

uses
  System.SysUtils
  , ConvRules.Platform
  ;

type
  /// <summary>How the picker's second (search) field is read.</summary>
  /// <remarks>usmWildcard is a whole-name, file-mask style match ('cx*');
  /// usmRegex is an unanchored, case-insensitive regular expression.</remarks>
  TUnitSearchMode = (usmWildcard, usmRegex);

  /// <summary>Both picker filters at once. A unit is shown only when it passes
  /// BOTH; an empty field passes everything.</summary>
  TUnitFilter = record
    /// <summary>The name edit's text: case-insensitive substring.</summary>
    NameText: string;
    /// <summary>The search field's text, read per Mode.</summary>
    Search  : string;
    /// <summary>How Search is read.</summary>
    Mode    : TUnitSearchMode;
  end;

/// <summary>Whether ASearch can be applied in AMode.</summary>
/// <param name="ASearch">The search field's text; '' is always valid.</param>
/// <param name="AMode">Wildcard or regex.</param>
/// <returns>False for a regex that does not compile or a mask that does not
/// parse; True otherwise.</returns>
function IsValidUnitSearch(const ASearch: string; AMode: TUnitSearchMode): Boolean;

/// <summary>The units of AUnits that pass AFilter, in their original order.</summary>
/// <param name="AUnits">The candidate unit names.</param>
/// <param name="AFilter">Both filters. An invalid Search (see IsValidUnitSearch)
/// is IGNORED rather than emptying the result: a half-typed regex must not
/// blank both lists while the user is still typing it.</param>
/// <returns>The matching subset; never nil-vs-empty sensitive.</returns>
function FilterUnits(const AUnits: TArray<string>; const AFilter: TUnitFilter): TArray<string>;

/// <summary>AFirst and ASecond merged, de-duplicated case-insensitively and
/// sorted case-insensitively. The first spelling met wins.</summary>
/// <param name="AFirst">Units listed first (their spelling is kept).</param>
/// <param name="ASecond">Units merged in.</param>
/// <returns>The sorted union.</returns>
function MergeUnitLists(const AFirst, ASecond: TArray<string>): TArray<string>;

/// <summary>The library units a platform selects: the Win32 list, the Win64
/// list, or for cpBoth their merged union (MergeUnitLists).</summary>
/// <param name="APlatform">The picker side's platform.</param>
/// <param name="AWin32">Units indexed in the Win32 library.</param>
/// <param name="AWin64">Units indexed in the Win64 library.</param>
/// <returns>The list the picker's library column shows.</returns>
function LibraryUnitsFor(APlatform: TConvPlatform; const AWin32, AWin64: TArray<string>): TArray<string>;

/// <summary>The note shown under the lists when the chosen unit exists in only
/// one platform library.</summary>
/// <param name="AUnit">The unit name, echoed as given.</param>
/// <param name="AWin32">Units indexed in the Win32 library.</param>
/// <param name="AWin64">Units indexed in the Win64 library.</param>
/// <returns>'X: not in the Win64 library' / 'X: not in the Win32 library', or
/// '' when the unit is in both libraries or in neither (a project unit, or a
/// name typed by hand -- nothing is known to be missing).</returns>
function PlatformGapNote(const AUnit: string; const AWin32, AWin64: TArray<string>): string;

/// <summary>AChosen with AUnit appended -- the replacement picker's accumulator,
/// fed by a double-click (or Enter) on a list item and by OK.</summary>
/// <param name="AChosen">The units picked so far, in pick order.</param>
/// <param name="AUnit">The unit to add; trimmed first.</param>
/// <param name="AExclude">The OLD unit being replaced ('' for none). A name
/// equal to it (any case) is refused: a unit is never its own replacement, and
/// that is exactly what an old unit landing in the replacement list looks like.</param>
/// <returns>AChosen unchanged when the trimmed name is blank, already present
/// (case-insensitive) or equal to AExclude; otherwise AChosen plus the trimmed
/// name at the end. The first spelling picked is kept.</returns>
function AddPickedUnit(const AChosen: TArray<string>; const AUnit, AExclude: string): TArray<string>;

implementation

uses
  System.Classes
  , System.Masks
  , System.RegularExpressions
  ;

{ One unit against the search field, which the caller has already validated. }
function SearchMatches(const AUnit, ASearch: string; AMode: TUnitSearchMode): Boolean;
begin
  if AMode = usmRegex then
    Result:= TRegEx.IsMatch(AUnit, ASearch, [roIgnoreCase])
  else
    Result:= MatchesMask(AUnit, ASearch);
end;

{ Case-insensitive membership, for the short per-selection lookups only. }
function ContainsText(const AList: TArray<string>; const AUnit: string): Boolean;
var
  U: string;
begin
  Result:= False;
  for U in AList do
    if SameText(U, AUnit) then
      Exit(True);
end;

function IsValidUnitSearch(const ASearch: string; AMode: TUnitSearchMode): Boolean;
begin
  if ASearch = '' then
    Exit(True);
  try
    // The probe subject is irrelevant; compiling / parsing the pattern is the test.
    SearchMatches('X', ASearch, AMode);
    Result:= True;
  except
    on Exception do
      Result:= False;
  end; // try
end;

function FilterUnits(const AUnits: TArray<string>; const AFilter: TUnitFilter): TArray<string>;
var
  UseSearch: Boolean;
  Needle   : string ;
  U        : string ;
begin
  Result   := nil;
  Needle   := UpperCase(AFilter.NameText);
  UseSearch:= (AFilter.Search <> '') and IsValidUnitSearch(AFilter.Search, AFilter.Mode);
  for U in AUnits do
  begin
    if (Needle <> '') and not UpperCase(U).Contains(Needle) then
      Continue;
    if UseSearch and not SearchMatches(U, AFilter.Search, AFilter.Mode) then
      Continue;
    Result:= Result + [U];
  end; // for
end;

function MergeUnitLists(const AFirst, ASecond: TArray<string>): TArray<string>;
var
  SL: TStringList;
  U : string     ;
begin
  SL:= TStringList.Create;
  try
    SL.CaseSensitive:= False;
    SL.Sorted       := True;
    SL.Duplicates   := dupIgnore;
    for U in AFirst do
      SL.Add(U);
    for U in ASecond do
      SL.Add(U);
    Result:= SL.ToStringArray;
  finally
    SL.Free;
  end; // try
end;

function LibraryUnitsFor(APlatform: TConvPlatform; const AWin32, AWin64: TArray<string>): TArray<string>;
begin
  case APlatform of
    cpWin32: Result:= AWin32;
    cpWin64: Result:= AWin64;
    else
      Result:= MergeUnitLists(AWin32, AWin64);
  end;
end;

function PlatformGapNote(const AUnit: string; const AWin32, AWin64: TArray<string>): string;
var
  In32: Boolean;
  In64: Boolean;
begin
  In32:= ContainsText(AWin32, AUnit);
  In64:= ContainsText(AWin64, AUnit);
  if In32 and not In64 then
    Result:= AUnit + ': not in the Win64 library'
  else if In64 and not In32 then
    Result:= AUnit + ': not in the Win32 library'
  else
    Result:= '';
end;

function AddPickedUnit(const AChosen: TArray<string>; const AUnit, AExclude: string): TArray<string>;
var
  U: string;
begin
  Result:= AChosen;
  U:= Trim(AUnit);
  if (U = '') or SameText(U, Trim(AExclude)) or ContainsText(AChosen, U) then
    Exit;
  Result:= Result + [U];
end;

end.
