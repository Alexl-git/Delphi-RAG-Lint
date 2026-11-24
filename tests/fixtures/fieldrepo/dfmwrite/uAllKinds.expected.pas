unit uAllKinds;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Data.DB, FireDAC.Comp.DataSet, FireDAC.Comp.Client,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf,
  FireDAC.DApt.Intf, cxGraphics, cxControls, cxGridCustomView, cxGridCustomTableView, cxGridTableView,
  cxGridDBTableView, cxGridLevel, cxGrid, cxClasses, cxTL, cxTLData, cxDBTL;

type
  TfrmAllKinds = class; // a forward declaration is not the class

  TfrmAllKinds = class(TForm)
    Grid: TcxGrid;
    GridView: TcxGridDBTableView;
    GridViewQTY: TcxGridDBColumn;
    GridViewSTATUS: TcxGridDBColumn;
    GridLevel: TcxGridLevel;
    Tree: TcxDBTreeList;
    TreeNOTE: TcxDBTreeListColumn;
    TreeSTATUS: TcxDBTreeListColumn;
    dsOrders: TDataSource;
    memOrders: TFDMemTable;
    memOrdersID: TIntegerField;
    memOrdersQTY: TIntegerField; // the quantity; not the price
    memOrdersNOTE: TStringField;
    memOrdersOLDCOL: TIntegerField;
    memOrdersUSEDCOL: TIntegerField;
    memOrdersBIG: TStringField;
    memOrdersDESCR: TMemoField;
    memOrdersFLAG: TBooleanField;
    memOrdersPRICE: TBCDField;
    memOrdersSUMQ: TAggregateField;
    memOrdersTOOLID: TIntegerField;
    memOrdersTOTAL: TFloatField;
    memOrdersWHENAT: TSQLTimeStampField;
    memOrdersTOOL: TStringField;
    memTools: TFDMemTable;
    memToolsID: TIntegerField;
    memToolsNAME: TStringField;
    Image: TImage;
  private
    { memOrdersOLDCOL in a comment is no use }
    function Used: Integer;
  end;

implementation

{$R *.dfm}

function TfrmAllKinds.Used: Integer;
begin
  Result := memOrdersUSEDCOL.AsInteger;
end;

end.
