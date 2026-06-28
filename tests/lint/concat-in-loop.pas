unit ConcatInLoop;

interface

implementation

procedure Bad;
var
  S: string;
  I: Integer;
begin
  for I := 1 to 100 do
    S := S + IntToStr(I);
  S := S + 'more';
end;

procedure Good;
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  for I := 1 to 100 do
    SL.Add(IntToStr(I));
  // SL.Text is the accumulated result
end;

end.
