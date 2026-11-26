unit uXJoin;

interface

uses
  Forms, DB, FireDAC.Comp.Client;

type
  TfrmXJoin = class(TForm)
    qryChart: TFDQuery;
    qryWhere: TFDQuery;
    qryOr: TFDQuery;
    qryGroup: TFDQuery;
    qryPair: TFDQuery;
    qryTwice: TFDQuery;
    procedure qryChartCalcFields(DataSet: TDataSet);
    procedure qryWhereCalcFields(DataSet: TDataSet);
    procedure qryOrCalcFields(DataSet: TDataSet);
    procedure qryGroupCalcFields(DataSet: TDataSet);
    procedure qryPairCalcFields(DataSet: TDataSet);
    procedure qryTwiceCalcFields(DataSet: TDataSet);
  end;

implementation

{$R *.dfm}

procedure TfrmXJoin.qryChartCalcFields(DataSet: TDataSet);
begin
  qryChartFTRNAME.AsString := FloatToStr(qryChartRVAL.AsFloat) + IntToStr(qryChartDECIMALS.AsInteger);
  qryChartDOUBLED.AsFloat := qryChartRVAL.AsFloat * 2;
  qryChartLABELX.AsString := qryChartDOUBLED.AsString + qryChartNOTATION.AsString;
end;

procedure TfrmXJoin.qryWhereCalcFields(DataSet: TDataSet);
begin
  qryWhereALTNAME.AsString := FloatToStr(qryWhereRVAL.AsFloat) + IntToStr(qryWhereDECIMALS.AsInteger);
end;

procedure TfrmXJoin.qryOrCalcFields(DataSet: TDataSet);
begin
  qryOrORNAME.AsString := FloatToStr(qryOrRVAL.AsFloat) + IntToStr(qryOrDECIMALS.AsInteger);
end;

procedure TfrmXJoin.qryGroupCalcFields(DataSet: TDataSet);
begin
  qryGroupGRTXT.AsString := FloatToStr(qryGroupRVAL.AsFloat) + qryGroupGRNAME.AsString;
  qryGroupNKTXT.AsString := FloatToStr(qryGroupRVAL.AsFloat) + qryGroupNKNAME.AsString;
end;

procedure TfrmXJoin.qryPairCalcFields(DataSet: TDataSet);
begin
  qryPairPAIRTXT.AsString := qryPairANAME.AsString + qryPairBNAME.AsString;
end;

procedure TfrmXJoin.qryTwiceCalcFields(DataSet: TDataSet);
begin
  qryTwiceTWOMSC.AsString := FloatToStr(qryTwiceRVAL.AsFloat) + qryTwiceDECIMALS.AsString + qryTwiceNOTATION.AsString;
end;

end.
