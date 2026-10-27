unit basic;

interface

implementation

procedure ProbeNoop(N: Integer);
begin
end;

procedure P(var X: Integer);
begin
  ProbeNoop(0);
  X := 1; ProbeNoop(1);
  Inc(X);
end;

end.
