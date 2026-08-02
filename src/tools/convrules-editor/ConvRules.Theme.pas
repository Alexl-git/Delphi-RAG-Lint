unit ConvRules.Theme;

{ Pure theme model for the conversion editor: which visual mode applies, and what
  colour the Examine "used" marking takes on top of it.

  Pure + headless -- no VCL, no registry, no I/O. The form reads the registry and the
  active style colour and passes values in, which is what makes every rule here
  unit-testable against inline fixtures. }

interface

uses
  System.SysUtils;

type
  /// <summary>The visual mode actually in force.</summary>
  TThemeMode = (tmLight, tmDark);

  /// <summary>What the user asked for. tpFollowIde defers to the IDE's own setting.</summary>
  TThemePref = (tpFollowIde, tpLight, tpDark);

/// <summary>Maps the IDE's registry theme name to a mode.</summary>
/// <param name="AIdeTheme">Value of HKCU\Software\Embarcadero\BDS\&lt;ver&gt;\Theme\Theme.</param>
/// <returns>tmDark only for 'Dark' (case-insensitive); tmLight for everything else.</returns>
/// <remarks>Light is the deliberate default for absent, empty or unrecognised values:
/// guessing dark wrongly paints dark text on a dark ground, which is unreadable, whereas
/// guessing light wrongly is merely unfashionable.</remarks>
function IdeThemeToMode(const AIdeTheme: string): TThemeMode;

/// <summary>The mode to apply given the user's preference and the IDE's setting.</summary>
/// <param name="APref">The stored preference.</param>
/// <param name="AIdeTheme">The IDE theme name; consulted only WHERE APref is tpFollowIde.</param>
function ResolveThemeMode(APref: TThemePref; const AIdeTheme: string): TThemeMode;

/// <summary>The background for a row Examine marked as used, derived from the active
/// window colour so it stays visible under any style.</summary>
/// <param name="AWindowColor">The style's resolved window colour, as a TColorRef-style
///   BGR integer.</param>
/// <param name="AMode">The mode in force.</param>
/// <returns>AWindowColor tinted towards green, and so different from AWindowColor for
///   every ground a real style produces. The tint is a fixed per-channel step that
///   saturates at 0 and 255, so a ground already sitting at those clamps comes back
///   unchanged: pure white ($00FFFFFF) in dark mode, and a ground with red = 0 AND
///   blue = 0 (fully saturated green) in light mode. Neither occurs in practice --
///   dark mode is only ever applied to a dark window colour -- but do not rely on the
///   difference for an arbitrary caller-supplied colour.</returns>
/// <remarks>Light mode tints green DOWN from the window colour; dark mode tints UP, so
/// the marking reads as "highlighted" against either ground.</remarks>
function ExamineRowColor(AWindowColor: Integer; AMode: TThemeMode): Integer;

/// <summary>Canonical token for a preference ('followide' | 'light' | 'dark').</summary>
function ThemePrefToStr(APref: TThemePref): string;

/// <summary>Parses a preference token; returns ADefault for anything unrecognised.</summary>
function StrToThemePref(const S: string; ADefault: TThemePref): TThemePref;

implementation

function IdeThemeToMode(const AIdeTheme: string): TThemeMode;
begin
  if SameText(Trim(AIdeTheme), 'Dark') then Result := tmDark else Result := tmLight;
end;

function ResolveThemeMode(APref: TThemePref; const AIdeTheme: string): TThemeMode;
begin
  case APref of
    tpLight: Result := tmLight;
    tpDark : Result := tmDark;
  else
    Result := IdeThemeToMode(AIdeTheme);
  end;
end;

function ExamineRowColor(AWindowColor: Integer; AMode: TThemeMode): Integer;
var
  r, g, b: Integer;
begin
  // Split the BGR integer into channels.
  r := AWindowColor and $FF;
  g := (AWindowColor shr 8) and $FF;
  b := (AWindowColor shr 16) and $FF;
  if AMode = tmLight then
  begin
    // Pull red and blue down, keep green: a pale green wash on a light ground.
    r := r - 39; if r < 0 then r := 0;
    b := b - 39; if b < 0 then b := 0;
  end
  else
  begin
    // Lift green on a dark ground; keep red/blue low so the hue stays green.
    g := g + 48; if g > 255 then g := 255;
    r := r + 8;  if r > 255 then r := 255;
    b := b + 8;  if b > 255 then b := 255;
  end;
  Result := r or (g shl 8) or (b shl 16);
end;

function ThemePrefToStr(APref: TThemePref): string;
begin
  case APref of
    tpLight: Result := 'light';
    tpDark : Result := 'dark';
  else
    Result := 'followide';
  end;
end;

function StrToThemePref(const S: string; ADefault: TThemePref): TThemePref;
var
  T: string;
begin
  T := LowerCase(Trim(S));
  if T = 'light' then Result := tpLight
  else if T = 'dark' then Result := tpDark
  else if T = 'followide' then Result := tpFollowIde
  else Result := ADefault;
end;

end.
