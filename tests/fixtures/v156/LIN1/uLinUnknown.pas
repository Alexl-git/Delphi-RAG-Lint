unit uLinUnknown;

{ Fixture of tests\autotest\run_v156_LIN1.ps1 (1.56 lane LIN-1, lineage model; SPEC-LIN 5.2 "uLinUnknown").
  Never compiled: it is indexed. The tests find their lines by the M-... markers, so lines may move. }

interface

uses
  System.Classes, System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfLinUnknown = class(TForm)
    tblOrders: TFDQuery;
    tblOrdersQTY: TFloatField;
    tblOrdersU1B: TFloatField;
    tblOrdersU2: TStringField;
    tblOrdersU3: TFloatField;
    qryCust: TFDQuery;
  public
    procedure Fill;
  end;

var
  fLinUnknown: TfLinUnknown;

implementation

{$R *.dfm}

procedure TfLinUnknown.Fill;
var
  vName: string;
begin
  vName := 'U' + IntToStr(1);
  tblOrders.FieldByName(vName).AsFloat := tblOrdersQTY.AsFloat; { M-U1 }
  tblOrders.FieldByName('U1B').AsFloat := tblOrdersQTY.AsFloat; { M-U1B }
  tblOrdersU2.AsVariant := qryCust.Lookup('ID', 1, 'NAME'); { M-U2 }
  with tblOrders, qryCust do
    FieldByName('U3').AsFloat := FieldByName('QTY').AsFloat; { M-U3 }
end;

end.
