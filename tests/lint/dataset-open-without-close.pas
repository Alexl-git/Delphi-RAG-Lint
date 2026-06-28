unit DatasetOpenWithoutClose;

interface

implementation

procedure Bad;
var
  Q: TFDQuery;
begin
  Q.Open;
  Q.First;
end;

procedure Good;
var
  Q: TFDQuery;
begin
  Q.Open;
  try
    Q.First;
  finally
    Q.Close;
  end;
end;

end.
