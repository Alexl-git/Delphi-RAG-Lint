unit uInput;

interface

uses
  Classes, StdCtrls, Forms;

type
  TfrmInput = class(TForm)
    Edit1: TEdit;
    procedure btnRunClick(Sender: TObject);
  end;

function ReadArg: string;

implementation

uses
  uDal;

function ReadArg: string;
begin
  Result := Trim(ParamStr(1));
end;

procedure TfrmInput.btnRunClick(Sender: TObject);
var
  S: string;
begin
  S := Edit1.Text;
  RunQuery(S);
end;

end.
