unit uCalc;

interface

uses
  System.Classes, Vcl.Forms, Data.DB, FireDAC.Comp.Client;

type
  TfrmCalc = class(TForm)
    qryOrders: TFDQuery;
    qryOrdersID: TIntegerField;
    qryOrdersQTY: TIntegerField;
    qryOrdersPRICE: TFloatField;
    qryOrdersTOTAL: TFloatField;
    procedure qryOrdersCalcFields(DataSet: TDataSet);
  end;

implementation

{$R *.dfm}

procedure TfrmCalc.qryOrdersCalcFields(DataSet: TDataSet);
begin
  qryOrdersTOTAL.Value := qryOrdersQTY.Value * qryOrdersPRICE.Value;
end;

end.