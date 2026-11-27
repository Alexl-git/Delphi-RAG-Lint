unit uForm;

interface

uses
  System.Classes, Vcl.Forms, Data.DB, FireDAC.Comp.Client, uMod, uTwo, uMacro;

type
  TfrmMain = class(TForm)
    tblLocal: TFDTable;
    tblLocalID: TIntegerField;
    tblLocalCUST_ID: TIntegerField;
    tblLocalCUST: TStringField;
    memOrders: TFDMemTable;
    memOrdersID: TIntegerField;
    memOrdersQTY: TIntegerField;
    memTwo: TFDMemTable;
    memTwoID: TIntegerField;
    memMacro: TFDMemTable;
    memMacroID: TIntegerField;
    procedure FormCreate(Sender: TObject);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  memOrders.CopyDataSet(dmMod.tblOrders);
  memTwo.CopyDataSet(dmTwo.tblTwo);
  memMacro.CopyDataSet(dmMacro.tblMacro);
end;

end.
