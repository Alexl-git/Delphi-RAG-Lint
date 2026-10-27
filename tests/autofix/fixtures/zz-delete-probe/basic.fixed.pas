unit basic;

interface

implementation

procedure ProbeNoop(N: Integer);
begin
end;

procedure P(var X: Integer);
begin
  X := 1;
  Inc(X);
end;

end.
