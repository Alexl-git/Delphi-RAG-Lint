unit uLinDirect;

{ Fixture of tests\autotest\run_v156_LIN1.ps1 (1.56 lane LIN-1, lineage model; SPEC-LIN 5.2 "uLinDirect").
  Never compiled: it is indexed. The tests find their lines by the M-... markers, so lines may move. }

interface

uses
  System.Classes, System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfLinDirect = class(TForm)
    tblOrders: TFDQuery;
    tblOrdersQTY: TFloatField;
    tblOrdersPRICE: TFloatField;
    tblOrdersTOTAL: TFloatField;
    tblOrdersSTAMP: TDateTimeField;
    tblOrdersIDLE: TFloatField;
    qryCust: TFDQuery;
    tblM: TFDMemTable;
    tblMX: TFloatField;
    qryQ: TFDQuery;
    qryQA: TFloatField;
    qryQB: TFloatField;
    procedure tblOrdersAfterOpen(DataSet: TDataSet);
  public
    procedure FillX;
  end;

var
  fLinDirect: TfLinDirect;

implementation

{$R *.dfm}

procedure TfLinDirect.FillX;
begin
  tblMX.AsFloat := qryQA.AsFloat * qryQB.AsFloat; { M-SIMPLE }
end;

procedure TfLinDirect.tblOrdersAfterOpen(DataSet: TDataSet);
var
  d: Double;
begin
  d := tblOrdersQTY.AsFloat * tblOrdersPRICE.AsFloat; { M-VIA }
  tblOrdersTOTAL.AsFloat := d * (1 - qryCust.FieldByName('DISCOUNT').AsFloat); { M-TOTAL }
  tblOrdersSTAMP.AsDateTime := Now; { M-STAMP }
end;

end.
