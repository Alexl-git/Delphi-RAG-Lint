unit DragLint.Plugin.Theme;

{ Session 27: IDE light/dark theming, shared.

  This logic already existed, implementation-private, inside
  DragLint.Plugin.HoverForm -- where it was worked out the hard way. When the
  About window needed the same behaviour the choice was to copy it or to share
  it, and this codebase has a written record of what copying costs: DbResolver's
  own header describes two divergent DB resolvers that drifted until they
  disagreed, and this session already found a second library-path resolver doing
  the same thing. So HoverForm now delegates here rather than keeping its copy.

  THE TRAP, preserved from HoverForm's original comment because it is the whole
  reason a first attempt at theming does nothing: the RAD Studio IDE themes
  itself through IOTAIDEThemingServices, NOT the process-global VCL
  TStyleManager. `TStyleManager.IsCustomStyleActive` reads False and the global
  `StyleServices` is the light default even while the IDE is visibly dark. The
  IDE's OWN StyleServices must be pulled from the theming service and mapped
  through THAT. }

interface

uses
  Vcl.Forms
  , Vcl.Graphics
  ;

/// <summary>Applies the IDE's active theme to a form and its child controls.</summary>
/// <param name="AForm">The form to recolor.</param>
/// <param name="AFormClass">The form's class, registered once with the theme
/// engine so it recognises the class.</param>
/// <remarks>Best-effort and fully guarded: a missing service or a theming-
/// disabled IDE leaves the form on its default colours rather than failing.
/// Main thread only.</remarks>
procedure ApplyIdeTheme(AForm: TCustomForm; AFormClass: TCustomFormClass);

/// <summary>Maps a system colour (clWindow, clWindowText, ...) through the IDE's
/// ACTIVE theme.</summary>
/// <param name="ASystemColor">A system colour constant.</param>
/// <returns>The themed colour, or ASystemColor when theming is unavailable.</returns>
/// <remarks>Needed for any control that opts out of style hooking
/// (StyleElements := []) to keep custom foreground colours: such a control also
/// loses the themed BACKGROUND and would otherwise paint white under a dark
/// theme. Main thread only.</remarks>
function ThemedColor(ASystemColor: TColor): TColor;

/// <summary>True when the IDE is currently running a dark theme.</summary>
/// <returns>True if the themed window background is dark.</returns>
/// <remarks>Decided from the themed clWindow's luminance rather than a theme
/// NAME: names are not a stable contract and a user can install their own.</remarks>
function IsDarkTheme: Boolean;

/// <summary>A status colour guaranteed readable against the themed background.</summary>
/// <param name="ABase">The intended colour, e.g. clRed for a failure.</param>
/// <returns>ABase, or a lightened/darkened variant meeting WCAG 4.5:1.</returns>
/// <remarks>clRed and clGreen on a dark background fall well below readable
/// contrast, so a status screen that colour-codes severity MUST adjust or the
/// colour that carries the meaning becomes the colour you cannot read.
/// Main thread only.</remarks>
function ThemedStatusColor(ABase: TColor): TColor;

implementation

uses
  System.SysUtils
  , Winapi.Windows
  , Vcl.Themes
  , ToolsAPI
  , DRagLint.Hover.Contrast
  ;

var
  { Registering the same class twice is harmless but pointless; track the ones
    already handed to the theme engine. }
  GRegistered: array of TCustomFormClass;

function AlreadyRegistered(AFormClass: TCustomFormClass): Boolean;
var
  C: TCustomFormClass;
begin
  Result:= False;
  for C in GRegistered do
    if C = AFormClass then Exit(True);
end;

procedure ApplyIdeTheme(AForm: TCustomForm; AFormClass: TCustomFormClass);
var
  Theming: IOTAIDEThemingServices;
begin
  try
    if AForm = nil then Exit;
    if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then Exit;
    if not Theming.IDEThemingEnabled then Exit;
    if (AFormClass <> nil) and not AlreadyRegistered(AFormClass) then
    begin
      Theming.RegisterFormClass(AFormClass);
      SetLength(GRegistered, Length(GRegistered) + 1);
      GRegistered[High(GRegistered)]:= AFormClass;
    end;
    Theming.ApplyTheme(AForm);
  except
    { theming is best-effort -- never let it break the window it decorates }
  end;
end;

function ThemedColor(ASystemColor: TColor): TColor;
var
  Theming: IOTAIDEThemingServices;
  SS     : TCustomStyleServices  ;
begin
  Result:= ASystemColor;
  try
    if Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) and Theming.IDEThemingEnabled then
    begin
      SS:= Theming.StyleServices; { the IDE's active StyleServices, not the global one }
      if (SS <> nil) and SS.Enabled then Result:= SS.GetSystemColor(ASystemColor);
    end;
  except
    { defensive: never let theming break the caller }
  end;
end;

function IsDarkTheme: Boolean;
var
  Bg : TColor;
  Rgb: Longint;
begin
  Bg := ThemedColor(clWindow);
  Rgb:= ColorToRGB(Bg);
  { Rec. 601 luma is enough to answer "is this dark"; the precise WCAG maths
    lives in EnsureReadable, which is what actually fixes the colour. }
  Result:= ((GetRValue(Rgb) * 299) + (GetGValue(Rgb) * 587) + (GetBValue(Rgb) * 114)) div 1000 < 128;
end;

function ThemedStatusColor(ABase: TColor): TColor;
begin
  Result:= EnsureReadable(ABase, ThemedColor(clWindow), 4.5);
end;

end.
