unit TooManyExitPoints;

interface

implementation

procedure Bad(N: Integer);
begin
  if N = 1 then Exit;
  if N = 2 then Exit;
  if N = 3 then Exit;
  if N = 4 then Exit;
  if N = 5 then Exit;
  if N = 6 then Exit;
end;

procedure Good(N: Integer);
begin
  if N = 1 then Exit;
  Writeln(N);
end;

end.
