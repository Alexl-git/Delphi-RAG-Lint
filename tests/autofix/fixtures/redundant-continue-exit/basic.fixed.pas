unit basic;

interface

procedure P(N: Integer);

implementation

procedure P(N: Integer);
var
  I: Integer;
begin
  for I := 0 to N do
  begin
    Writeln(I);
    // trailing note
  end;
  Writeln('x');
end;

end.
