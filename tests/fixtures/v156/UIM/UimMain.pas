unit UimMain;

interface

uses
  System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms, Vcl.DBCtrls;

type
  TfrmMain = class(TForm)
    qCust: TFDQuery;
    qCustCUSTNAME: TStringField;
    edName: TDBEdit;
    edCity: TDBEdit;
  public
    function CustName: string;
  end;

implementation

{$R *.dfm}

function TfrmMain.CustName: string;
begin
  Result := qCust.FieldByName('CUSTNAME').AsString;
end;

end.