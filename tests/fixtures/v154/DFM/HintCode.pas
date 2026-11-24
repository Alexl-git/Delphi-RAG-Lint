unit HintCode;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.Dialogs, System.Classes;

type
  THintCode = class(TForm)

    procedure Run;
  end;

var
  HintCodeVar: THintCode;

implementation

{$R *.dfm}


procedure THintCode.Run;
begin
  Edit1.ShowHint := True;
end;


end.
