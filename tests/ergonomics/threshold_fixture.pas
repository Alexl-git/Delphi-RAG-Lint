unit threshold_fixture;
interface
procedure FourParams(pA, pB, pC, pD: Integer);
implementation
procedure FourParams(pA, pB, pC, pD: Integer);
begin
  if pA > 0 then Writeln(pB + pC + pD);
end;
end.
