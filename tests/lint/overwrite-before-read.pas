unit overwritebeforeread;
interface
implementation
procedure P;
var x: Integer;
begin
  x := 1;
  x := 2;
  Writeln(x);
end;
end.
