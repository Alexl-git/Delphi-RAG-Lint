unit FrMain;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, FrFrame;

type
  TFrmMain = class(TForm)
    BtnGo: TButton;
    Lbl: TLabel;
    Frame1: TFrmFrame;
  public
    procedure Poke;
  end;

implementation

{$R *.dfm}

procedure TFrmMain.Poke;
begin
  BtnGo.Caption:= 'poked';
end;

end.
