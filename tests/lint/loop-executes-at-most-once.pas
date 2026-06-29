unit LoopAtMostOnce;

interface

implementation

procedure Bad;
var
  I: Integer;
begin
  for I := 1 to 10 do
  begin
    Exit;
    Writeln(I);
  end;
  while I > 0 do
    Break;
end;

procedure Good;
var
  I: Integer;
begin
  for I := 1 to 10 do
  begin
    if I = 5 then Exit;
    Writeln(I);
  end;
end;

procedure GoodCase(N: Integer);
begin
  while N > 0 do
  begin
    case N of
      1: N := 0;
      2: N := N - 1;
    end;
    Exit;
  end;
end;

end.
