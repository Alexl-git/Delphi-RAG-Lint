unit DragLint.Plugin.SeverityGlyph;

{ Per-severity diagnostic glyphs for the editor gutter and the Diagnostics tree.

  WHY THESE ARE DRAWN AND NOT RASTERISED FROM THE SUPPLIED SVGs
  -------------------------------------------------------------
  docs\INBOX-ide-diagnostic-icons.md proposed TImageCollection +
  TVirtualImageList with the SVG source held as string constants, on the premise
  that "Delphi 11+ renders SVG natively via TImageCollection". It flagged that
  premise as needing verification. It is WRONG, and this is the verification:
  Vcl.ImageCollection.pas in RAD Studio 37 contains no occurrence of "svg" at
  all, and TImageCollection's source images are TWICImage -- Windows Imaging
  Component, which has no SVG decoder. That route cannot work.

  The two routes that could:
    * Vcl.Skia (TSkSvgBrush). sk4d.dll does ship, in Studio\37.0\bin, which is
      bds.exe's own directory -- but using it means adding Skia to a design-time
      package that currently requires only rtl, vcl, vclsmp, designide, and a
      package-load collision in a design-time BPL compiles clean and fails only
      in a live IDE (Delphi_IDE_OptionsPage_HOWTO.md, W1033).
    * dxSVGCore.TdxSVGBrush. DevExpress is installed and loaded by the IDE, but
      this package deliberately does not require it, for the same reason.

  Both are one-way doors that cannot be tested without a live IDE. GDI is not:
  it has no dependency, no resource load (so no EResNotFound, the design-time
  trap this repo has already hit), and it degrades to nothing only if GDI
  itself fails. The INBOX note asked for a GDI fallback "so a failure degrades
  to a glyph, never to nothing" -- since the primary route does not exist, the
  fallback is the design.

  What is lost is essentially nothing at this size. The note says it itself: the
  supplied artwork is drawn on a 32-unit grid, a gutter glyph renders at 12-16px,
  and 32-grid strokes land on half-pixels and blur. These shapes are drawn FOR
  the target size, from the same silhouettes and the same palette as the SVGs:

      error   Actions_DeleteCircled  filled circle, white X          #D11C1C
      warning Security_Warning       filled triangle, dark bang      #FFB115 / #727272
      info    Actions_Info           filled circle, white i          #1177D7
      hint    Actions_CheckCircled   filled circle, white check      #039C23 (muted)

  The hint green is deliberately muted toward grey. Actions_CheckCircled is a
  tick, which reads as "passed", and hint is the third most common severity
  (403 on the ORM3 baseline) -- a bright green tick every third line looks like
  the gutter is congratulating the user. Owner instruction, 2026-08-25.

  COLOUR POLICY, and it is a deliberate change worth objecting to if it is
  wrong: the glyph uses the ICON palette above, not LoadEditorColors. The
  editor colours (clRed / clOlive / clTeal / clNavy by default) are the right
  answer for the wavy UNDERLINE, which is text decoration and should match the
  IDE's syntax colouring -- and PaintLine still uses them there. But the gutter
  glyph is a product asset the owner chose by supplying these four files, and
  drawn in clOlive a warning triangle simply is not the warning icon. Flip
  GLYPH_USES_EDITOR_COLORS if that judgement is wrong. }

interface

uses
  Winapi.Windows
  , System.Classes
  , Vcl.Graphics
  , Vcl.Controls
  , Vcl.ImgList
  , DragLint.Plugin.DiagnosticCache
  ;

