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

end.
