unit UBars;

interface

uses
  Vcl.Forms;

type
  TFrmBars = class(TForm)
  private
    FDummy: Integer;
  public
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TFrmBars.Touch;
begin
  FindComponent('dxBarButton2').Tag:= 1;
end;

end.
