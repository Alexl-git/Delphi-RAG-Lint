unit BdeSplitForm;

{ D2 split fixture: one instance of every From class of BDE-to-FireDAC.rules and
  DataDB-to-FireDAC.rules, plus a code site for each trailing #migrate line. }

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Data.DB, Bde.DBTables;

type
  TFrmBdeSplit = class(TForm)
    Session1: TSession;
    Database1: TDatabase;
    Table1: TTable;
    Table1CustNo: TAutoIncField;
    Table1Company: TStringField;
    Query1: TQuery;
    StoredProc1: TStoredProc;
    UpdateSQL1: TUpdateSQL;
    BatchMove1: TBatchMove;
    procedure Query1UpdateRecord(DataSet: TDataSet; UpdateKind: TUpdateKind;
      var UpdateAction: TUpdateAction);
  private
    procedure DoSites;
  end;

var
  FrmBdeSplit: TFrmBdeSplit;

implementation

{$R *.dfm}

procedure TFrmBdeSplit.Query1UpdateRecord(DataSet: TDataSet; UpdateKind: TUpdateKind;
  var UpdateAction: TUpdateAction);
begin
  case UpdateKind of
    ukModify: UpdateAction := uaApplied;
    ukInsert: UpdateAction := uaSkip;
    ukDelete: UpdateAction := uaFail;
  end;
end;

procedure TFrmBdeSplit.DoSites;
var
  vCursor: TDBScreenCursor;
  vStream: TBlobStream;
begin
  vCursor := dcrHourGlass;
  Session.FindDatabase('DBDEMOS');
  Database1.TransIsolation := tiDirtyRead;
  Database1.Execute('select 1 from rdb$database');
  Table1.UpdateRecordTypes := [rtModified];
  BatchMove1.Mode := batAppendUpdate;
  try
    vStream := TBlobStream.Create(nil, bmRead);
    vStream.Free;
  except
    on E: EDBEngineError do
      vCursor := dcrDefault;
  end;
end;

end.