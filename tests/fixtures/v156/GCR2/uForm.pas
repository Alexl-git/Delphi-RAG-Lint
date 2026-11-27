unit uForm;

interface

uses
  System.Classes, Vcl.Forms, Data.DB, FireDAC.Comp.Client, uMod, { uGhost is not used: } uTwin, uGone;

type
  TfrmMain = class(TForm)
    tblLocal: TFDTable;
    tblLocalID: TIntegerField;
    tblLocalCUST_ID: TIntegerField;
    tblLocalCUST: TStringField;
    memOrders: TFDMemTable;
    memOrdersID: TIntegerField;
    memOrdersQTY: TIntegerField;
    memTwin: TFDMemTable;
    memTwinID: TIntegerField;
    memGhost: TFDMemTable;
    memGhostID: TIntegerField;
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
  memOrders.CopyDataSet(dmMod.tblOrders);
  memTwin.CopyDataSet(dmTwin.tblTwin);
  memGhost.CopyDataSet(dmGhost.tblGhost);
  memGone.CopyDataSet(dmGone.tblGone);
end;

end.
