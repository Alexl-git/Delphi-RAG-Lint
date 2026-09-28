unit ConvRules.UnitMask;

{ Session-only view masks for the Unit Rules tab's harvested rows, and the
  display order (spec section 5). Masks never touch rule rows and are never
  saved. Pure. }

interface

uses
  System.SysUtils
  , ConvRules.UsesHarvest
  , ConvRules.UnitStatus
  , ConvRules.UnitPick
  ;

type
  /// <summary>A harvested unit with its classification.</summary>
  TUnitRow = record
    /// <summary>What was harvested.</summary>
    Harvest: THarvestedUnit;
    /// <summary>Its status against the destination.</summary>
    Status : TUnitStatus;
  end;

  /// <summary>The mask controls' state. Default(TUnitMask) hides nothing.</summary>
  TUnitMask = record
    /// <summary>Hide names matching this; '' or an invalid pattern hides nothing.</summary>
    NameMask     : string;
    /// <summary>How NameMask is read.</summary>
    NameMode     : TUnitSearchMode;
    /// <summary>Hide library rows.</summary>
    HideLibrary  : Boolean;
    /// <summary>Hide project rows.</summary>
    HideProject  : Boolean;
    /// <summary>Hide names containing a dot.</summary>
    HideQualified: Boolean;
    /// <summary>Hide project rows whose resolved file lies under this folder.</summary>
    Folder       : string;
  end;

  /// <summary>Answers "does a unit rule already speak about AUnit?".</summary>
  THasRuleFunc = reference to function(const AUnit: string): Boolean;

  /// <summary>What the Unit Rules list shows of the harvest, and where every
  /// other harvested row went.</summary>
  /// <remarks>Each input row lands in exactly one bucket:
  /// Length(Shown) + Masked + Filtered = the number of rows given.</remarks>
  THarvestView = record
    /// <summary>The rows to list, in SortForDisplay order.</summary>
    Shown   : TArray<TUnitRow>;
    /// <summary>Rows that passed the check boxes and have no rule, but a mask hid.</summary>
    Masked  : Integer;
    /// <summary>Rows the check boxes dropped, or that a unit rule already covers.</summary>
    Filtered: Integer;
  end;

/// <summary>Whether AMask hides ARow.</summary>
/// <param name="ARow">A harvested row.</param>
/// <param name="AMask">The mask.</param>
/// <returns>True when any enabled mask matches. The folder mask applies only to
/// rows with a resolved FILE, so MISSING and library rows are never hidden by it.</returns>
function IsMasked(const ARow: TUnitRow; const AMask: TUnitMask): Boolean;

/// <summary>The rows AMask leaves visible, in their original order.</summary>
/// <param name="ARows">All rows.</param>
/// <param name="AMask">The mask.</param>
/// <param name="AHidden">How many rows the mask hid.</param>
/// <returns>The visible rows.</returns>
function ApplyMask(const ARows: TArray<TUnitRow>; const AMask: TUnitMask; out AHidden: Integer): TArray<TUnitRow>;

/// <summary>Rows in display order: MISSING, via scope, unknown, project, library;
/// stable within each group.</summary>
/// <param name="ARows">The rows.</param>
/// <returns>A reordered copy.</returns>
function SortForDisplay(const ARows: TArray<TUnitRow>): TArray<TUnitRow>;

/// <summary>The harvested rows the Unit Rules list shows, with the three counts
/// its status label reports.</summary>
/// <param name="ARows">Every classified harvested row.</param>
/// <param name="AFindMissing">Find missing is ticked (see ShouldAdd).</param>
/// <param name="AIncludeUnqualified">Include unqualified names is ticked.</param>
/// <param name="AHasRule">True when a unit rule already covers the name; such a
/// row is Filtered. nil means no row has a rule.</param>
/// <param name="AMask">The session masks, applied after the check boxes and rules.</param>
/// <returns>Shown in display order; a row the check boxes drop or a rule covers
/// counts as Filtered even when a mask would also hide it.</returns>
function FilterHarvestRows(const ARows: TArray<TUnitRow>; AFindMissing, AIncludeUnqualified: Boolean; const AHasRule: THasRuleFunc; const AMask: TUnitMask): THarvestView;

