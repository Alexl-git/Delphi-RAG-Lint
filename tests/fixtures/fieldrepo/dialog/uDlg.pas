unit uDlg;

interface

uses
  System.Classes, Vcl.Forms, Data.DB, FireDAC.Comp.Client;

type
  TfrmDlg = class(TForm)
    qryOrders: TFDQuery;
    qryOrdersID: TIntegerField;
    qryOrdersQTY: TIntegerField;
    qryOrdersOLD: TStringField;
  end;

implementation

{$R *.dfm}

end.