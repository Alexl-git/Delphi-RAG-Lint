unit ConvRules.FormTypes;

{ The distinct component TYPES used on one or more .dfm forms, plus the pure
  predicates that decide how each one is presented in the form-types panel.

  WHY A SEPARATE UNIT FROM ConvRules.Usage. Usage answers "which PROPERTIES of a
  chosen class does this form assign" -- it needs a From class and reports property
  names. This unit answers the question that comes BEFORE that one: "what types are
  on this form at all, and which of them are worth writing a rule for". The two
  share ParseBlockHeader (exported by Usage for exactly this reason) so there is one
  DFM object-header parser, not two.

  NOTHING HERE FILTERS THE LIST DOWN TO VISUAL CONTROLS. Owner's ruling 2026-09-04:
  any type on a form may be worth converting -- TStringField -> TFDStringField is a
  real conversion -- so the visual/non-visual distinction is presented as a MARK and
  never as a filter.

  VCL-free and side-effect-free, so every decision here is unit-tested headlessly. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults, System.RegularExpressions;

type
  /// <summary>Whether a form type is a visual control, as far as the index can
  /// tell.</summary>
  /// <remarks>tvkUnknown is NOT a synonym for non-visual: it means the type was
  /// not found in the descendant set the caller supplied (unindexed, or a
  /// project-local type). Rendering it as "not a control" would turn absence of
  /// evidence into evidence of absence, so the panel shows '?'.</remarks>
  TTypeVisualKind = (tvkUnknown, tvkVisual, tvkNonVisual);

  /// <summary>One distinct component type found on the scanned form(s).</summary>
  /// <remarks>ScanDfmTypes fills TypeName and Count only. Visual, Excluded, Ruled
  /// and RuledBy are decoration applied afterwards by the caller, which is what
  /// keeps the harvest independent of the index and of the rule catalog.
  /// Reenabled is the user's per-row override and is deliberately NOT derived:
  /// it must survive an edit to the filter that would otherwise re-exclude the
  /// row.</remarks>
  TFormTypeRow = record
    TypeName : string;
    Count    : Integer;
    Visual   : TTypeVisualKind;
    Excluded : Boolean;
    Ruled    : Boolean;
    RuledBy  : string;
    Reenabled: Boolean;
  end;

  TFormTypeRows = TArray<TFormTypeRow>;

/// <summary>PURE: the distinct component types declared in one .dfm text, with an
/// instance count each, sorted by type name (case-insensitive ascending).</summary>
/// <param name="AText">The whole .dfm as text. A binary .dfm simply yields
/// nothing, as it does everywhere else in this editor.</param>
/// <returns>One row per distinct type; Count is the number of 'object'/'inherited'/
/// 'inline' declarations of it. Only TypeName and Count are set.</returns>
/// <remarks>Name-ascending, not count-descending, on purpose: it groups a family
/// (every TOvc*) together, which is how a conversion is actually chosen. The high
/// counts are noise -- VARINSP.dfm's largest is 388 TLabel.</remarks>
function ScanDfmTypes(const AText: string): TFormTypeRows;

/// <summary>PURE: union of several forms' type rows, summing the counts of a type
/// that appears on more than one.</summary>
/// <param name="AParts">One array per scanned form; empty parts are ignored.</param>
/// <returns>The merged rows, sorted as ScanDfmTypes sorts.</returns>
function MergeFormTypes(const AParts: TArray<TFormTypeRows>): TFormTypeRows;

/// <summary>PURE: True when AUnitName is a standard Delphi VCL or FMX unit.</summary>
/// <param name="AUnitName">A declaring unit name, qualified or not; '' is False.</param>
/// <remarks>Deliberately LITERAL -- only the 'Vcl.' and 'FMX.' namespaces, because
/// that is what the checkbox offering this says. System./Data./Winapi. types such
/// as TIntegerField are RTL but are not "standard Delphi controls", and silently
/// hiding 103 TIntegerField behind a box labelled VCL/FMX would be a surprise.
/// Use a regex condition for those.</remarks>
function IsStandardVclOrFmxUnit(const AUnitName: string): Boolean;

/// <summary>PURE: True when a type should be greyed as excluded by the filter.</summary>
/// <param name="ATypeName">The bare type name, e.g. 'TOvcTable'.</param>
/// <param name="ADeclaringUnit">Its declaring unit, or '' when unresolved.</param>
/// <param name="APatterns">Exclusion regexes; a type is excluded when ANY of them
/// matches (OR), so order is irrelevant. Blank patterns are skipped.</param>
/// <param name="AExcludeStandard">Also exclude anything whose declaring unit
/// satisfies IsStandardVclOrFmxUnit.</param>
/// <param name="AError">'' on success; otherwise the FIRST malformed pattern and
/// its message. A malformed pattern never excludes and never raises.</param>
/// <returns>True when the type is excluded.</returns>
/// <remarks>Matching is case-insensitive and UNANCHORED, so 'Ovc' matches
/// 'TOvcTable' -- anchor with ^ or $ to be strict. A malformed pattern failing
/// OPEN (excluding nothing) is only safe because AError is surfaced in the panel;
/// a silent fail-open here would hide the fact that a condition never ran.</remarks>
function TypeIsExcluded(const ATypeName, ADeclaringUnit: string;
  const APatterns: TArray<string>; AExcludeStandard: Boolean;
  out AError: string): Boolean;

/// <summary>PURE: True when the row is greyed in the panel, for any reason.</summary>
/// <param name="ARow">A decorated row.</param>
/// <remarks>The two reasons -- filtered out, already covered by a rule -- render
/// identically but are tracked separately on the row, because Reenabled must
/// override both without erasing WHY the row was grey.</remarks>
function RowIsGreyed(const ARow: TFormTypeRow): Boolean;

implementation

uses
  System.StrUtils, ConvRules.Usage, ConvRules.BlockFile;

const
  /// The namespaces the standard-controls checkbox covers. See IsStandardVclOrFmxUnit.
  STD_CONTROL_NAMESPACES: array[0..1] of string = ('Vcl.', 'FMX.');

{ Sorts rows by TypeName, case-insensitive ascending, and hands back the array.
  One place so ScanDfmTypes and MergeFormTypes cannot drift apart on ordering. }
function SortedByName(const ARows: TFormTypeRows): TFormTypeRows;
begin
  Result := Copy(ARows, 0, Length(ARows));
  TArray.Sort<TFormTypeRow>(Result, TComparer<TFormTypeRow>.Construct(
    function(const L, R: TFormTypeRow): Integer
    begin
      Result := CompareText(L.TypeName, R.TypeName);
    end));
end;

{ Folds counted type names out of a Counts map into sorted rows. }
function RowsFromCounts(ACounts: TDictionary<string, TFormTypeRow>): TFormTypeRows;
var
  Row: TFormTypeRow;
  i  : Integer;
begin
  SetLength(Result, ACounts.Count);
  i := 0;
  for Row in ACounts.Values do
  begin
    Result[i] := Row;
    Inc(i);
  end;
  Result := SortedByName(Result);
end;

function ScanDfmTypes(const AText: string): TFormTypeRows;
var
  Lines : TArray<TRawLine>;
  Counts: TDictionary<string, TFormTypeRow>;
  i     : Integer;
  Cls   : string;
  Key   : string;
  Row   : TFormTypeRow;
begin
  Counts := TDictionary<string, TFormTypeRow>.Create;
  try
    Lines := SplitRawLines(AText);
    for i := 0 to High(Lines) do
    begin
      // ParseBlockHeader keys off the line's FIRST TOKEN, so a type named inside a
      // quoted value ("Caption = 'object fake: TNotReal'") can never reach here --
      // its first token is the property name. That is why no literal-stripping pass
      // is needed for the header scan, unlike ScanDfmText's terminator search.
      if not ParseBlockHeader(Lines[i].Text, Cls) then Continue;
      if Cls = '' then Continue;

      Key := UpperCase(Cls);
      if Counts.TryGetValue(Key, Row) then
        Inc(Row.Count)
      else
      begin
        Row := Default(TFormTypeRow);
        Row.TypeName := Cls;   // first spelling seen wins
        Row.Count    := 1;
      end;
      Counts.AddOrSetValue(Key, Row);
    end;
    Result := RowsFromCounts(Counts);
  finally
    Counts.Free;
  end;
end;

function MergeFormTypes(const AParts: TArray<TFormTypeRows>): TFormTypeRows;
var
  Counts: TDictionary<string, TFormTypeRow>;
  Part  : TFormTypeRows;
  Src   : TFormTypeRow;
  Row   : TFormTypeRow;
  Key   : string;
begin
  Counts := TDictionary<string, TFormTypeRow>.Create;
  try
    for Part in AParts do
      for Src in Part do
      begin
        if Src.TypeName = '' then Continue;
        Key := UpperCase(Src.TypeName);
        if Counts.TryGetValue(Key, Row) then
          Inc(Row.Count, Src.Count)
        else
          Row := Src;
        Counts.AddOrSetValue(Key, Row);
      end;
    Result := RowsFromCounts(Counts);
  finally
    Counts.Free;
  end;
end;

function IsStandardVclOrFmxUnit(const AUnitName: string): Boolean;
var
  Ns: string;
begin
  Result := False;
  if Trim(AUnitName) = '' then Exit;
  for Ns in STD_CONTROL_NAMESPACES do
    if StartsText(Ns, Trim(AUnitName)) then Exit(True);
end;

function TypeIsExcluded(const ATypeName, ADeclaringUnit: string;
  const APatterns: TArray<string>; AExcludeStandard: Boolean;
  out AError: string): Boolean;
var
  P      : string;
  StdHit : Boolean;
  PatHit : Boolean;
begin
  AError := '';
  StdHit := AExcludeStandard and IsStandardVclOrFmxUnit(ADeclaringUnit);
  PatHit := False;

  // Every pattern is evaluated even once one has matched, so a malformed condition
  // LATER in the list still reports. Reporting is the only thing that makes the
  // fail-open below safe: a bad pattern excludes nothing, and if that were silent
  // the user would read an un-greyed row as "my filter says keep this".
  for P in APatterns do
  begin
    if Trim(P) = '' then Continue;
    try
      if TRegEx.IsMatch(ATypeName, P, [roIgnoreCase]) then PatHit := True;
    except
      on E: Exception do
        if AError = '' then
          AError := Format('bad pattern "%s": %s', [P, E.Message]);
    end;
  end;

  Result := StdHit or PatHit;
end;

function RowIsGreyed(const ARow: TFormTypeRow): Boolean;
begin
  // Reenabled is the user's explicit override and beats BOTH reasons. The reasons
  // stay on the row so the panel can still say why it was grey.
  Result := (ARow.Excluded or ARow.Ruled) and (not ARow.Reenabled);
end;

end.