/// <summary>Index of the row whose harvested name is AName, case-insensitive.</summary>
/// <param name="ARows">The rows.</param>
/// <param name="AName">A unit name.</param>
/// <returns>The index, or -1 when no row has that name.</returns>
function IndexOfRow(const ARows: TArray<TUnitRow>; const AName: string): Integer;

implementation

uses
  System.StrUtils
  ;

const
  DISPLAY_ORDER: array[0..Ord(High(TUnitStatusKind))] of TUnitStatusKind = (uskMissing, uskViaScope, uskUnknown, uskProject, uskLibrary);
  NOT_FOUND    = -1;

function IsUnder(const APath, AFolder: string): Boolean;
begin
  Result:= StartsText(IncludeTrailingPathDelimiter(ExpandFileName(AFolder)), ExpandFileName(APath));
end;

function IsMasked(const ARow: TUnitRow; const AMask: TUnitMask): Boolean;
var
  F: TUnitFilter;
begin
  if AMask.HideLibrary and (ARow.Status.Kind = uskLibrary) then
    Exit(True);
  if AMask.HideProject and (ARow.Status.Kind = uskProject) then
    Exit(True);
  if (AMask.Folder <> '') and (ARow.Status.Kind = uskProject) and (ARow.Status.Resolved <> '') and IsUnder(ARow.Status.Resolved, AMask.Folder) then
    Exit(True);
  if AMask.HideQualified and (Pos('.', ARow.Harvest.UnitName) > 0) then
    Exit(True);
  if (AMask.NameMask <> '') and IsValidUnitSearch(AMask.NameMask, AMask.NameMode) then
  begin
    F.NameText:= '';
    F.Search  := AMask.NameMask;
    F.Mode    := AMask.NameMode;
    Exit(Length(FilterUnits([ARow.Harvest.UnitName], F)) = 1);
  end;
  Result:= False;
end;

function ApplyMask(const ARows: TArray<TUnitRow>; const AMask: TUnitMask; out AHidden: Integer): TArray<TUnitRow>;
var
  R: TUnitRow;
begin
  Result := nil;
  AHidden:= 0;
  for R in ARows do
    if IsMasked(R, AMask) then
      Inc(AHidden)
    else
      Result:= Result + [R];
end;

function SortForDisplay(const ARows: TArray<TUnitRow>): TArray<TUnitRow>;
var
  K: TUnitStatusKind;
  R: TUnitRow;
begin
  Result:= nil;
  for K in DISPLAY_ORDER do
    for R in ARows do
      if R.Status.Kind = K then
        Result:= Result + [R];
end;

function FilterHarvestRows(const ARows: TArray<TUnitRow>; AFindMissing, AIncludeUnqualified: Boolean; const AHasRule: THasRuleFunc; const AMask: TUnitMask): THarvestView;
var
  R     : TUnitRow;
  Passed: TArray<TUnitRow>;
begin
  Result:= Default(THarvestView);
  Passed:= nil;
  for R in ARows do
    if ShouldAdd(R.Status, AFindMissing, AIncludeUnqualified) and not (Assigned(AHasRule) and AHasRule(R.Harvest.UnitName)) then
      Passed:= Passed + [R]
    else
      Inc(Result.Filtered);
  Result.Shown:= SortForDisplay(ApplyMask(Passed, AMask, Result.Masked));
end;

function IndexOfRow(const ARows: TArray<TUnitRow>; const AName: string): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(ARows) do
    if SameText(ARows[i].Harvest.UnitName, AName) then
      Exit(i);
  Result:= NOT_FOUND;
end;

end.
