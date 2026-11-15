unit FrKid;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, FrMain;

type
  TFrmKid = class(TFrmMain)
  public
    function KidCaption: string;
  end;

implementation

{$R *.dfm}

function TFrmKid.KidCaption: string;
begin
  Result:= BtnGo.Caption;
end;

end.
