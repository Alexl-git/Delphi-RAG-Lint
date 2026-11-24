unit ArrayDml;
interface
uses SqlStubs;
procedure Batches(Q: TFDQuery; N: Integer);
procedure Looked(Q: TFDQuery; N: Integer);
implementation
procedure Batches(Q: TFDQuery; N: Integer);
var
  I: Integer;
begin
  for I := 0 to N do Q.Execute(100);
end;

procedure Looked(Q: TFDQuery; N: Integer);
var
  I: Integer;
begin
  for I := 0 to N do
  begin
    Q.ParamByName('A').AsInteger := I; // FIRE field-by-name-in-loop
    Q.ParamByName('B').AsInteger := I;
  end;
  for I := 0 to N do
  begin
    Q.SQL.Text := 'SELECT :A';
    Q.ParamByName('A').AsInteger := I;
  end;
  Q.ParamByName('A').AsInteger := 1;
  for I := 0 to N do
    Q.ParamByName('A').AsInteger := Q.FieldByName('B').AsInteger; // FIRE field-by-name-in-loop
end;
end.