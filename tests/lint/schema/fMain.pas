unit fMain;

{ schema-length-bound fixture (lane FR-LINT): DFM persistent fields and FieldByName on datasets whose
  table the .dfm names (UpdateOptions.UpdateTableName / TableName). }

interface

uses
  System.Classes, Vcl.Forms, Data.DB, FireDAC.Comp.Client, FireDAC.Comp.DataSet;

type
  TfrmMain = class(TForm)
    qryOrders: TFDQuery;
    qryOrdersNOTE: TStringField;
    tblOrders: TFDTable;
    tblOrdersNOTE: TStringField;
    qryList: TFDQuery;
    qryListDIMNAME: TStringField;
    qryFree: TFDQuery;
    qryFreeNOTE: TStringField;
  public
    procedure SizeNotes(const pText: string);
  end;

implementation

{$R *.dfm}

procedure TfrmMain.SizeNotes(const pText: string);
begin
  qryOrders.FieldByName('NOTE').Size := 30; { 30 > 20 -> FIRES }
  qryOrders.FieldByName('NOTE').Size := 20; { silent }
  qryOrdersNOTE.AsString := Copy(pText, 1, 25); { 25 > 20 -> FIRES }
  qryFree.FieldByName('NOTE').Size := 99; { dataset without a table -> silent }
end;

end.
