unit uJoin;

interface

uses
  Forms, DB, DBTables, FireDAC.Comp.Client;

type
  TfrmJoin = class(TForm)
    qryJ: TFDQuery;
    procedure qryJCalcFields(DataSet: TDataSet);
    procedure qryJOQGetText(Sender: TField; var Text: string; DisplayText: Boolean);
    procedure qryJNameGetText(Sender: TField; var Text: string; DisplayText: Boolean);
  end;

implementation

{$R *.dfm}

procedure TfrmJoin.qryJCalcFields(DataSet: TDataSet);
begin
  qryJTotal.AsFloat := qryJOQ.AsInteger * 1.5;
  qryJTwice.AsFloat := qryJTotal.AsFloat * 2;
  qryJLabel.AsString := qryJName.AsString + qryJPrice.AsString;
  qryJMixed.AsString := qryJName.AsString + qryJOQ.AsString;
  qryJComp.AsInteger := qryJDbl.AsInteger + 1;
  qryJConst.AsInteger := 7;
  qryJLoop1.AsInteger := qryJLoop2.AsInteger + 1;
  qryJLoop2.AsInteger := qryJLoop1.AsInteger + 1;
  if qryJCyc2.IsNull then
    qryJCyc1.AsInteger := qryJOQ.AsInteger
  else
    qryJCyc1.AsInteger := qryJCyc2.AsInteger;
  qryJCyc2.AsInteger := qryJCyc1.AsInteger + qryJID.AsInteger;
  try
    qryJSlice.AsInteger := qryJOQ.AsInteger;
    if qryJName.AsString = '' then
      qryJOther.AsInteger := 1
    else
      qryJOther.AsInteger := 2;
  finally
  end;
end;

procedure TfrmJoin.qryJOQGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  Text := qryJID.AsString + Sender.AsString;
end;

procedure TfrmJoin.qryJNameGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  Text := Sender.AsString + qryJOQ.AsString;
end;

end.
