unit uSerial6;

interface

uses
  System.UITypes, Vcl.Forms;

type
  TfrmSerial6 = class(TForm)
  public
    function Execute(AId: Integer): TModalResult;
  end;

implementation

{$R *.dfm}

function TfrmSerial6.Execute(AId: Integer): TModalResult;
begin
  Tag := AId;
  Result := ShowModal;
end;

end.
