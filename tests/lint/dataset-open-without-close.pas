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

{ A FIELD named Open is not a dataset open. INBOX 2026-09-17 section 2: a
  record with Open: TArray<...> read as AState.Open[High(AState.Open)]
  fired EIGHT times on drag-lint's own source -- the walk matched every
  exprDot whose rhs spelt Open, wherever it sat. Only a bare X.Open; /
  X.Open(); STATEMENT is a dataset open; an X.Open that is indexed, passed
  as an argument, or assigned is an operand and must be ignored. }
type
  TOpenHandler = record
    SawStmt: Boolean;
  end;
  THandlersScanState = record
    Open: TArray<TOpenHandler>;
  end;

procedure GoodOpenIsAField(var AState: THandlersScanState);
var
  N: Integer;
begin
  AState.Open[High(AState.Open)].SawStmt:= True;
  N:= Length(AState.Open);
  if N > 0 then
    AState.Open[0].SawStmt:= False;
end;

end.