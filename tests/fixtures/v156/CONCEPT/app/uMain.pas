unit uMain;

interface

uses
  System.Classes, Data.DB, Vcl.Forms, Vcl.Controls, Vcl.DBGrids, FireDAC.Comp.Client,
  cxGrid, cxGridDBTableView, cxDBEdit;

type
  TfrmMain = class(TForm)
    qryCustomers: TFDQuery;
    qryCustomersID: TIntegerField;
    qryCustomersNAME: TStringField;
    qryCustomersCREDIT_LIMIT: TFloatField;
    dsCustomers: TDataSource;
    tblSuppliers: TFDTable;
    tblSuppliersNAME: TStringField;
    dsSuppliers: TDataSource;
    grdMain: TcxGrid;
    tvCustomers: TcxGridDBTableView;
    colName: TcxGridDBColumn;
    colLimit: TcxGridDBColumn;
    colName2: TcxGridDBColumn;
    colOther: TcxGridDBColumn;
    edtName: TcxDBTextEdit;
    grdOld: TDBGrid;
  private
    Name: string;
  public
    procedure CustomerNameChanged;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

procedure TfrmMain.CustomerNameChanged;
begin
  Name := qryCustomers.FieldByName('NAME').AsString;
  if qryCustomersNAME.AsString = '' then
    Name := tblSuppliers.FindField('NAME').AsString;
end;

end.
