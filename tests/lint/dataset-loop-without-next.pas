unit DatasetLoopWithoutNext;

interface

implementation

uses
  Data.DB, FireDAC.Comp.Client;

procedure BadNoNext(Q: TFDQuery);
begin
  while not Q.Eof do
  begin
    Total := Total + Q.FieldByName('A').AsInteger;
  end;
end;

procedure BadContinueSkipsNext(Q: TFDQuery);
begin
  while not Q.Eof do
  begin
    if Q.FieldByName('A').IsNull then
      Continue;
    Total := Total + Q.FieldByName('A').AsInteger;
    Q.Next;
  end;
end;

procedure BadWithNoNext(Q: TFDQuery);
begin
  with Q do
    while not Eof do
      Total := Total + FieldByName('A').AsInteger;
end;

procedure BadRepeat(Q: TFDQuery);
begin
  repeat
    Total := Total + Q.FieldByName('A').AsInteger;
  until Q.Eof;
end;

procedure GoodNext(Q: TFDQuery);
begin
  while not Q.Eof do
  begin
    Total := Total + Q.FieldByName('A').AsInteger;
    Q.Next;
  end;
end;

procedure GoodDelete(Q: TFDQuery);
begin
  while not Q.Eof do
    Q.Delete;
end;

procedure GoodBreak(Q: TFDQuery);
begin
  while not Q.Eof do
  begin
    Found := Q.FieldByName('A').AsInteger = 1;
    Break;
  end;
end;

procedure GoodWithNext(Q: TFDQuery);
begin
  with Q do
    while not Eof do
    begin
      Total := Total + FieldByName('A').AsInteger;
      Next;
    end;
end;

procedure GoodContinueAfterNext(Q: TFDQuery);
begin
  while not Q.Eof do
  begin
    Total := Total + 1;
    Q.Next;
    if Q.Eof then
      Continue;
  end;
end;

procedure GoodNextInFinally(Q: TFDQuery);
begin
  while not Q.Eof do
  begin
    try
      if Q.FieldByName('A').IsNull then
        Continue;
      Total := Total + 1;
    finally
      Q.Next;
    end;
  end;
end;

procedure GoodPassedAway(Q: TFDQuery);
begin
  while not Q.Eof do
    Advance(Q);
end;

procedure GoodRepeatNext(Q: TFDQuery);
begin
  repeat
    Total := Total + 1;
    Q.Next;
  until Q.Eof;
end;

procedure GoodNextThenContinue(Q: TFDQuery);
begin
  while not Q.Eof do
  begin
    if Q.FieldByName(A).IsNull then
    begin
      LogSkip;
      Q.Next;
      Continue;
    end;
    Total := Total + 1;
    Q.Next;
  end;
end;

end.
