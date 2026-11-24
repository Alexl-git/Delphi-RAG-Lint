unit DataMod;

interface

uses
  System.Classes, Data.DB, Bde.DBTables, FireDAC.Comp.Client, FireDAC.Comp.DataSet;

type
  TdmMain = class(TDataModule)
    qryOrders: TFDQuery;
    qryOrdersID: TLargeintField;
    qryOrdersGONE: TStringField;
    qryOrdersCALC: TStringField;
    qryOrdersLOOK: TStringField;
    qryOrdersCNT: TIntegerField;
    qryOrdersCREATED: TIntegerField;
    qryOrdersNOTE: TStringField;
    tblOrders: TFDTable;
    tblOrdersNOTE: TStringField;
    tblOrdersQTY: TStringField;
    tblOrdersLOST: TStringField;
    qryJoin: TFDQuery;
    qryJoinWHAT: TStringField;
    qryLive: TFDQuery;
    qryLiveNOTE: TStringField;
    qryLiveLIVEX: TStringField;
    tblLive: TFDTable;
    tblLiveLIVEX: TStringField;
    qryOwn: TFDQuery;
    qryOwnLIVEX: TStringField;
    qryOther: TFDQuery;
    qryOtherANY: TStringField;
    bdeTable: TTable;
    bdeTablePDX: TIntegerField;
    bdeTableNOTE: TIntegerField;
    bdeQuery: TQuery;
    qryIns: TFDQuery;
    qryMacro: TFDQuery;
    qryMacroCUSTNAME: TStringField;
    qryBad: TFDQuery;
  public
    procedure Work;
  end;

var
  dmMain: TdmMain;

implementation

{$R *.dfm}

procedure TdmMain.Work;
var
  S: string;
  I: Integer;
begin
  S := bdeTable.FieldByName('PDY').AsString;
  I := bdeTable.FieldByName('NOTE').AsInteger;
  qryOrders.Open;
  S := qryOrders.FieldByName('CALC').AsString;
  S := qryOrders.FieldByName('LOOK').AsString;
  qryOwn.SQL.Text := 'SELECT 1 LIVEX FROM ORDERS';
  S := tblOrders.FieldByName('NOPE').AsString; // FIRE schema-unknown-column
  I := tblOrders.FieldByName('NOTE').AsInteger; // FIRE schema-type-mismatch
  S := tblLive.FieldByName('NOPE').AsString;
  S := qryLive.FieldByName('NOPE').AsString;
end;

end.