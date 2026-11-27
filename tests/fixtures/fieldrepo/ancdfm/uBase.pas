unit uBase;

interface

uses
  System.Classes, Data.DB, FireDAC.Comp.Client;

type
  TdmBase = class(TDataModule)
    tblOrders: TFDTable;
    tblOrdersID: TIntegerField;
    tblOrdersQTY: TIntegerField;
    tblCust: TFDTable;
    tblCustID: TIntegerField;
    tblCustNAME: TStringField;
    qryItems: TFDQuery;
    qryItemsID: TIntegerField;
    qryItemsCODE: TStringField;
  end;

var
  dmBase: TdmBase;

implementation

{$R *.dfm}

end.
