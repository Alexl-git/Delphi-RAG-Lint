unit inlinevar;

interface

procedure P;

implementation

{ The dead store is the initializer of an inline var: deleting the statement deletes
  the DECLARATION and the unit no longer compiles. Declined. }
procedure P;
begin
  var X: Integer := 1;
  X := 2;
  Writeln(X);
end;

end.
