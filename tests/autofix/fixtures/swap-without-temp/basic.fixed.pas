unit basic;

interface

procedure Bad(var A, B: Integer);

implementation

procedure Bad(var A, B: Integer);
begin
  var LSwap := A;
  A := B;
  B := LSwap;
end;

end.
