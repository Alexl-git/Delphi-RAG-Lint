unit component_fixed_pixels;

{ Fixture for component-fixed-pixels (hint, OFF by default; the .config.json
  enables it). Fires once per drawing call that has an integer literal of 2 or
  more among its arguments, inside a Paint / Draw / Resize routine. Silent: 0 and
  1, a divisor, a factor, a hex literal, a literal inside a scaling call, an image
  list Draw (index argument), a routine that does not paint. (+) must fire, (-) must not. }

interface

uses
  Classes, Types, Controls, Graphics, ImgList;

type
  TBox = class(TCustomControl)
  private
    FArea: TRect;
    FBmp: TBitmap;
    FImages: TImageList;
    procedure Prepare;
  protected
    procedure Paint; override;
    procedure Resize; override;
  end;

implementation

procedure TBox.Paint;
var
  R: TRect;
begin
  R := ClientRect;
  Canvas.FillRect(Rect(0, 0, 16, 16)); { (+) }
  Canvas.TextOut(ScaleValue(4), ScaleValue(2), 'x'); { (-) }
  Canvas.MoveTo(0, 1); { (-) }
  Canvas.LineTo(Width div 2, Height div 2); { (-) }
  Canvas.Rectangle(R.Left + 3, R.Top, R.Right, R.Bottom); { (+) }
  Canvas.Draw(MulDiv(8, CurrentPPI, 96), 0, FBmp); { (-) }
  Canvas.Ellipse(0, 0, 2 * Width, Height); { (-) }
  FImages.Draw(Canvas, 0, 0, 5); { (-) }
  Canvas.Rectangle(0, 0, $7F, Height); { (-) }
end;

procedure TBox.Resize;
begin
  inherited Resize;
  FArea := Bounds(0, 0, 20, 20); { (+) }
end;

procedure TBox.Prepare;
begin
  FArea := Rect(0, 0, 16, 16); { (-) }
end;

end.
