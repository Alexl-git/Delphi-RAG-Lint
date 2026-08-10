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

{ DESTROYING a dataset closes it. TDataSet.Destroy calls Close before freeing,
  so none of the three below leaks a cursor -- they are the ordinary Delphi
  idiom, and the rule used to flag every one of them. 95 findings on drag-lint's
  own source were exactly this shape, each telling the reader to add a Close the
  language already guarantees. }
procedure GoodFreeInFinally;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Open;
    Q.First;
  finally
    Q.Free;
  end;
end;

procedure GoodFreeAndNilInFinally;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Open;
  finally
    FreeAndNil(Q);
  end;
end;

procedure GoodDisposeOfInFinally;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Open;
  finally
    Q.DisposeOf;
  end;
end;

{ THE CONTROL, and the assertion that matters most here: a Free that is NOT in a
  finally protects nothing on the exception path, so the finding must still
  fire. Without this, "recognise Free" would be indistinguishable from "switch
  the rule off". }
procedure BadFreeOutsideFinally;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  Q.Open;
  Q.First;
  Q.Free;
end;

end.
