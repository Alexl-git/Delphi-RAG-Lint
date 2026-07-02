unit loopcontrolflag;
interface
implementation

procedure PositiveWhileFlag;
var
  Found: Boolean;
  I, N: Integer;
begin
  I := 0;
  N := 10;
  Found := False;
  while not Found do
  begin
    Inc(I);
    if I = N then
      Found := True;
  end;
end;

procedure PositiveRepeatFlag;
var
  Stop: Boolean;
  I: Integer;
begin
  I := 0;
  Stop := False;
  repeat
    Inc(I);
    if I > 10 then
      Stop := True;
  until Stop = True;
end;

procedure NegativeCounterLoop;
var
  I, N: Integer;
begin
  I := 0;
  N := 10;
  while I < N do
    Inc(I);
end;

procedure NegativeEofLoop;
var
  F: TextFile;
begin
  while not Eof(F) do
  begin
    Readln(F);
  end;
end;

end.
