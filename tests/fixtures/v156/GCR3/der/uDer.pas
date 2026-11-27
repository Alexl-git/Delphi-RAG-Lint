unit uDer;

{ Fixture of lane GCR-3 item 4: ORDERS.TOTAL is a derived field (its value is computed here), yet the dataset is a table
  dataset, so the DFM field TOTAL maps to the repository row ORDERS|TOTAL. }

interface

uses
  System.Classes, Data.DB, FireDAC.Comp.Client;

type
  TfDer = class(TForm)
    tblOrders: TFDTable;
    tblOrdersQTY: TFloatField;
    tblOrdersPRICE: TFloatField;
    tblOrdersTOTAL: TFloatField;
  public
    procedure Fill;
  end;

implementation

procedure TfDer.Fill;
begin
  tblOrdersTOTAL.AsFloat := tblOrdersQTY.AsFloat * tblOrdersPRICE.AsFloat;
end;

end.
