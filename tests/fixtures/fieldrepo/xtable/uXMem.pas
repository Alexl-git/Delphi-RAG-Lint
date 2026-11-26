unit uXMem;

interface

uses
  Forms, DB, FireDAC.Comp.Client, kbmMemTable;

type
  TfrmXMem = class(TForm)
    tblChart: TFDTable;
    qryJ: TFDQuery;
    memA: TkbmMemTable;
    memB: TkbmMemTable;
    memC1: TkbmMemTable;
    memC2: TkbmMemTable;
    memD: TkbmMemTable;
    memE: TkbmMemTable;
    memF: TFDMemTable;
    memG: TFDMemTable;
    memH: TFDMemTable;
    memI: TFDMemTable;
    memJ: TFDMemTable;
    memK: TFDMemTable;
    memL: TFDMemTable;
    tblCalc: TFDTable;
    procedure memACalcFields(DataSet: TDataSet);
    procedure tblCalcCalcFields(DataSet: TDataSet);
  private
    TblArr: array[0..1] of TFDTable;
    procedure Load;
  end;

implementation

{$R *.dfm}

procedure TfrmXMem.memACalcFields(DataSet: TDataSet);
begin
  memAHALF.AsFloat := memARVAL.AsFloat / 2;
end;

procedure TfrmXMem.tblCalcCalcFields(DataSet: TDataSet);
begin
end;

procedure TfrmXMem.Load;
begin
  memD.AttachTable(tblChart);
  memE.AttachTable(TblArr[0]);
  memF.CopyDataSet({ dmlGlb.qryJ }tblChart, [coStructure, coAppend]);
  memF.FieldByName('RVAL').AsFloat := 0;
  memG.CloneCursor(qryJ, False);
  memH.Data := tblChart.Data;
  memI.CopyData(tblChart);
  memJ.AppendData(tblChart);
  memK.CopyDataSet(tblChart);
  memK.CopyDataSet(qryJ);
  Self.memL.CloneCursor(Self.tblChart);
  // memL.CopyDataSet(qryJ);
end;

end.
