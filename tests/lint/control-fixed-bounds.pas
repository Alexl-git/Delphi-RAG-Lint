unit control_fixed_bounds;

{ Fixture for control-fixed-bounds (hint, OFF by default; the .config.json
  enables it). Fires when a VCL unit sets Width / Height / Left / Top of a
  control to a fixed non-zero literal or unit constant, and on SetBounds with
  one. Silent: 0, a TRect, a bitmap, a scaled value. (+) must fire, (-) must not. }

interface

uses
  System.Types, Vcl.Graphics, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Forms;

const
  PANEL_W = 300;
  NO_SIZE = 0;

type
  TSizedForm = class(TForm)
  private
    FEdit: TEdit;
    FBmp: TBitmap;
    procedure Arrange;
  end;

procedure SizePanel(APanel: TPanel);

implementation

procedure TSizedForm.Arrange;
var
  R: TRect;
  Lbl: TLabel;
begin
  Lbl := TLabel.Create(Self);
  Width := 640; { (+) }
  FEdit.Width := 240; { (+) }
  Lbl.Left := 8; { (+) }
  Self.Height := PANEL_W; { (+) }
  FEdit.Top := NO_SIZE; { (-) }
  FEdit.Height := 0; { (-) }
  R.Left := 10; { (-) }
  FBmp.Width := 16; { (-) }
  FEdit.Width := ScaleValue(240); { (-) }
  FEdit.SetBounds(0, 0, 100, 20); { (+) }
end;

procedure SizePanel(APanel: TPanel);
begin
  APanel.Width := 50; { (+) }
end;

end.