const
  { Set True to take glyph colours from LoadEditorColors instead of the icon
    palette. See the colour-policy note in this unit's header. }
  GLYPH_USES_EDITOR_COLORS = False;

  { TColor is $00BBGGRR, so these are the SVG hex values byte-reversed. }
  GLYPH_ERROR_FILL   = TColor($001C1CD1); { #D11C1C  .Red   }
  GLYPH_WARNING_FILL = TColor($0015B1FF); { #FFB115  .Yellow }
  GLYPH_WARNING_MARK = TColor($00727272); { #727272  .Black  }
  GLYPH_INFO_FILL    = TColor($00D77711); { #1177D7  .Blue   }
  { #039C23 blended 50% toward #808080 -> #418E51. See the hint note above. }
  GLYPH_HINT_FILL    = TColor($00518E41);

/// <summary>The icon-palette fill colour for a severity.</summary>
/// <param name="ASeverity">Severity to colour.</param>
/// <returns>A solid TColor; never clNone.</returns>
function SeverityGlyphColor(ASeverity: TDragLintSeverity): TColor;

/// <summary>Draws the severity glyph into ARect on ACanvas.</summary>
/// <param name="ACanvas">Target canvas. Pen and Brush are saved and restored,
/// so the caller's state is untouched.</param>
/// <param name="ARect">Bounding box. The glyph is drawn as a square inscribed
/// in it and centred; a rect narrower than 7px is skipped rather than drawn as
/// an unreadable smudge.</param>
/// <param name="ASeverity">Which glyph.</param>
/// <param name="AFill">Fill colour, normally SeverityGlyphColor(ASeverity).</param>
/// <remarks>Pure GDI: no image list, no resource, no external package. Safe to
/// call from a paint handler. Call from the VCL thread only.</remarks>
procedure PaintSeverityGlyph(ACanvas: TCanvas; const ARect: TRect;
  ASeverity: TDragLintSeverity; AFill: TColor);

/// <summary>A 4-entry image list of the severity glyphs, for controls that
/// render icons through an image list (the Diagnostics TTreeView).</summary>
/// <param name="ASize">Square glyph size in pixels; clamped to 8..64.</param>
/// <returns>A cached list owned by this unit -- do NOT free it, and do not
/// assign it an Owner that will. Rebuilt only when ASize changes, since a tree
/// asks for one size and keeps it.</returns>
/// <remarks>Indices are SeverityGlyphIndex order, NOT Ord(TDragLintSeverity).
/// Returns nil if the list cannot be built, so callers must handle nil and
/// simply show no icon -- which is what they did before this existed.</remarks>
function SeverityGlyphImages(ASize: Integer): TCustomImageList;

/// <summary>Image-list index for a severity.</summary>
/// <param name="ASeverity">Severity to map.</param>
/// <returns>0 error, 1 warning, 2 info, 3 hint.</returns>
/// <remarks>Deliberately NOT Ord(ASeverity): TDragLintSeverity is declared
/// (dlsError, dlsWarning, dlsHint, dlsInfo), so Ord puts hint before info. An
/// index that silently disagrees with reading order is the kind of thing that
/// mislabels every icon and looks like an artwork problem.</remarks>
function SeverityGlyphIndex(ASeverity: TDragLintSeverity): Integer;

implementation

uses
  System.SysUtils
  , System.Math
  , DragLint.Plugin.Telemetry
  ;

const
  { Interior-mark geometry, as PERCENTAGES of the glyph box, so every shape
    scales with DPI instead of carrying pixel offsets. Named rather than inlined
    because these are the numbers anyone tuning the artwork will reach for, and
    because a bare 26 in a LineTo says nothing about what it positions. }
  CHECK_X1 = 26;  CHECK_Y1 = 52;   { check: start, on the left limb   }
  CHECK_X2 = 44;  CHECK_Y2 = 70;   {        vertex, at the bottom     }
  CHECK_X3 = 76;  CHECK_Y3 = 30;   {        end, top of the long limb }
  INFO_DOT_TOP  = 22;              { "i" tittle                       }
  INFO_STEM_TOP = 42;
  INFO_STEM_BOT = 78;
  PCT           = 100;
  { Outline darkness. Enough to separate the glyph from a light gutter,
    little enough not to swallow a 9px shape the way clBlack did. }
  OUTLINE_DARKEN_PCT = 35;

var
  GImages    : TImageList = nil;
  GImagesSize: Integer    = 0;

function SeverityGlyphIndex(ASeverity: TDragLintSeverity): Integer;
begin
  case ASeverity of
    dlsError  : Result:= 0;
    dlsWarning: Result:= 1;
    dlsHint   : Result:= 3;
    else        Result:= 2; { dlsInfo }
  end;
end;

function SeverityGlyphColor(ASeverity: TDragLintSeverity): TColor;
begin
  case ASeverity of
    dlsError  : Result:= GLYPH_ERROR_FILL;
    dlsWarning: Result:= GLYPH_WARNING_FILL;
    dlsHint   : Result:= GLYPH_HINT_FILL;
    else        Result:= GLYPH_INFO_FILL;
  end;
end;

{ Darkened fill, used for the outline. A pure black outline swallows too much of
  a 10px glyph; a darker shade of the fill keeps the silhouette crisp on both a
  light and a dark gutter without dominating it. }
function Darken(AColor: TColor; APercent: Integer): TColor;
var
  RGBv: Cardinal;
  R, G, B: Integer;
begin
  RGBv:= ColorToRGB(AColor);
  R:= GetRValue(RGBv) * (100 - APercent) div 100;
  G:= GetGValue(RGBv) * (100 - APercent) div 100;
  B:= GetBValue(RGBv) * (100 - APercent) div 100;
  Result:= TColor(Winapi.Windows.RGB(R, G, B));
end;

procedure PaintSeverityGlyph(ACanvas: TCanvas; const ARect: TRect;
  ASeverity: TDragLintSeverity; AFill: TColor);
var
  D, X, Y, M, Stroke: Integer     ;
  SavedPenColor     : TColor      ;
  SavedPenStyle     : TPenStyle   ;
  SavedPenWidth     : Integer     ;
  SavedBrushColor   : TColor      ;
  SavedBrushStyle   : TBrushStyle ;
  Tri               : array[0..2] of TPoint;
  DotTop            : Integer     ;
  StemTop           : Integer     ;
begin
  if not Assigned(ACanvas) then Exit;

  D:= Min(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  { Below this the shapes stop being distinguishable and a smudge is worse than
    nothing -- it reads as a rendering fault rather than as a severity. }
  if D < 7 then Exit;

  X:= ARect.Left + (ARect.Right  - ARect.Left - D) div 2;
  Y:= ARect.Top  + (ARect.Bottom - ARect.Top  - D) div 2;

  SavedPenColor  := ACanvas.Pen  .Color;
  SavedPenStyle  := ACanvas.Pen  .Style;
  SavedPenWidth  := ACanvas.Pen  .Width;
  SavedBrushColor:= ACanvas.Brush.Color;
  SavedBrushStyle:= ACanvas.Brush.Style;
  try
    ACanvas.Brush.Color:= AFill;
    ACanvas.Brush.Style:= bsSolid;
    ACanvas.Pen  .Color:= Darken(AFill, OUTLINE_DARKEN_PCT);
    ACanvas.Pen  .Style:= psSolid;
    ACanvas.Pen  .Width:= 1;

    Stroke:= Max(1, D div 7);
    M     := Max(2, D div 4);

    case ASeverity of

      dlsWarning:
      begin
        { Triangle, apex up, matching Security_Warning's silhouette. }
        Tri[0]:= Point(X + D div 2, Y            );
        Tri[1]:= Point(X + D      , Y + D - 1    );
        Tri[2]:= Point(X          , Y + D - 1    );
        ACanvas.Polygon(Tri);
        { Bang: bar over dot, in the SVG's dark grey rather than white -- that is
          what the asset does, and grey on yellow is far more legible than white
          on yellow at this size. }
        ACanvas.Brush.Color:= GLYPH_WARNING_MARK;
        ACanvas.Pen  .Color:= GLYPH_WARNING_MARK;
        ACanvas.Rectangle(X + (D - Stroke) div 2, Y + D div 3,
                          X + (D - Stroke) div 2 + Stroke, Y + D * 2 div 3);
        ACanvas.Rectangle(X + (D - Stroke) div 2, Y + D * 3 div 4,
                          X + (D - Stroke) div 2 + Stroke, Y + D * 3 div 4 + Stroke);
      end;

      dlsError:
      begin
        ACanvas.Ellipse(X, Y, X + D, Y + D);
        ACanvas.Pen.Color:= clWhite;
        ACanvas.Pen.Width:= Stroke;
        { Far endpoint is D-1-M, not D-M. Ellipse fills pixels X..X+D-1, so
          D-1-M is the mirror of M and the X lands CENTRED; D-M puts it half
          a pixel down-right, which is visibly lopsided at 9px and at D=11
          pushes the lower-right arm outside the circle altogether. Found by
          rendering the arithmetic at every size, not by reading it. }
        ACanvas.MoveTo(X + M        , Y + M        );
        ACanvas.LineTo(X + D - 1 - M, Y + D - 1 - M);
        ACanvas.MoveTo(X + D - 1 - M, Y + M        );
        ACanvas.LineTo(X + M        , Y + D - 1 - M);
      end;

      dlsHint:
      begin
        ACanvas.Ellipse(X, Y, X + D, Y + D);
        ACanvas.Pen.Color:= clWhite;
        ACanvas.Pen.Width:= Stroke;
        ACanvas.MoveTo(X + D * CHECK_X1 div PCT, Y + D * CHECK_Y1 div PCT);
        ACanvas.LineTo(X + D * CHECK_X2 div PCT, Y + D * CHECK_Y2 div PCT);
        ACanvas.LineTo(X + D * CHECK_X3 div PCT, Y + D * CHECK_Y3 div PCT);
      end;

      else { dlsInfo }
      begin
        ACanvas.Ellipse(X, Y, X + D, Y + D);
        { A lower-case i: tittle then stem, both white. Drawn as filled
          rectangles rather than glyph text -- TextOut at 10px with the editor's
          font is not reproducible across DPI settings.

          The gap between them is FORCED, not left to the percentages. At D=14,
          stroke is 2, so the tittle occupies rows 3-4 while INFO_STEM_TOP lands
          on row 5 -- they touch, and the "i" renders as one solid bar that
          reads as an exclamation mark, i.e. as a warning. Caught by rendering
          the arithmetic at every size the gutter can produce (9..16), not by
          looking at the code. }
        ACanvas.Brush.Color:= clWhite;
        ACanvas.Pen  .Color:= clWhite;
        DotTop := Y + D * INFO_DOT_TOP div PCT;
        StemTop:= Max(Y + D * INFO_STEM_TOP div PCT, DotTop + Stroke + 1);
        ACanvas.Rectangle(X + (D - Stroke) div 2, DotTop,
                          X + (D - Stroke) div 2 + Stroke, DotTop + Stroke);
        ACanvas.Rectangle(X + (D - Stroke) div 2, StemTop,
                          X + (D - Stroke) div 2 + Stroke,
                          Y + D * INFO_STEM_BOT div PCT);
      end;

    end; // case
  finally
    ACanvas.Pen  .Color:= SavedPenColor;
    ACanvas.Pen  .Style:= SavedPenStyle;
    ACanvas.Pen  .Width:= SavedPenWidth;
    ACanvas.Brush.Color:= SavedBrushColor;
    ACanvas.Brush.Style:= SavedBrushStyle;
  end; // try
end; // procedure

function SeverityGlyphImages(ASize: Integer): TCustomImageList;
const
  { Index order, so the list is built in SeverityGlyphIndex order rather than
    enum order. Getting this wrong mislabels every row. }
  ORDER: array[0..3] of TDragLintSeverity = (dlsError, dlsWarning, dlsInfo, dlsHint);
var
  I  : Integer;
  Bmp: TBitmap;
begin
  { dcc32 reports H2077 "value assigned ... never used" here, correctly: every
    path below assigns Result. It stays anyway. This returns an object reference
    into a design-time BPL, and the cost of the two states is not symmetric -- a
    redundant nil is a hint, while an unassigned one is a garbage pointer handed
    to a TTreeView. Delphi's W1035 does not reliably catch that through a
    try/except, so the compiler would not necessarily say so if a later edit
    added an exit path. Do not "clean this up". }
  Result:= nil;
  try
    ASize:= Max(8, Min(64, ASize));
    if Assigned(GImages) and (GImagesSize = ASize) then Exit(GImages);

    FreeAndNil(GImages);
    GImagesSize:= 0;

    GImages:= TImageList.Create(nil);
    GImages.Width      := ASize;
    GImages.Height     := ASize;
    { Masked, not alpha-blended: the glyphs are drawn on clFuchsia and that
      colour is knocked out, which is the classic route and needs no 32-bit
      image-list support from whatever control consumes it. }
    GImages.Masked     := True;
    GImages.BkColor    := clNone;

    for I:= Low(ORDER) to High(ORDER) do
    begin
      Bmp:= TBitmap.Create;
      try
        Bmp.PixelFormat:= pf24bit;
        Bmp.SetSize(ASize, ASize);
        Bmp.Canvas.Brush.Color:= clFuchsia;
        Bmp.Canvas.Brush.Style:= bsSolid;
        Bmp.Canvas.FillRect(Rect(0, 0, ASize, ASize));
        PaintSeverityGlyph(Bmp.Canvas, Rect(0, 0, ASize, ASize), ORDER[I],
                           SeverityGlyphColor(ORDER[I]));
        GImages.AddMasked(Bmp, clFuchsia);
      finally
        Bmp.Free;
      end;
    end;

    GImagesSize:= ASize;
    Result:= GImages;
  except
    { A control that gets nil shows no icon, exactly as it did before this unit
      existed -- never let icon construction take down a form. But SAY so: "no
      icon" and "no findings" look identical in a tree, and that exact ambiguity
      is how the gutter's own emptiness went unexplained for a whole session. }
    on E: Exception do
    begin
      FreeAndNil(GImages);
      GImagesSize:= 0;
      Result     := nil;
      { No guard around this call: DLT swallows everything itself and is
        documented never to raise, so wrapping it would only add an empty
        handler of the kind this repo's own rules flag. }
      DLT('glyph', Format('SeverityGlyphImages(%d) FAILED: %s: %s -- rows will show no icon',
          [ASize, E.ClassName, E.Message]));
    end;
  end; // try
end; // function

initialization

finalization
FreeAndNil(GImages);

end.
