unit basic;

interface

procedure Bad(var A, B: Integer);

implementation

procedure Bad(var A, B: Integer);
begin
  A := B;
  B := A;
end;

end.
