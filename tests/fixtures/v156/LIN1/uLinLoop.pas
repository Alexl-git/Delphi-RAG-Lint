unit uLinLoop;

{ Fixture of tests\autotest\run_v156_LIN1.ps1 (1.56 lane LIN-1, lineage model; SPEC-LIN 5.2 "uLinLoop").
  Never compiled: it is indexed. The tests find their lines by the M-... markers, so lines may move. }

interface

uses
  System.Classes, System.SysUtils, Data.DB, FireDAC.Comp.Client, Vcl.Forms;

type
  TfLinLoop = class(TForm)
    tblOrders: TFDQuery;
    tblOrdersQTY: TFloatField;
    tblOrdersTOTAL: TFloatField;
    tblOrdersCOUNT2: TIntegerField;
    tblOrdersSEQ: TFloatField;
    qryLines: TFDQuery;
    qryLinesAMOUNT: TFloatField;
    qryLinesQTY: TIntegerField;
    procedure tblOrdersAfterOpen(DataSet: TDataSet);
  public
    procedure Renumber;
  end;

var
  fLinLoop: TfLinLoop;

implementation

{$R *.dfm}

procedure TfLinLoop.tblOrdersAfterOpen(DataSet: TDataSet);
var
  vSum: Double;
begin
  vSum := 0;
  qryLines.First;
  while not qryLines.Eof do { M-LOOP }
  begin
    vSum := vSum + qryLinesAMOUNT.AsFloat * qryLinesQTY.AsInteger; { M-ACC }
    tblOrdersCOUNT2.AsInteger := tblOrdersCOUNT2.AsInteger + qryLinesQTY.AsInteger; { M-COUNT2 }
    qryLines.Next;
  end;
  tblOrdersTOTAL.AsFloat := vSum; { M-TOTAL }
end;

procedure TfLinLoop.Renumber;
begin
  tblOrders.First;
  while not tblOrders.Eof do { M-OWNLOOP }
  begin
    tblOrdersSEQ.AsFloat := tblOrdersQTY.AsFloat + 1; { M-SEQ }
    tblOrders.Next;
  end;
end;

end.
