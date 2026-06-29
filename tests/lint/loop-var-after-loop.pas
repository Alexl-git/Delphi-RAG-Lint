unit loopvarafterloop;
interface
implementation
procedure P;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to 10 do s := s + i;
  s := s + i;
  Writeln(s);
end;
procedure Q;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to 10 do s := s + i;
  i := 0;
  s := s + i;
  Writeln(s);
end;
end.
