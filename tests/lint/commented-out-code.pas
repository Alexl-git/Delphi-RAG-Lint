unit commout;
interface
implementation
procedure P;
var X: Integer;
begin
  // X := 42;
  { DoSomething(X); }
  X := 1;
  // this is a prose note
  // see Foo (1, 2);
  {$IFDEF DEBUG}
  X := 2;
  {$ENDIF}
end;
end.
