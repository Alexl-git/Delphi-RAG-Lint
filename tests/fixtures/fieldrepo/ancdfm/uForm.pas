unit uForm;

interface

uses
  System.Classes, Vcl.Forms, Data.DB, FireDAC.Comp.Client, uDerived, uThird;

type
  TfrmMain = class(TForm)
    tblLocal: TFDTable;
    tblLocalID: TIntegerField;
    tblLocalCUST_ID: TIntegerField;
    tblLocalCUST: TStringField;
    memOrders: TFDMemTable;
    memOrdersID: TIntegerField;
    memOrdersNOTE: TStringField;
    memCust: TFDMemTable;
    memCustNAME: TStringField;
    memDeep: TFDMemTable;
    memDeepQTY: TIntegerField;
    memItems: TFDMemTable;
    memItemsCODE: TStringField;
    memAtt: TFDMemTable;
    memAttID: TIntegerField;
    memAmb: TFDMemTable;
    memAmbID: TIntegerField;
    memNoUnit: TFDMemTable;
    memNoUnitID: TIntegerField;
    memOrphan: TFDMemTable;
    memOrphanID: TIntegerField;
    memGone: TFDMemTable;
    memGoneID: TIntegerField;
    procedure FormCreate(Sender: TObject);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  memOrders.CopyDataSet(dmDerived.tblOrders, [coStructure, coRestart, coAppend]);
  memCust.CopyDataSet(dmDerived.tblCust);
  memDeep.CloneCursor(dmThird.tblOrders);
  memItems.CopyDataSet(dmDerived.qryItems);
  memAtt.AttachTable(tblLocal.Table, nil);
  memAmb.CopyDataSet(dmAmbChild.tblAmb);
  memNoUnit.CopyDataSet(dmNoUnit.tblOrders);
  memOrphan.CopyDataSet(dmOrphan.tblOrders);
  memGone.CopyDataSet(dmDerived.tblGone);
end;

end.
