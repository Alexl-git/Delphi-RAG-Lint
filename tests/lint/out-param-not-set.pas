unit outparamnotset;
interface
implementation
procedure P1(out a: Integer);
begin
end;
procedure P2(out a: Integer; b: Boolean);
begin
  if b then a := 1 else a := 2;
end;
procedure P3(var a: Integer);
begin
end;
end.
