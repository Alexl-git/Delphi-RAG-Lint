unit uBase;

interface

uses
  System.SysUtils, System.Classes, Data.DB, FireDAC.Comp.Client;

type
  TdmBase = class(TDataModule)
    tblOrders: TFDTable;
    tblOrdersID: TIntegerField;
    tblOrdersQTY: TIntegerField;
    tblOrdersPRICE: TFloatField;
    tblOrdersTOTAL: TFloatField;
    tblCust: TFDTable;
    tblCustID: TIntegerField;
    qryItems: TFDQuery;
    qryItemsID: TIntegerField;
    qryItemsCODE: TStringField;
    procedure tblOrdersCalcFields(DataSet: TDataSet);
    procedure tblOrdersQTYGetText(Sender: TField; var Text: string; DisplayText: Boolean);
  end;

var
  dmBase: TdmBase;

implementation

{$R *.dfm}

procedure TdmBase.tblOrdersCalcFields(DataSet: TDataSet);
begin
  tblOrdersTOTAL.AsFloat := tblOrdersQTY.AsInteger * tblOrdersPRICE.AsFloat;
end;

procedure TdmBase.tblOrdersQTYGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  Text := IntToStr(Sender.AsInteger) + ' pcs';
end;

end.
