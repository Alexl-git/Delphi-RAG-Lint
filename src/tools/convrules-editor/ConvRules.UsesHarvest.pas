unit ConvRules.UsesHarvest;

{ Pure harvest model behind the Unit Rules tab's Add source / drop / paste
  (spec docs\superpowers\specs\2026-09-28-unit-rules-harvest-and-missing-design.md).
  Everything here is pure except HarvestFiles, the one routine that reads the
  disk. The VCL form only renders what these return; ConvRulesModelTests.dpr
  pins every rule, because the form unit is outside its closure. }

interface

uses
  System.SysUtils
  ;

type
  /// <summary>One used unit found in a source.</summary>
  THarvestedUnit = record
    /// <summary>The unit name as written; dotted names are kept whole.</summary>
    UnitName: string;
    /// <summary>'interface' or 'implementation' for a .pas; '' for pasted text
    /// and for a .dpr's own uses clause.</summary>
    Section : string;
    /// <summary>The unit or project that uses it; PASTED_SOURCE for text.</summary>
    UsedBy  : string;
  end;

  /// <summary>One entry of a .dpr uses clause.</summary>
  TDprMember = record
    /// <summary>The unit name as written.</summary>
    UnitName: string;
    /// <summary>Absolute path from the entry's `in '...'` part; '' for a plain
    /// entry such as `Vcl.Forms`.</summary>
    FilePath: string;
  end;

const
  /// <summary>UsedBy value for units that came from dropped or pasted text.</summary>
  PASTED_SOURCE = '(pasted)';

/// <summary>Used units named by a piece of dropped or pasted text.</summary>
/// <param name="AText">Any text. When it contains the keyword `uses` it is read
/// as Delphi source (comments, strings and `in '...'` handled by
/// ScanUsesClausesSectioned); otherwise it is split on commas, semicolons and
/// whitespace and only identifier-shaped tokens (dotted allowed) are kept.</param>
/// <returns>First occurrence wins, case-insensitively; Section is always '' and
/// UsedBy is PASTED_SOURCE.</returns>
function HarvestText(const AText: string): TArray<THarvestedUnit>;

/// <summary>The entries of a .dpr's uses clause, with `in` paths made absolute.</summary>
/// <param name="ADprText">The whole .dpr text.</param>
/// <param name="ADprDir">The .dpr's folder; relative `in` paths resolve against it.</param>
/// <returns>Source order, de-duplicated case-insensitively.</returns>
function ReadDprMembers(const ADprText, ADprDir: string): TArray<TDprMember>;

/// <summary>AExisting followed by the units of AAdded it does not already hold.</summary>
/// <param name="AExisting">The current list; its entries win on a name clash.</param>
/// <param name="AAdded">Units to merge in.</param>
/// <returns>The merged list; comparison is case-insensitive.</returns>
function MergeHarvest(const AExisting, AAdded: TArray<THarvestedUnit>): TArray<THarvestedUnit>;

/// <summary>AUnits without the entry named AName (case-insensitive).</summary>
/// <param name="AUnits">The list.</param>
/// <param name="AName">The unit to drop.</param>
/// <returns>A new array; AUnits is not modified.</returns>
function WithoutUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): TArray<THarvestedUnit>;

/// <summary>Index of AName in AUnits, case-insensitive; -1 when absent.</summary>
/// <param name="AUnits">The list.</param>
/// <param name="AName">The unit name.</param>
/// <returns>The index, or -1.</returns>
function IndexOfUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): Integer;

/// <summary>The Flag column text for a harvested unit.</summary>
/// <param name="AUnit">The harvested unit.</param>
/// <returns>'interface, U1' when a section is known, else just UsedBy.</returns>
function HarvestFlagText(const AUnit: THarvestedUnit): string;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , System.RegularExpressions
  , ConvRules.Usage
  ;

const
  IDENT_RE    = '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$';
  USES_RE     = '(^|[^A-Za-z0-9_.])uses($|[^A-Za-z0-9_])';
  DPR_IN_RE   = '([A-Za-z_][A-Za-z0-9_.]*)\s+in\s+''([^'']+)''';
  NOT_FOUND   = -1;

function MakeUnit(const AName, ASection, AUsedBy: string): THarvestedUnit;
begin
  Result.UnitName:= AName;
  Result.Section := ASection;
  Result.UsedBy  := AUsedBy;
end;

function IndexOfUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(AUnits) do
    if SameText(AUnits[i].UnitName, AName) then
      Exit(i);
  Result:= NOT_FOUND;
end;

function MergeHarvest(const AExisting, AAdded: TArray<THarvestedUnit>): TArray<THarvestedUnit>;
var
  H: THarvestedUnit;
begin
  Result:= AExisting;
  for H in AAdded do
    if IndexOfUnit(Result, H.UnitName) = NOT_FOUND then
      Result:= Result + [H];
end;

function WithoutUnit(const AUnits: TArray<THarvestedUnit>; const AName: string): TArray<THarvestedUnit>;
var
  H: THarvestedUnit;
begin
  Result:= nil;
  for H in AUnits do
    if not SameText(H.UnitName, AName) then
      Result:= Result + [H];
end;

function HarvestFlagText(const AUnit: THarvestedUnit): string;
begin
  if AUnit.Section = '' then
    Result:= AUnit.UsedBy
  else
    Result:= AUnit.Section + ', ' + AUnit.UsedBy;
end;

{ .pas (or .dpr) text -> harvested units; AKeepSection False blanks the section
  for sources where interface/implementation means nothing. }
function HarvestPasText(const AText, AUsedBy: string; AKeepSection: Boolean): TArray<THarvestedUnit>;
var
  R: TUsedUnitRef;
begin
  Result:= nil;
  for R in ScanUsesClausesSectioned(AText) do
    if AKeepSection then
      Result:= Result + [MakeUnit(R.UnitName, R.Section, AUsedBy)]
    else
      Result:= Result + [MakeUnit(R.UnitName, '', AUsedBy)];
end;

function HarvestText(const AText: string): TArray<THarvestedUnit>;
var
  Tok: string;
begin
  if TRegEx.IsMatch(AText, USES_RE, [roIgnoreCase]) then
    Exit(HarvestPasText(AText, PASTED_SOURCE, False));
  Result:= nil;
  for Tok in AText.Split([',', ';', ' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty) do
    if TRegEx.IsMatch(Tok, IDENT_RE) and (IndexOfUnit(Result, Tok) = NOT_FOUND) then
      Result:= Result + [MakeUnit(Tok, '', PASTED_SOURCE)];
end;

function ReadDprMembers(const ADprText, ADprDir: string): TArray<TDprMember>;
var
  Paths: TDictionary<string, string>;
  M    : TMatch;
  R    : TUsedUnitRef;
  D    : TDprMember;
  Rel  : string;
begin
  Result:= nil;
  Paths:= TDictionary<string, string>.Create;
  try
    for M in TRegEx.Matches(ADprText, DPR_IN_RE, [roIgnoreCase]) do
      if not Paths.ContainsKey(UpperCase(M.Groups[1].Value)) then
        Paths.Add(UpperCase(M.Groups[1].Value), M.Groups[2].Value);
    for R in ScanUsesClausesSectioned(ADprText) do
    begin
      D.UnitName:= R.UnitName;
      D.FilePath:= '';
      if Paths.TryGetValue(UpperCase(R.UnitName), Rel) then
        D.FilePath:= TPath.GetFullPath(TPath.Combine(ADprDir, Rel));
      Result:= Result + [D];
    end;
  finally
    Paths.Free;
  end;
end;

end.
