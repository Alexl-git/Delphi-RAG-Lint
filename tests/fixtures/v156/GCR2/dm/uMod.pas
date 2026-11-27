unit uMod;

interface

uses
  System.Classes, Data.DB, FireDAC.Comp.Client;

type
  TdmMod = class(TDataModule)
    tblOrders: TFDTable;
    tblOrdersID: TIntegerField;
    tblOrdersQTY: TIntegerField;
    tblCust: TFDTable;
    tblCustID: TIntegerField;
    tblCustNAME: TStringField;
  end;

var
  dmMod: TdmMod;

implementation

{$R *.dfm}

end.
