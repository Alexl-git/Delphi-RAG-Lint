unit uGrid;

interface

uses
  Forms, DB, DBTables, cxGridDBTableView;

implementation

{$R *.dfm}

procedure TfrmGrid.tblOCalcFields(DataSet: TDataSet);
begin
  if tblOQTY.IsNull then
    tblOTOTAL.Clear
  else
    tblOTOTAL.AsFloat := tblOQTY.AsInteger * 2;
end;

procedure TfrmGrid.tblOQTYChange(Sender: TField);
begin
  tblONOTE.AsString := 'q' + DataSetOf(Sender, tblOQTY);
end;

procedure TfrmGrid.tblOQTYGetText(Sender: TField; var Text: string; DisplayText: Boolean);
begin
  Text := Sender.AsString;
end;

procedure TfrmGrid.tblOQTYSetText(Fld: TField; const S: string);
begin
  Fld.AsString := Trim(S);
end;

procedure TfrmGrid.tblOQTYValidate(Sender: TField);
begin
  if Sender.AsInteger < 0 then
    Abort;
end;

procedure TfrmGrid.colQtyGetDisplayText(Sender: TcxCustomGridTableItem; ARecord: TcxCustomGridRecord; var S: string);
begin
  if tblOQTY.IsNull then
    S := '-';
end;

procedure TfrmGrid.colQtyCustomDrawCell(Sender: TcxCustomGridTableView; ACanvas: TcxCanvas;
  AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean);
begin
  ACanvas.Font.Color := clRed;
end;

procedure TfrmGrid.colDrawCustomDrawCell(Sender: TcxCustomGridTableView; ACanvas: TcxCanvas;
  AViewInfo: TcxGridTableDataCellViewInfo; var ADone: Boolean);
begin
  ADone := True;
end;

end.
