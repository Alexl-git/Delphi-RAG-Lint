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

implementation

uses
  System.StrUtils
  ;

const
  DISPLAY_ORDER: array[0..Ord(High(TUnitStatusKind))] of TUnitStatusKind = (uskMissing, uskViaScope, uskUnknown, uskProject, uskLibrary);

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

end.
