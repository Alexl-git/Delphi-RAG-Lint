unit uLin2b;

{ Fixture of tests\autotest\run_v156_LIN2.ps1 (1.56 lane LIN-2). Never compiled.
  REBATE is derived from ORDERS.QTY and CUSTOMERS.DISCOUNT, and nothing in this form makes the read plan the FK
  relation ORDERS -> CUSTOMERS: the field is proposed, the input is unplaced until the relation is stored. }

interface

uses
  System.Classes, System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfLin2b = class(TForm)
    tblOrders: TFDQuery;
    tblOrdersQTY: TFloatField;
    tblOrdersREBATE: TFloatField;
    qryCust: TFDQuery;
    qryCustDISCOUNT: TFloatField;
  public
    procedure Fill;
  end;

var
  fLin2b: TfLin2b;

implementation

{$R *.dfm}

procedure TfLin2b.Fill;
begin
  tblOrdersREBATE.AsFloat := tblOrdersQTY.AsFloat * qryCustDISCOUNT.AsFloat;
end;

end.
