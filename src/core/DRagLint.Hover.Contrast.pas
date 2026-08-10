unit DRagLint.Hover.Contrast;

/// <summary>WCAG 2.x relative-luminance contrast math for the hover popup, so a
/// syntax color is never rendered unreadable against the active theme
/// background. Pure arithmetic -- no VCL forms, no theming state.</summary>

interface

uses
  Vcl.Graphics; // TColor

/// <summary>WCAG relative-luminance contrast ratio between two colors.</summary>
/// <param name="AForeground">Text color (system colors are resolved via ColorToRGB).</param>
/// <param name="ABackground">Background color behind the text.</param>
/// <returns>Ratio in [1.0, 21.0]: 1.0 identical, 21.0 black-on-white.</returns>
/// <remarks>
/// Order-independent (lighter/darker sorted internally).
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoContrastSelfTest (DRagLint.CLI.pas), DRagLint.Hover.Contrast.EnsureReadable (DRagLint.Hover.Contrast.pas)
/// Calls: DRagLint.Hover.Contrast.RelLuminance
/// Returns: (Hi + 0.05) / (Lo + 0.05)
/// Pure
/// <seealso cref="DRagLint.Hover.Contrast.RelLuminance"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ContrastRatio(AForeground, ABackground: TColor): Double;

/// <summary>Return AForeground if it already clears AMinRatio against
/// ABackground; otherwise nudge its lightness away from the background until it
/// does (clamped at black/white).</summary>
/// <param name="AForeground"><!-- drag-lint:auto type -->TColor</param>
/// <param name="ABackground"><!-- drag-lint:auto type -->TColor</param>
/// <param name="AMinRatio">WCAG floor: 4.5 body text, 3.0 large/bold.</param>
/// <returns>A color guaranteed to meet AMinRatio against ABackground.</returns>
/// <remarks>
/// Hue is preserved where possible so "keyword blue" stays blue.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoContrastSelfTest (DRagLint.CLI.pas)
/// Calls: ColorToRGB, DRagLint.Hover.Contrast.ContrastRatio, DRagLint.Hover.Contrast.RelLuminance, EnsureRange, GetBValue, GetGValue, GetRValue, RGB, TColor
/// Returns: AForeground; clWhite
/// Pure
/// <seealso cref="DRagLint.Hover.Contrast.ContrastRatio"/>
/// <seealso cref="DRagLint.Hover.Contrast.RelLuminance"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EnsureReadable(AForeground, ABackground: TColor; AMinRatio: Double = 4.5): TColor;

implementation

uses
  System.Math, Winapi.Windows; // GetRValue etc.

function Linearize(AChannel: Byte): Double;
var
  C: Double;
begin
  C:= AChannel / 255.0;
  if C <= 0.03928 then Result:= C / 12.92
  else Result:= Power((C + 0.055) / 1.055, 2.4);
end;

function RelLuminance(AColor: TColor): Double;
var
  RGB: TColorRef;
begin
  RGB:= ColorToRGB(AColor);
  Result:= 0.2126 * Linearize(GetRValue(RGB))
         + 0.7152 * Linearize(GetGValue(RGB))
         + 0.0722 * Linearize(GetBValue(RGB));
end;

function ContrastRatio(AForeground, ABackground: TColor): Double;
var
  L1, L2, Hi, Lo: Double;
begin
  L1:= RelLuminance(AForeground);
  L2:= RelLuminance(ABackground);
  if L1 >= L2 then begin Hi:= L1; Lo:= L2; end else begin Hi:= L2; Lo:= L1; end;
  Result:= (Hi + 0.05) / (Lo + 0.05);
end;

function EnsureReadable(AForeground, ABackground: TColor; AMinRatio: Double): TColor;
var
  SrcRGB: TColorRef;
  R,G,B : Double   ;
  BgLum : Double   ;
  Step  : Double   ;
  Target: TColor   ;
  I     : Integer  ;
begin
  Result:= AForeground;
  if ContrastRatio(AForeground, ABackground) >= AMinRatio then Exit;

  SrcRGB:= ColorToRGB(AForeground);
  R:= GetRValue(SrcRGB); G:= GetGValue(SrcRGB); B:= GetBValue(SrcRGB);
  BgLum:= RelLuminance(ABackground);
  { push toward white on a dark bg, toward black on a light bg }
  if BgLum < 0.5 then Step:= 12 else Step:= -12;

  for I:= 1 to 24 do
  begin
    R:= EnsureRange(R + Step, 0, 255);
    G:= EnsureRange(G + Step, 0, 255);
    B:= EnsureRange(B + Step, 0, 255);
    { RGB2TColor is absent from this RTL's Vcl.Graphics -- use TColor(RGB(...)) instead. }
    Target:= TColor(RGB(Round(R), Round(G), Round(B)));
    if ContrastRatio(Target, ABackground) >= AMinRatio then Exit(Target);
  end;
  { fell through -- clamp to the maximally-contrasting extreme }
  if BgLum < 0.5 then Result:= clWhite else Result:= clBlack;
end;

end.
