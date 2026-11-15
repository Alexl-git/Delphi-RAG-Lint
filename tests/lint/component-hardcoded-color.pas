unit component_hardcoded_color;

{ Fixture for component-hardcoded-color (hint, OFF by default; the .config.json
  enables it). Fires in a Paint / Draw routine on RGB(..), TColor(<number>), a
  number assigned to a ...Color member and a number passed to SetTextColor.
  Silent: named colours, a cast of a named colour, a routine that does not
  paint. (+) must fire, (-) must not. }

interface

uses
  Windows, Classes, Controls, Graphics, StdCtrls;

type
  TSwatch = class(TCustomControl)
  private
    FList: TListBox;
    procedure Setup;
    procedure ListDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
  protected
    procedure Paint; override;
  end;

implementation

procedure TSwatch.Paint;
begin
  Canvas.Brush.Color := $00FF8000; { (+) }
  Canvas.Pen.Color := RGB(10, 20, 30); { (+) }
  Canvas.Font.Color := TColor($0000FF); { (+) }
  Canvas.Brush.Color := clBtnFace; { (-) }
  Canvas.Pen.Color := TColor(clRed); { (-) }
  SetTextColor(Canvas.Handle, $00FFFFFF); { (+) }
end;

procedure TSwatch.Setup;
begin
  Color := $00FF8000; { (-) }
end;

procedure TSwatch.ListDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
begin
  FList.Canvas.Brush.Color := RGB(1, 2, 3); { (+) }
end;

end.
