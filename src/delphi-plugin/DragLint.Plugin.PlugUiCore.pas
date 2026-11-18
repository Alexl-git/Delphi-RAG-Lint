unit DragLint.Plugin.PlugUiCore;

{ Lane PLUGUI (1.52): the pure, ToolsAPI-free halves of two plugin UI fixes, so
  a headless test can pin them.

    N2  rules search (Lint Options): the debounce interval and the "does this
        edit need a refill at all" rule.
    N3  Find Usages panel: the row colours, computed through an injected colour
        mapper (the IDE theme in the plugin, a fake dark theme in the test). }

interface

uses
  Vcl.Graphics
  , DRagLint.Lint.Config
  ;

const
  /// <summary>Quiet time after the last keystroke / clear before the rules
  /// list is refilled, in milliseconds.</summary>
  SEARCH_DEBOUNCE_MS = 250;

type
  /// <summary>Maps a system colour (clWindow, clWindowText, ...) to the colour
  /// the active theme paints it with.</summary>
  TColorMapper = reference to function(AColor: TColor): TColor;

/// <summary>True when the rules list must be refilled for the new search text.</summary>
/// <param name="AAppliedTrim">The trimmed search text the list currently shows.</param>
/// <param name="ANewText">The raw text now in the search box.</param>
/// <param name="AHasData">False while no catalog is loaded (nothing to refill).</param>
/// <returns>False when nothing is loaded or the trimmed text did not change
/// (e.g. only a trailing space was typed).</returns>
function SearchRefillNeeded(const AAppliedTrim, ANewText: string; AHasData: Boolean): Boolean;

/// <summary>Colours for one caller row of the Find Usages tree.</summary>
/// <param name="ASelected">True for the selected / marked row.</param>
/// <param name="AMap">Theme mapper; the form passes the IDE theme's ThemedColor.</param>
/// <param name="ABack">Row background.</param>
/// <param name="AText">Plain text colour.</param>
/// <param name="AMatch">Colour of the highlighted symbol (bold); readable
/// against ABack on both light and dark themes.</param>
procedure UsageRowColors(ASelected: Boolean; const AMap: TColorMapper; out ABack, AText, AMatch: TColor);

/// <summary>One line of the Lint Options "Overrides" list for a rule_overrides entry.</summary>
/// <param name="AOverride">The entry (project-wide disable and/or excluded units).</param>
/// <returns>'rule - off for the project (reason, date)' and/or 'rule - off in unit a, b'.</returns>
function RuleOverrideCaption(const AOverride: TRuleOverride): string;

/// <summary>Caption of the Lint Options button that opens the overrides list.</summary>
/// <param name="ACount">How many rule_overrides entries the active config holds.</param>
/// <returns>'Overrides...' for none, else 'Overrides (N)...'.</returns>
function OverridesButtonCaption(ACount: Integer): string;

implementation

uses
  System.SysUtils
  , DRagLint.Hover.Contrast
  ;

const
  AMBER_BGR       = TColor($004080FF); { the highlight hue the panel always used }
  MATCH_MIN_RATIO = 3.0;               { large bold text: WCAG 3:1 }

function RuleOverrideCaption(const AOverride: TRuleOverride): string;
var
  Why: string;
begin
  Result:= AOverride.RuleId;
  if AOverride.HasEnabled and not AOverride.Enabled then
  begin
    Why:= Trim(AOverride.Reason);
    if AOverride.Date <> '' then Why:= Trim(Why + ', ' + AOverride.Date).TrimLeft([',', ' ']);
    Result:= Result + ' - off for the project' + (if Why <> '' then ' (' + Why + ')' else '');
  end;
  if Length(AOverride.ExcludeUnits) > 0 then
    Result:= Result + ' - off in unit ' + string.Join(', ', AOverride.ExcludeUnits);
end;

function OverridesButtonCaption(ACount: Integer): string;
begin
  Result:= if ACount > 0 then Format('Overrides (%d)...', [ACount]) else 'Overrides...';
end;function SearchRefillNeeded(const AAppliedTrim, ANewText: string; AHasData: Boolean): Boolean;
begin
  Result:= AHasData and (Trim(ANewText) <> AAppliedTrim);
end;

procedure UsageRowColors(ASelected: Boolean; const AMap: TColorMapper; out ABack, AText, AMatch: TColor);
begin
  if ASelected then
  begin
    ABack := AMap(clHighlight);
    AText := AMap(clHighlightText);
    AMatch:= AText;
  end
  else
  begin
    ABack := AMap(clWindow);
    AText := AMap(clWindowText);
    AMatch:= EnsureReadable(AMBER_BGR, ABack, MATCH_MIN_RATIO);
  end;
end;

end.
